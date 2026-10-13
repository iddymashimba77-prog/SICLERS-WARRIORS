import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../../../../core/l10n/app_localizations.dart';
import '../../../auth/domain/auth_types.dart';
import '../../data/education_repository.dart';

/// Create or edit a Warrior Academy article (FR-EDU-005).
///
/// Pushed via `MaterialPageRoute` with `null` [article] to create a draft, or
/// with an existing draft to edit it. Pops `true` when something was written;
/// the caller both refreshes and confirms, because a SnackBar raised here
/// would disappear with this route.
///
/// The length limits are the server's (`education.serializers.TITLE_MAX`,
/// `BODY_MAX`), duplicated here so an over-long article is caught while the
/// doctor is typing rather than after a round trip. The server still
/// sanitises the HTML on write — this is a courtesy, not the control.
class ArticleFormPage extends StatefulWidget {
  const ArticleFormPage({
    super.key,
    required this.accessToken,
    required this.repository,
    this.article,
  });

  final String accessToken;
  final EducationRepository repository;
  final EducationalContent? article;

  static const int titleMax = 200;
  static const int bodyMax = 50000;

  @override
  State<ArticleFormPage> createState() => _ArticleFormPageState();
}

class _ArticleFormPageState extends State<ArticleFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _cover;
  String _category = '';
  List<EducationCategory> _categories = const [];
  bool _loadingCategories = true;
  bool _saving = false;
  String? _categoryError;

  bool get _isEdit => widget.article != null;

  @override
  void initState() {
    super.initState();
    final article = widget.article;
    _title = TextEditingController(text: article?.title ?? '');
    _body = TextEditingController(text: article?.body ?? '');
    _cover = TextEditingController(text: article?.coverUrl ?? '');
    _category = article?.category.code ?? '';
    _loadCategories();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _cover.dispose();
    super.dispose();
  }

  /// The category list is a separate reference endpoint: an article stores a
  /// code, and the picker must send codes the server recognises.
  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });
    try {
      final categories = await widget.repository.listCategories(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        // An existing article can hold a category that has since been retired.
        // Keep it in the list so editing the body does not silently re-file the
        // article elsewhere — but only if it is missing, or the dropdown would
        // hold the same code twice.
        final known = categories.any((c) => c.code == _category);
        if (!known && _category.isNotEmpty) {
          _categories = [
            EducationCategory.fromJson({'code': _category, 'name': _category}),
            ...categories,
          ];
        } else {
          _categories = categories;
        }
        if (_category.isEmpty && categories.isNotEmpty) {
          _category = categories.first.code;
        }
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoryError = '$e';
        _loadingCategories = false;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Surface the server's own validation message when there is one; a blanket
  /// "could not save" would hide which field the server objected to.
  String _messageFor(Object error, String fallbackKey) {
    final s = AppLocalizations.of(context);
    if (error is! AuthException) return s.tr(fallbackKey);
    final message = error.message.trim();
    if (message.isNotEmpty && !message.contains('Exception')) return message;
    return s.tr(fallbackKey);
  }

  String? _validateTitle(String? raw) {
    final s = AppLocalizations.of(context);
    final value = (raw ?? '').trim();
    if (value.isEmpty) return s.tr('edu.author.titleRequired');
    if (value.length > ArticleFormPage.titleMax) {
      return s.tr(
        'edu.author.titleTooLong',
        args: {'max': '${ArticleFormPage.titleMax}'},
      );
    }
    return null;
  }

  String? _validateBody(String? raw) {
    final s = AppLocalizations.of(context);
    final value = (raw ?? '').trim();
    if (value.isEmpty) return s.tr('edu.author.bodyRequired');
    if (value.length > ArticleFormPage.bodyMax) {
      return s.tr(
        'edu.author.bodyTooLong',
        args: {'max': '${ArticleFormPage.bodyMax}'},
      );
    }
    return null;
  }

  String? _validateCover(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      return AppLocalizations.of(context).tr('edu.author.coverInvalid');
    }
    return null;
  }

  Future<void> _save() async {
    final s = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_category.isEmpty) {
      _toast(s.tr('edu.author.categoryRequired'));
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.article;
      if (existing == null) {
        await widget.repository.createContent(
          access: widget.accessToken,
          title: _title.text.trim(),
          body: _body.text.trim(),
          category: _category,
          coverUrl: _cover.text.trim(),
        );
      } else {
        await widget.repository.updateContent(
          access: widget.accessToken,
          uid: existing.uid,
          title: _title.text.trim(),
          body: _body.text.trim(),
          category: _category,
          coverUrl: _cover.text.trim(),
        );
      }
      if (!mounted) return;
      // No toast here: this route is about to pop, and the SnackBar would be
      // torn down with it. The caller confirms the write instead.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(_messageFor(e, 'edu.author.failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tr(_isEdit ? 'edu.author.edit' : 'edu.author.new')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              maxLength: ArticleFormPage.titleMax,
              // Deliberately not `MaxLengthEnforcement.enforced`: the default
              // silently cuts a long paste, and losing the end of a sentence in
              // a patient handout is worse than a red counter. The counter turns
              // red and the validator explains the limit on save instead.
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: s.tr('edu.author.title'),
                helperText: s.tr('edu.author.titleHint'),
              ),
              validator: _validateTitle,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _loadingCategories ? null : _category,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.tr('edu.author.category')),
              items: [
                for (final category in _categories)
                  DropdownMenuItem(
                    value: category.code,
                    child: Text(
                      category.name.isEmpty ? category.code : category.name,
                    ),
                  ),
              ],
              onChanged: _loadingCategories
                  ? null
                  : (value) => setState(() => _category = value ?? ''),
              validator: (value) =>
                  (value == null || value.isEmpty)
                      ? s.tr('edu.author.categoryRequired')
                      : null,
            ),
            if (_categoryError != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.tr('edu.author.categoryLoadFailed'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(onPressed: _loadCategories, child: Text(s.tr('common.retry'))),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _body,
              minLines: 8,
              maxLines: 20,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: s.tr('edu.author.body'),
                helperText: s.tr('edu.author.bodyHint'),
                alignLabelWithHint: true,
              ),
              validator: _validateBody,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cover,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: s.tr('edu.author.cover'),
                helperText: s.tr('edu.author.coverHint'),
              ),
              validator: _validateCover,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(s.tr(_saving ? 'edu.author.saving' : 'edu.author.save')),
            ),
          ],
        ),
      ),
    );
  }
}