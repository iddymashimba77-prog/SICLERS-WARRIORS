import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../emergency/presentation/pages/emergency_page.dart';
import '../../data/ai_repository.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// AI coach (FR-AI-001/002/006) — a real chat surface over `POST /api/ai/chat/`.
///
/// Replaces the module placeholder: every turn is a live request, and the
/// screen renders the backend's own safety and provenance fields rather than
/// inventing any — emergency blocks open the SOS pathway, refusals are shown
/// as refusals, approved-knowledge citations are listed, and the non-diagnosis
/// disclaimer stays pinned above the composer.
class AiAssistantPage extends StatelessWidget {
  const AiAssistantPage({super.key, this.authController, this.repository});

  static const String routeName = '/ai-assistant';

  final AuthController? authController;
  final AiRepository? repository;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppTopBar(
        title: s.tr('act.aiCoach'),
        avatarName: session.displayName,
        avatarImageUrl: session.photoUrl,
      ),
      body: SafeArea(
        child: AiAssistantView(
          accessToken: token,
          repository: repository ?? AiRepository(),
        ),
      ),
    );
  }
}

/// One use-case the API accepts; the label is localised, the code is not.
class _UseCase {
  const _UseCase(this.code, this.labelKey);

  final String code;
  final String labelKey;
}

const List<_UseCase> _useCases = [
  _UseCase('education', 'ai.useEducation'),
  _UseCase('medication_education', 'ai.useMedication'),
  _UseCase('health_questions', 'ai.useHealth'),
  _UseCase('appointment_preparation', 'ai.useAppointments'),
  _UseCase('health_summary', 'ai.useSummary'),
  _UseCase('symptom_assistance', 'ai.useSymptoms'),
  _UseCase('insight_explanation', 'ai.useInsight'),
];

enum _EntryKind { user, assistant, error }

class _ChatEntry {
  const _ChatEntry.user(this.text) : kind = _EntryKind.user, turn = null;
  const _ChatEntry.assistant(this.turn)
      : kind = _EntryKind.assistant,
        text = '';
  const _ChatEntry.error(this.text) : kind = _EntryKind.error, turn = null;

  final _EntryKind kind;
  final String text;
  final AiChatTurn? turn;
}

class AiAssistantView extends StatefulWidget {
  const AiAssistantView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final AiRepository repository;

  @override
  State<AiAssistantView> createState() => _AiAssistantViewState();
}

