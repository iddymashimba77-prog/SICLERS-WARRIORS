import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/banners/page_banner_catalog.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../emergency/presentation/pages/emergency_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
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
          ownerKey: session.email ?? session.displayName,
          displayName: session.displayName,
          email: session.email,
          photoUrl: session.photoUrl,
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

/// One date bucket in the history sidebar (ChatGPT/Claude-style grouping).
class _ConversationGroup {
  const _ConversationGroup(this.labelKey, this.items);

  final String labelKey;
  final List<AiConversation> items;
}

class AiAssistantView extends StatefulWidget {
  const AiAssistantView({
    super.key,
    required this.accessToken,
    required this.repository,
    this.ownerKey,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  final String accessToken;
  final AiRepository repository;

  /// Stable identity used to scope local UI state (last-opened thread) to the
  /// signed-in account. It is never sent to the backend as ownership proof —
  /// the API derives ownership from the bearer token.
  final String? ownerKey;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  @override
  State<AiAssistantView> createState() => _AiAssistantViewState();
}

class _AiAssistantViewState extends State<AiAssistantView> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final List<_ChatEntry> _entries = [];
  bool _sending = false;
  String _useCase = 'education';

  List<AiConversation> _conversations = [];
  bool _loadingConversations = false;
  bool _loadingConversation = false;
  bool _sidebarOpen = true;
  String? _currentConversationUid;
  bool _restoredConversation = false;
  String? _conversationError;
  String _searchQuery = '';
  Timer? _searchDebounce;

  /// The last-opened thread is remembered per account, so switching accounts
  /// can never surface the previous user's conversation id — and the backend
  /// remains the authority for what the new account may open.
  static const String _currentConversationPrefix =
      'ai_assistant_current_conversation';
  String get _currentConversationKey =>
      '${_currentConversationPrefix}_${widget.ownerKey ?? 'local'}';

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void didUpdateWidget(covariant AiAssistantView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerKey != widget.ownerKey ||
        oldWidget.accessToken != widget.accessToken) {
      // Account switch / fresh session: drop the previous account's in-memory
      // history immediately and reload from the authoritative backend.
      _searchDebounce?.cancel();
      _searchController.clear();
      _searchQuery = '';
      _entries.clear();
      _conversations = const [];
      _currentConversationUid = null;
      _restoredConversation = false;
      _conversationError = null;
      _loadConversations();
    }
  }

