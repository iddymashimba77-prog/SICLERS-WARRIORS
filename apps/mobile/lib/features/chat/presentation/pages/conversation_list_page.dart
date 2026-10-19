import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../data/chat_repository.dart';
import 'conversation_thread_page.dart';
import '../widgets/recipient_picker_dialog.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Conversation list (approved CHAT-001; FR-DOC-005/UR-01).
///
/// Private doctor⇄patient threads only; community content is never mixed in
/// here. Unread counts surface without any message-body preview.
///
/// Starting a conversation uses the server-built recipient picker
/// (`GET /api/chat/recipients/`) instead of asking anyone to paste a
/// verified professional UID; roles without `chat.start` (caregiver, donors)
/// never see the compose action at all — the backend stays the authority.
class ConversationListPage extends StatelessWidget {
  const ConversationListPage({super.key, this.authController, this.repository});

  static const String routeName = '/messages';

  /// Roles the backend lets start a conversation (`chat.start` seeds).
  static const Set<String> _startableRoles = {
    'PATIENT',
    'DOCTOR',
    'PSYCHOLOGIST',
    'SOCIAL_SUPPORT',
    'HEALTHCARE_STAFF',
  };

  final AuthController? authController;
  final ChatRepository? repository;

  @override
  Widget build(BuildContext context) {
    final controller = authController ?? SessionScope.controllerOf(context);
    final token = controller.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    // Unknown roles (session still hydrating) keep compose visible; the
    // server refuses anyone without `chat.start` regardless.
    final roles = controller.roles;
    final canCompose = roles.isEmpty || roles.any(_startableRoles.contains);
    return ConversationListView(
      accessToken: token,
      repository: repository ?? ChatRepository(tokenStore: EphemeralTokenStore()),
      canCompose: canCompose,
    );
  }
}

class ConversationListView extends StatefulWidget {
  const ConversationListView({
    super.key,
    required this.accessToken,
    required this.repository,
    this.canCompose = true,
  });

  final String accessToken;
  final ChatRepository repository;

  /// Whether this session may start conversations (`chat.start`). Caregivers
  /// and donors never can, so their clients hide compose entirely.
  final bool canCompose;

  @override
  State<ConversationListView> createState() => _ConversationListViewState();
}

class _ConversationListViewState extends State<ConversationListView> {
  List<Conversation>? _conversations;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations =
          await widget.repository.listConversations(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _startConversation() async {
    final uid = await showRecipientPicker(
      context: context,
      repository: widget.repository,
      accessToken: widget.accessToken,
    );
    if (uid == null || uid.isEmpty || !mounted) return;
    try {
      final conversation = await widget.repository.startConversation(
        access: widget.accessToken,
        participantUid: uid,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConversationThreadView(
            accessToken: widget.accessToken,
            repository: widget.repository,
            conversationUid: conversation.uid,
          ),
        ),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).tr('chat.startFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.messages),
        actions: [
          if (widget.canCompose)
            IconButton(
              key: const ValueKey<String>('compose-conversation'),
              tooltip: s.tr('chat.newConversation'),
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _startConversation,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(message: AppStrings.conversationsLoadFailed, onRetry: _load);
    }
    final conversations = _conversations ?? const <Conversation>[];
    if (conversations.isEmpty) {
      return EmptyStateView(
        message: AppStrings.noConversations,
        icon: Icons.chat_bubble_outline,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final conversation = conversations[i];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.medical_services_outlined)),
            title: Text(conversation.displayTitle),
            subtitle: Text(AppStrings.privateDoctorChat),
            trailing: conversation.unreadCount > 0
                ? Badge(label: Text('${conversation.unreadCount}'))
                : null,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConversationThreadView(
                    accessToken: widget.accessToken,
                    repository: widget.repository,
                    conversationUid: conversation.uid,
                  ),
                ),
              );
              _load();
            },
          );
        },
      ),
    );
  }
}
