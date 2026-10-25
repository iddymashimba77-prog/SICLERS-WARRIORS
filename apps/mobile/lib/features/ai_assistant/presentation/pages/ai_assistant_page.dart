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

  List<AiConversation> _conversations = [];
  bool _loadingConversations = false;
  bool _loadingConversation = false;
  bool _sidebarOpen = true;
  String? _currentConversationUid;
  bool _restoredConversation = false;
  static const String _currentConversationKey =
      'ai_assistant_current_conversation';

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    if (mounted) setState(() => _loadingConversations = true);
    try {
      final list = await widget.repository.listConversations(widget.accessToken);
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loadingConversations = false;
      });
      if (!_restoredConversation) {
        _restoredConversation = true;
        await _restoreLastConversation();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingConversations = false);
    }
  }

  Future<void> _restoreLastConversation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(_currentConversationKey);
      if (uid == null || uid.isEmpty) return;
      final matches = _conversations.where((c) => c.uid == uid).toList();
      if (matches.isEmpty) return;
      await _openConversation(matches.first, closeSheet: false);
    } catch (_) {}
  }

  Future<void> _rememberCurrentConversation(String? uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid == null || uid.isEmpty) {
        await prefs.remove(_currentConversationKey);
      } else {
        await prefs.setString(_currentConversationKey, uid);
      }
    } catch (_) {}
  }

  void _startNewChat({bool closeSheet = true}) {
    setState(() {
      _entries.clear();
      _currentConversationUid = null;
      _loadingConversation = false;
    });
    _rememberCurrentConversation(null);
    if (closeSheet && MediaQuery.of(context).size.width < 900) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openConversation(AiConversation conversation,
      {bool closeSheet = true}) async {
    if (closeSheet && MediaQuery.of(context).size.width < 900) {
      Navigator.of(context).maybePop();
    }
    setState(() => _loadingConversation = true);
    try {
      final full =
          await widget.repository.getConversation(widget.accessToken, conversation.uid);
      if (!mounted) return;
      final entries = <_ChatEntry>[];
      for (final message in full.messages) {
        if (message.isUser) {
          entries.add(_ChatEntry.user(message.content));
        } else {
          entries.add(_ChatEntry.assistant(_turnFromStored(message)));
        }
      }
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _currentConversationUid = full.uid;
        _loadingConversation = false;
      });
      _rememberCurrentConversation(full.uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingConversation = false);
    }
  }

  AiChatTurn _turnFromStored(AiConversationMessage message) {
    final meta = message.meta;
    final safety = meta['safety'] as Map<String, dynamic>?;
    final rawSources = meta['sources'] as List<dynamic>? ?? const [];
    return AiChatTurn(
      assistantId: message.uid,
      useCase: (meta['use_case'] as String?) ?? 'education',
      message: message.content,
      disclaimer: '',
      emergencyAction: meta['emergency_action'] == true,
      emergencyCategories: [
        for (final c in (meta['emergency_categories'] as List<dynamic>? ?? const []))
          c.toString(),
      ],
      safetyBlocked: safety?['blocked'] == true,
      safetyReason: safety?['reason'] as String?,
      contextUsed: meta['context_used'] == true,
      limitation: meta['limitation'] as String?,
      sources: [
        for (final s in rawSources)
          AiSource.fromJson((s as Map<String, dynamic>?) ?? const {}),
      ],
    );
  }

  Future<void> _renameConversation(AiConversation conversation) async {
    final s = AppLocalizations.of(context);
    final currentTitle = conversation.displayTitle.isEmpty
        ? s.tr('ai.newConversation')
        : conversation.displayTitle;
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.tr('ai.renameConversation')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(labelText: s.tr('ai.titleLabel')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.tr('ai.cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(s.tr('ai.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle == null || newTitle.isEmpty) return;
    try {
      final updated = await widget.repository.renameConversation(
        widget.accessToken,
        conversation.uid,
        title: newTitle,
      );
      if (!mounted) return;
      setState(() {
        _conversations = [
          for (final c in _conversations)
            c.uid == updated.uid ? updated : c,
        ];
      });
    } catch (_) {}
  }

  Future<void> _deleteConversation(AiConversation conversation) async {
    final s = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.tr('ai.deleteConversation')),
        content: Text(s.tr('ai.deleteConversationBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.tr('ai.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.tr('ai.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository
          .deleteConversation(widget.accessToken, conversation.uid);
      if (!mounted) return;
      setState(() {
        _conversations =
            _conversations.where((c) => c.uid != conversation.uid).toList();
        if (_currentConversationUid == conversation.uid) {
          _entries.clear();
          _currentConversationUid = null;
        }
      });
      if (_currentConversationUid == null) {
        _rememberCurrentConversation(null);
      }
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
    try {
      final turn = await widget.repository.sendChat(
        access: widget.accessToken,
        message: text,
        useCase: _useCase,
        metric: _useCase == 'insight_explanation' ? 'medication_adherence' : null,
        conversationUid: _currentConversationUid,
      );
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.assistant(turn));
        _currentConversationUid =
            turn.conversationUid ?? _currentConversationUid;
        _sending = false;
      });
      _rememberCurrentConversation(_currentConversationUid);
        _loadConversations();
    } on AiRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.error(e.isThrottled ? s.tr('ai.throttled') : e.message));
        _sending = false;
      });
      } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries.add(_ChatEntry.error(s.tr('err.generic')));
        _sending = false;
      });
      }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final chat = Column(
      children: [
        _chatToolbar(context, isWide: isWide),
        Expanded(
          child: _loadingConversation
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? _welcome(context)
                  : _thread(context),
        ),
        if (_sending) const LinearProgressIndicator(minHeight: 2),
        _disclaimer(context),
        _composer(context),
      ],
    );
    return Row(
      children: [
        if (isWide && _sidebarOpen)
          SizedBox(width: 280, child: _sidebar(context, embedded: true)),
        Expanded(child: chat),
      ],
    );
  }

  Widget _chatToolbar(BuildContext context, {required bool isWide}) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: s.tr('ai.newChat'),
            onPressed: () => _startNewChat(closeSheet: false),
            icon: const Icon(Icons.add_comment_outlined),
          ),
          if (!isWide)
            IconButton(
              tooltip: s.tr('ai.history'),
              onPressed: () => _openSidebarSheet(context),
              icon: const Icon(Icons.history),
            ),
          const Spacer(),
          if (isWide)
            IconButton(
              tooltip: _sidebarOpen
                  ? s.tr('ai.hideHistory')
                  : s.tr('ai.showHistory'),
              onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
              icon: Icon(
                _sidebarOpen ? Icons.chevron_left : Icons.chevron_right,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openSidebarSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.75,
        child: _sidebar(sheetContext, embedded: false),
      ),
    );
  }

  Widget _sidebar(BuildContext context, {required bool embedded}) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: embedded
            ? Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.forum_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    s.tr('ai.conversations'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: s.tr('ai.newChat'),
                  onPressed: () => _startNewChat(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingConversations
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _conversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            s.tr('ai.noConversations'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs),
                        itemCount: _conversations.length,
                        itemBuilder: (context, i) => _conversationTile(
                          context,
                          _conversations[i],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _conversationTile(BuildContext context, AiConversation conversation) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = conversation.uid == _currentConversationUid;
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: ListTile(
        dense: true,
        selected: selected,
        leading: Icon(
          Icons.chat_bubble_outline,
          size: 18,
          color: selected
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          conversation.displayTitle.isEmpty
              ? s.tr('ai.newConversation')
              : conversation.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        subtitle: conversation.messageCount > 0
            ? Text(
                s.tr('ai.messagesCount',
                    args: {'count': '${conversation.messageCount}'}),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        onTap: () => _openConversation(conversation),
        trailing: PopupMenuButton<String>(
          tooltip: s.tr('ai.conversationOptions'),
          onSelected: (value) {
            if (value == 'rename') _renameConversation(conversation);
            if (value == 'delete') _deleteConversation(conversation);
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'rename', child: Text(s.tr('ai.rename'))),
            PopupMenuItem(value: 'delete', child: Text(s.tr('ai.delete'))),
          ],
        ),
      ),
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