class _AiAssistantViewState extends State<AiAssistantView> {
  final TextEditingController _input = TextEditingController();
  final List<_ChatEntry> _entries = [];
  bool _sending = false;
  String _useCase = 'education';
  static const String _prefsKey = 'ai_assistant_chat_history';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_prefsKey);
      if (data == null || data.isEmpty) return;
      final list = jsonDecode(data) as List<dynamic>;
      final entries = <_ChatEntry>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final type = item['type'] as String?;
          final text = item['text'] as String? ?? '';
          if (type == 'user') {
            entries.add(_ChatEntry.user(text));
          } else if (type == 'assistant') {
            entries.add(_ChatEntry.error(text.isEmpty ? '...' : text));
            // skip complex turn reconstruction for now
          } else if (type == 'error') {
            entries.add(_ChatEntry.error(text));
          }
        }
      }
      if (entries.isNotEmpty && mounted) {
        setState(() {
          _entries.clear();
          _entries.addAll(entries);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = <Map<String, String>>[];
      for (final e in _entries.take(100)) {
        if (e.kind == _EntryKind.user) {
          list.add({'type': 'user', 'text': e.text});
        } else if (e.kind == _EntryKind.error) {
          list.add({'type': 'error', 'text': e.text});
        } else if (e.kind == _EntryKind.assistant && e.turn != null) {
          list.add({'type': 'assistant', 'text': e.turn!.message});
        }
      }
      await prefs.setString(_prefsKey, jsonEncode(list));
    } catch (_) {}
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send({String? preset}) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    final s = AppLocalizations.of(context);
    setState(() {
      _entries.add(_ChatEntry.user(text));
      _input.clear();
      _sending = true;
    });
    _saveHistory();
    try {
      final turn = await widget.repository.sendChat(
        access: widget.accessToken,
        message: text,
        useCase: _useCase,
        metric: _useCase == 'insight_explanation' ? 'medication_adherence' : null,
      );
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.assistant(turn));
        _sending = false;
      });
      _saveHistory();
    } on AiRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.error(e.isThrottled ? s.tr('ai.throttled') : e.message));
        _sending = false;
      });
      _saveHistory();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.error(s.tr('err.generic')));
        _sending = false;
      });
      _saveHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _entries.isEmpty ? _welcome(context) : _thread(context)),
        if (_sending) const LinearProgressIndicator(minHeight: 2),
        _disclaimer(context),
        _composer(context),
      ],
    );
  }

  // ------------------------------------------------------------- welcome

  Widget _welcome(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text(s.tr('ai.welcomeTitle'), style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.tr('ai.welcomeBody'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final key in const [
              'ai.suggestCrisis',
              'ai.suggestMeds',
              'ai.suggestAppt',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: OutlinedButton.icon(
                  onPressed: () => _send(preset: s.tr(key)),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(s.tr(key)),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- thread

  Widget _thread(BuildContext context) {
    final count = _entries.length;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: count,
      itemBuilder: (context, i) => _bubble(context, _entries[count - 1 - i]),
    );
  }

  Widget _bubble(BuildContext context, _ChatEntry entry) {
    switch (entry.kind) {
      case _EntryKind.user:
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: dark ? theme.colorScheme.primaryContainer : AppColors.navy,
              borderRadius: AppShapes.card,
              border: Border.all(
                color: dark
                    ? theme.colorScheme.primary.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              entry.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: dark
                    ? theme.colorScheme.onPrimaryContainer
                    : AppColors.textOnDark,
                height: 1.4,
              ),
            ),
          ),
        );
      case _EntryKind.error:
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: dark
                ? AppColors.emergency.withValues(alpha: .18)
                : AppColors.lightRed,
            borderRadius: AppShapes.card,
            border: Border.all(
              color: dark
                  ? AppColors.emergency.withValues(alpha: .60)
                  : AppColors.emergency.withValues(alpha: .35),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline,
                  color: dark
                      ? AppColors.emergency.withValues(alpha: .90)
                      : AppColors.emergency),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  entry.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      case _EntryKind.assistant:
        return _assistantBubble(context, entry.turn!);
    }
  }

  Widget _assistantBubble(BuildContext context, AiChatTurn turn) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: AppShapes.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy_outlined,
                  size: 18, color: AppColors.blue),
              const SizedBox(width: AppSpacing.xs),
              Text(
                s.tr('ai.coach'),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.blue),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            turn.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (turn.emergencyAction) ...[
            const SizedBox(height: AppSpacing.lg),
            _emergencyCallout(context),
          ] else if (turn.safetyBlocked) ...[
            const SizedBox(height: AppSpacing.lg),
            _refusalCallout(context),
          ],
          if (turn.sources.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.tr('ai.sources'),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final src in turn.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.menu_book_outlined,
                        size: 16, color: AppColors.blue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(src.title,
                              style: theme.textTheme.labelMedium),
                          if (src.snippet.isNotEmpty)
                            Text(
                              src.snippet,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (turn.limitation != null && turn.limitation!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.tr('ai.limitationNote'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emergencyCallout(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? theme.colorScheme.error : AppColors.emergency;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.emergency.withValues(alpha: .16)
            : AppColors.emergencyContainer,
        borderRadius: AppShapes.tile,
        border: Border.all(
          color: accent.withValues(alpha: dark ? .60 : .30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  s.tr('ai.emergencyTitle'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: dark ? theme.colorScheme.onSurface : AppColors.darkRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            s.tr('ai.emergencyBody'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(
                context, EmergencyPage.routeName),
            icon: const Icon(Icons.emergency, size: 18),
            label: Text(s.tr('ai.openEmergency')),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: dark
                  ? theme.colorScheme.onError
                  : AppColors.textOnEmergency,
            ),
          ),
        ],
      ),
    );
  }

  Widget _refusalCallout(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.warning.withValues(alpha: .18)
            : AppColors.lightAmber,
        borderRadius: AppShapes.tile,
        border: Border.all(
          color: dark
              ? AppColors.warning.withValues(alpha: .60)
              : AppColors.warning.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.block,
              size: 18,
              color: dark ? AppColors.warning.withValues(alpha: .90) : AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              s.tr('ai.blockedTitle'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ composer

  Widget _disclaimer(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Text(
        '${s.tr('ai.disclaimerLabel')}: ${s.tr('ai.disclaimer')}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final uc in _useCases)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(
                      label: Text(s.tr(uc.labelKey)),
                      selected: _useCase == uc.code,
                      onSelected: (_) => setState(() => _useCase = uc.code),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: s.tr('ai.placeholder'),
                    prefixIcon: const Icon(Icons.chat_bubble_outline),
                    border: OutlineInputBorder(
                      borderRadius: AppShapes.hero,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                tooltip: s.tr('ai.send'),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