  Future<void> _loadConversations({
    String? search,
    bool allowRestore = true,
  }) async {
    final query = (search ?? _searchQuery).trim();
    if (mounted) {
      setState(() {
        _loadingConversations = true;
        _conversationError = null;
      });
    }
    try {
      final list = await widget.repository.listConversations(
        widget.accessToken,
        search: query,
      );
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loadingConversations = false;
      });
      if (allowRestore && !_restoredConversation && query.isEmpty) {
        _restoredConversation = true;
        await _restoreLastConversation();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingConversations = false;
        _conversationError = AppLocalizations.of(
          context,
        ).tr('ai.loadConversationsFailed');
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadConversations(search: value, allowRestore: false);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
    _loadConversations(search: '', allowRestore: false);
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

  Future<void> _openConversation(
    AiConversation conversation, {
    bool closeSheet = true,
  }) async {
    if (closeSheet && MediaQuery.of(context).size.width < 900) {
      Navigator.of(context).maybePop();
    }
    setState(() => _loadingConversation = true);
    try {
      final full = await widget.repository.getConversation(
        widget.accessToken,
        conversation.uid,
      );
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
      _showError(AppLocalizations.of(context).tr('err.generic'));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
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
        for (final c
            in (meta['emergency_categories'] as List<dynamic>? ?? const []))
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
    var draft = currentTitle;
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.tr('ai.renameConversation')),
        content: TextFormField(
          initialValue: currentTitle,
          autofocus: true,
          maxLength: 200,
          onChanged: (value) => draft = value,
          decoration: InputDecoration(labelText: s.tr('ai.titleLabel')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.tr('ai.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
            child: Text(s.tr('ai.save')),
          ),
        ],
      ),
    );
    if (newTitle == null) return;
    if (newTitle.isEmpty) {
      _showError(s.tr('ai.renameEmpty'));
      return;
    }
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
            c.uid == updated.uid
                ? c.copyWith(
                    title: updated.title,
                    updatedAt: updated.updatedAt,
                    lastActivityAt: updated.lastActivityAt,
                  )
                : c,
        ];
      });
    } catch (_) {
      if (!mounted) return;
      _showError(s.tr('err.generic'));
    }
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
      await widget.repository.deleteConversation(
        widget.accessToken,
        conversation.uid,
      );
      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .where((c) => c.uid != conversation.uid)
            .toList();
        if (_currentConversationUid == conversation.uid) {
          _entries.clear();
          _currentConversationUid = null;
        }
      });
      if (_currentConversationUid == null) {
        _rememberCurrentConversation(null);
      }
    } catch (_) {
      if (!mounted) return;
      _showError(s.tr('err.generic'));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
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
        metric: _useCase == 'insight_explanation'
            ? 'medication_adherence'
            : null,
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
      _loadConversations(allowRestore: false);
    } on AiRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _rollbackFailedTurn(text);
        _entries.add(
          _ChatEntry.error(e.isThrottled ? s.tr('ai.throttled') : e.message),
        );
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rollbackFailedTurn(text);
        _entries.add(_ChatEntry.error(s.tr('err.generic')));
        _sending = false;
      });
    }
  }

  /// The backend rolls back a failed turn (no partial user message is kept).
  /// Mirror that locally and restore the composer so a retry cannot produce a
  /// duplicate user bubble or lose what was typed.
  void _rollbackFailedTurn(String text) {
    if (_entries.isNotEmpty && _entries.last.kind == _EntryKind.user) {
      _entries.removeLast();
    }
    _input.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final chat = Column(
      children: [
        _chatToolbar(context, isWide: isWide),
        PageBanner(
          page: BannerPage.aiAssistant,
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
        ),
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
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.centerLeft,
          child: (isWide && _sidebarOpen)
              ? SizedBox(width: 288, child: _sidebar(context, embedded: true))
              : const SizedBox.shrink(),
        ),
        Expanded(child: chat),
      ],
    );
  }

  Widget _chatToolbar(BuildContext context, {required bool isWide}) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = _conversations
        .where((c) => c.uid == _currentConversationUid)
        .toList();
    final title = selected.isEmpty
        ? s.tr('ai.brandName')
        : (selected.first.displayTitle.isEmpty
              ? s.tr('ai.newConversation')
              : selected.first.displayTitle);
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
          if (!isWide || !_sidebarOpen)
            IconButton(
              tooltip: s.tr('ai.history'),
              onPressed: isWide
                  ? () => setState(() => _sidebarOpen = true)
                  : () => _openSidebarPanel(context),
              icon: const Icon(Icons.menu),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (isWide && _sidebarOpen)
            IconButton(
              tooltip: s.tr('ai.hideHistory'),
              onPressed: () => setState(() => _sidebarOpen = false),
              icon: const Icon(Icons.chevron_left),
            ),
        ],
      ),
    );
  }

  /// Mobile/tablet slide-out side panel (never permanently consumes space).
  Future<void> _openSidebarPanel(BuildContext context) async {
    final s = AppLocalizations.of(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: s.tr('ai.history'),
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        final width = MediaQuery.of(dialogContext).size.width;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width < 380 ? width * 0.9 : 320,
            height: double.infinity,
            child: SafeArea(
              right: false,
              child: Material(
                color: Theme.of(dialogContext).colorScheme.surfaceContainerLow,
                child: _sidebar(dialogContext, embedded: false),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
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
            ? Border(right: BorderSide(color: theme.colorScheme.outlineVariant))
            : null,
      ),
      child: Column(
        children: [
          _sidebarHeader(context, embedded: embedded),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              key: const ValueKey('ai-search-input'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: s.tr('ai.searchConversations'),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: s.tr('ai.clearSearch'),
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: const OutlineInputBorder(
                  borderRadius: AppShapes.medium,
                ),
              ),
            ),
          ),
          Expanded(child: _historyList(context)),
          const Divider(height: 1),
          _sidebarAccount(context),
        ],
      ),
    );
  }

  Widget _sidebarHeader(BuildContext context, {required bool embedded}) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: AppShapes.small,
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  size: 20,
                  color: AppColors.textOnDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.tr('ai.brandName'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      s.tr('ai.brandSubtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: embedded ? s.tr('ai.hideHistory') : s.tr('ai.history'),
                onPressed: () {
                  if (embedded) {
                    setState(() => _sidebarOpen = false);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                icon: Icon(embedded ? Icons.chevron_left : Icons.close),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () => _startNewChat(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(s.tr('ai.newChat')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              alignment: Alignment.centerLeft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyList(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_loadingConversations && _conversations.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_conversationError != null && _conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _conversationError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => _loadConversations(allowRestore: false),
                child: Text(s.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            _searchQuery.trim().isEmpty
                ? s.tr('ai.noConversations')
                : s.tr('ai.noSearchResults'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final groups = _groupConversations(_conversations);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final group = groups[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                s.tr(group.labelKey).toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
            ),
            for (final conversation in group.items)
              _conversationTile(context, conversation),
          ],
        );
      },
    );
  }

  List<_ConversationGroup> _groupConversations(List<AiConversation> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final buckets = <String, List<AiConversation>>{};
    for (final conversation in items) {
      final stamp =
          (conversation.lastActivityAt ??
                  conversation.updatedAt ??
                  conversation.createdAt)
              ?.toLocal();
      final day = stamp == null
          ? null
          : DateTime(stamp.year, stamp.month, stamp.day);
      final diff = day == null ? 9999 : today.difference(day).inDays;
      final key = diff <= 0
          ? 'ai.today'
          : diff == 1
          ? 'ai.yesterday'
          : diff < 7
          ? 'ai.previous7Days'
          : diff < 30
          ? 'ai.previous30Days'
          : 'ai.older';
      buckets.putIfAbsent(key, () => []).add(conversation);
    }
    const order = [
      'ai.today',
      'ai.yesterday',
      'ai.previous7Days',
      'ai.previous30Days',
      'ai.older',
    ];
    return [
      for (final key in order)
        if (buckets.containsKey(key)) _ConversationGroup(key, buckets[key]!),
    ];
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
        shape: const RoundedRectangleBorder(borderRadius: AppShapes.small),
        contentPadding: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.xs,
        ),
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
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onSurface,
          ),
        ),
        subtitle: conversation.messageCount > 0
            ? Text(
                s.tr(
                  'ai.messagesCount',
                  args: {'count': '${conversation.messageCount}'},
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? theme.colorScheme.onSecondaryContainer.withValues(
                          alpha: .75,
                        )
                      : theme.colorScheme.onSurfaceVariant,
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
            PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(s.tr('ai.rename')),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(s.tr('ai.delete')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarAccount(BuildContext context) {
    final s = AppLocalizations.of(context);
    final name = (widget.displayName ?? '').trim();
    final email = (widget.email ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        leading: AppAvatar(
          imageUrl: widget.photoUrl,
          name: name.isNotEmpty ? name : email,
          radius: 16,
        ),
        title: Text(
          name.isNotEmpty ? name : s.tr('nav.profile'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        subtitle: email.isEmpty
            ? null
            : Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          // Close the slide-out panel first on mobile; on wide screens the
          // sidebar stays put and the profile route simply opens.
          if (MediaQuery.of(context).size.width < 900) {
            Navigator.of(context).maybePop();
          }
          Navigator.of(context).pushNamed(ProfilePage.routeName);
        },
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
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
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
              Icon(
                Icons.error_outline,
                color: dark
                    ? AppColors.emergency.withValues(alpha: .90)
                    : AppColors.emergency,
              ),
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
              const Icon(
                Icons.smart_toy_outlined,
                size: 18,
                color: AppColors.blue,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                s.tr('ai.coach'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.blue,
                ),
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
              style: theme.textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final src in turn.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.menu_book_outlined,
                      size: 16,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(src.title, style: theme.textTheme.labelMedium),
                          if (src.snippet.isNotEmpty)
                            Text(
                              src.snippet,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
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
        border: Border.all(color: accent.withValues(alpha: dark ? .60 : .30)),
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
                    color: dark
                        ? theme.colorScheme.onSurface
                        : AppColors.darkRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            s.tr('ai.emergencyBody'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, EmergencyPage.routeName),
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
          Icon(
            Icons.block,
            size: 18,
            color: dark
                ? AppColors.warning.withValues(alpha: .90)
                : AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              s.tr('ai.blockedTitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
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
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
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
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
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
                  key: const ValueKey('ai-composer-input'),
                  controller: _input,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: s.tr('ai.placeholder'),
                    prefixIcon: const Icon(Icons.chat_bubble_outline),
                    border: OutlineInputBorder(borderRadius: AppShapes.hero),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
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
