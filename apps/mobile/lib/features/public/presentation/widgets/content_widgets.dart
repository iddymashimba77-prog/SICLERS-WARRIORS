/// Shared public-content widgets: covers, chips and meta lines used by the
/// news home section, the news list and the article detail page.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart' show AppColors;
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_shapes.dart';

/// Renders an article cover from the server (already origin-resolved).
/// A branded illustration placeholder is shown while loading or on failure so
/// a broken image never leaves a dead region on the page.
class PublicNewsCover extends StatelessWidget {
  const PublicNewsCover({
    super.key,
    this.url = '',
    this.alt = '',
    this.borderRadius = 16,
    this.height = 160,
  });

  final String url;
  final String alt;
  final double borderRadius;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = url.isEmpty
        ? const _CoverFallback()
        : Image.network(
            url,
            height: height,
            width: double.infinity,
            fit: BoxFit.contain,
            // Covers may be admin-supplied external URLs (e.g. pinned stock
            // photos) whose hosts do not send CORS headers. On Flutter web the
            // default byte-fetch is blocked by the browser, so fall back to an
            // <img> element, which is not subject to CORS. No effect off web.
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, __, ___) => const _CoverFallback(),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const _CoverFallback(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(height: height, width: double.infinity, child: child),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.blue],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.handshake_outlined,
          size: 44,
          color: dark ? AppColors.textOnDark : AppColors.lightRed,
        ),
      ),
    );
  }
}

/// Small tinted category chip, coloured by topic using the brand palette.
class PublicNewsCategoryChip extends StatelessWidget {
  const PublicNewsCategoryChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: dark ? AppColors.blue.withValues(alpha: .28) : AppColors.lightBlue,
        borderRadius: AppShapes.pill,
        border: Border.all(
          color: dark
              ? AppColors.blue.withValues(alpha: .60)
              : AppColors.blue.withValues(alpha: .30),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

/// Published date + author line for cards and headers.
class PublicNewsMetaRow extends StatelessWidget {
  const PublicNewsMetaRow({
    super.key,
    this.publishedAt,
    this.author = '',
    this.urgent = false,
  });

  final String? publishedAt;
  final String author;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final label = StringBuffer();
    if (publishedAt != null && publishedAt!.isNotEmpty) {
      label.write(_friendlyDate(publishedAt!));
    }
    if (author.isNotEmpty) {
      if (label.isNotEmpty) label.write('  ·  ');
      label.write(author);
    }
    if (label.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        if (urgent) ...[
          const Icon(Icons.campaign, size: 14, color: AppColors.emergency),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label.toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

String _friendlyDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month]} ${parsed.year}';
}