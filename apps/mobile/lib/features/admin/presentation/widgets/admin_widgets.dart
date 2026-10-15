/// Shared widgets + interaction helpers for the ADMIN-3 portal.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../../core/theme/app_shapes.dart';

/// Generic async list with the standard loading / error / empty / retry chain.
/// The owning page can reload via its [GlobalKey] after an in-place mutation.
class AdminAsyncList<T> extends StatefulWidget {
  const AdminAsyncList({
    super.key,
    required this.load,
    required this.itemBuilder,
    this.emptyTitle,
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.loadingLabel,
    this.separator = true,
  });

  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String? emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final String? loadingLabel;
  final bool separator;

  @override
  State<AdminAsyncList<T>> createState() => AdminAsyncListState<T>();
}

class AdminAsyncListState<T> extends State<AdminAsyncList<T>> {
  List<T> _items = const [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SkeletonListView(rows: 5);
    }
    final s = AppLocalizations.of(context);
    if (_error != null) {
      final message = _error is Exception
          ? _userMessage(_error as Exception, s)
          : s.tr('admin.couldNotLoadSection');
      return ErrorRetryView(
        message: message,
        onRetry: reload,
        title: s.tr('admin.couldNotLoad'),
      );
    }
    if (_items.isEmpty) {
      return EmptyStateView(
        icon: widget.emptyIcon,
        title: widget.emptyTitle ?? s.tr('admin.nothingToShow'),
        message: widget.emptyMessage ?? s.tr('admin.nothingHere'),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _items.length,
        separatorBuilder: (_, __) =>
            widget.separator ? const SizedBox(height: AppSpacing.md) : const SizedBox.shrink(),
        itemBuilder: (context, index) =>
            widget.itemBuilder(context, _items[index]),
      ),
    );
  }

  String _userMessage(Exception e, AppLocalizations s) {
    final text = e.toString();
    if (text.isEmpty) return s.tr('admin.serverUnreachable');
    if (text.contains('Server error') || text.contains('Request failed')) {
      return text;
    }
    return s.tr('admin.serverUnreachable');
  }
}

/// Small colored status pill matching backend status vocabulary.
class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppShapes.pill,
      ),
      child: Text(
        status.isEmpty ? '—' : status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _colorFor(String status) {
    final s = status.toUpperCase();
    if (s.contains('SUCCESS') || s == 'ACTIVE' || s.contains('VERIFIED') ||
        s == 'RESOLVED' || s == 'PUBLISHED' || s == 'COMPLETED' ||
        s.contains('APPROV') || s == 'PROCESSED') {
      return AppColors.success;
    }
    if (s.contains('FAIL') || s == 'REJECTED' || s == 'SUSPENDED' ||
        s == 'BLOCKED' || s == 'DENIED' || s == 'EXCLUDED' || s == 'DECLINED') {
      return AppColors.emergency;
    }
    if (s.contains('PENDING') || s == 'IN_REVIEW' || s == 'OPEN' ||
        s == 'DRAFT' || s == 'REQUESTED' || s == 'UNVERIFIED' ||
        s.contains('INITIAT')) {
      return AppColors.warning;
    }
    return AppColors.blue;
  }
}

/// Title + subtitle header used above every portal section.
class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Confirmation dialog → `true` when the user confirms.
Future<bool> confirmAction({
  required BuildContext context,
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final theme = Theme.of(context);
  final s = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.tr('admin.cancel')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? s.tr('admin.confirm')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Reason prompt (required for audited admin mutations) → trimmed text or null.
Future<String?> promptReason({
  required BuildContext context,
  required String title,
  String? hint,
}) async {
  final s = AppLocalizations.of(context);
  final controller = TextEditingController();
  final submitted = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration:
              InputDecoration(hintText: hint ?? s.tr('admin.reasonHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.tr('admin.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(s.tr('admin.submit')),
          ),
        ],
      );
    },
  );
  return (submitted == null || submitted.trim().length < 5) ? null : submitted;
}

/// Small helper to show a transient snackbar message.
void showAdminMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}