import 'package:flutter/material.dart';

import '../../features/public/presentation/pages/public_home_page.dart';
import '../../shared/widgets/app_icon.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Fallback for a named route that no entry in the `MaterialApp.routes`
/// table can resolve.
///
/// Without `onUnknownRoute`, WidgetsApp throws
/// `Could not find a generator for route …` in debug and a null-check crash in
/// release, so a stale deep link would take the whole app down instead of
/// landing here (see `_onUnknownRoute` in flutter/lib/src/widgets/app.dart).
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, this.failedRoute});

  /// The route that failed to resolve, surfaced for support/debugging.
  final String? failedRoute;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.tr('err.notFoundTitle'))),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  icon: Icons.explore_off_outlined,
                  color: AppTheme.colorScheme(context).primary,
                ),
                const SizedBox(height: 16),
                Text(
                  s.tr('err.notFoundTitle'),
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  s.tr('err.notFoundBody'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.colorScheme(context).onSurfaceVariant,
                  ),
                ),
                if (failedRoute != null && failedRoute!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    failedRoute!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.colorScheme(context).onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                    PublicHomePage.routeName,
                    (route) => false,
                  ),
                  child: Text(s.tr('common.goHome')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
