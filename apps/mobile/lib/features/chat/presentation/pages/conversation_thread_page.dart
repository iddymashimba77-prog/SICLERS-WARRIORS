import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/chat_repository.dart';
import '../../../../core/theme/app_shapes.dart';

/// Conversation thread (approved CHAT-002/CHAT-003; FR-DOC-005).
///
/// Not end-to-end encrypted in v1 (server ACL + TLS, §23) — no claim of E2E is
/// made in the UI. Own messages can be tombstoned; the body is masked for all
/// participants after deletion.
class ConversationThreadView extends StatefulWidget {
  const ConversationThreadView({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.conversationUid,
  });

  final String accessToken;
  final ChatRepository repository;
  final String conversationUid;

  @override
  State<ConversationThreadView> createState() => _ConversationThreadViewState();
}

class _ConversationThreadViewState extends State<ConversationThreadView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage>? _messages;
  Object? _error;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.repository.listMessages(
        access: widget.accessToken,
        uid: widget.conversationUid,
      );
      await widget.repository.markRead(
        access: widget.accessToken,
        uid: widget.conversationUid,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final message = await widget.repository.sendMessage(
        access: widget.accessToken,
        uid: widget.conversationUid,
        content: text,
      );
      _controller.clear();
      if (!mounted) return;
      setState(() {
        _messages = [...?_messages, message];
        _sending = false;
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.messageSendFailed)),
      );
    }
  }

  Future<void> _delete(ChatMessage message) async {
    try {
      await widget.repository.deleteMessage(
        access: widget.accessToken,
        conversationUid: widget.conversationUid,
        messageUid: message.uid,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          for (final m in _messages ?? const <ChatMessage>[])
            if (m.uid == message.uid)
              ChatMessage(
                uid: m.uid,
                sender: m.sender,
                content: '',
                messageType: m.messageType,
                status: 'DELETED',
                deleted: true,
                isMine: m.isMine,
                createdAt: m.createdAt,
              )
            else
              m,
        ];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.deleteFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.privateDoctorChat)),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_messages != null && _error == null) _composer(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(message: AppStrings.threadLoadFailed, onRetry: _load);
    }
    final messages = _messages ?? const <ChatMessage>[];
    if (messages.isEmpty) {
      return EmptyStateView(message: AppStrings.noConversations);
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: messages[i],
        onDelete: messages[i].isMine && !messages[i].deleted
            ? () => _delete(messages[i])
            : null,
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: AppStrings.sendMessageHint,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onDelete});

  final ChatMessage message;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final body = message.deleted
        ? (mine ? AppStrings.messageDeletedSelf : AppStrings.messageDeleted)
        : message.content;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onDelete,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: mine
                ? AppColors.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppShapes.tile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                body,
                style: TextStyle(
                  color: mine ? AppColors.onPrimary : null,
                  fontStyle: message.deleted ? FontStyle.italic : null,
                ),
              ),
              if (mine && !message.deleted)
                Text(
                  message.isRead ? '✓✓' : '✓',
                  style: const TextStyle(fontSize: 11, color: AppColors.onPrimary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
