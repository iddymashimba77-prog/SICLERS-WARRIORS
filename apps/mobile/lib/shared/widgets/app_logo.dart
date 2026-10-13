import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../features/public/presentation/controllers/branding_controller.dart'
    show BrandingScope;

/// Official Sickler's Warriors brand lockup.
///
/// Renders the live admin-provided logo when the platform has branding
/// uploaded (`/api/branding/logo/`); otherwise it falls back to the bundled
/// brand image (`AppAssets.brandLogo`), and finally to an on-brand
/// typographic fallback so the app never breaks on a missing image.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 96, this.width});

  /// Target render height of the mark.
  final double height;

  /// Optional explicit width (defaults to a square box of `height`).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final branding = BrandingScope.maybeOf(context);
    final liveUrl = (branding?.hasLogo ?? false) ? branding!.resolvedLogoUrl : '';
    // Fixed box (never the platform's full cross-axis width): an admin-driven
    // logo can be wide or large and without an explicit tight box it would
    // render at its intrinsic size inside stretch columns.
    final edge = width ?? height;
    final child = liveUrl.isNotEmpty
        ? Image.network(
            liveUrl,
            fit: BoxFit.contain,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            semanticLabel: branding!.info.logoAlt.isEmpty
                ? null
                : branding.info.logoAlt,
            errorBuilder: (_, __, ___) => _BundledImage(
              height: height,
              width: width,
            ),
          )
        : _BundledImage(height: height, width: width);
    return Center(
      child: SizedBox(width: edge, height: height, child: child),
    );
  }
}

class _BundledImage extends StatelessWidget {
  const _BundledImage({required this.height, required this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.brandLogo,
      width: width ?? height,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _BrandFallbackMark(size: height),
    );
  }
}

/// Inline header lockup: small mark + the wordmark + optional tagline.
///
/// Use this for app bars and auth screens where a horizontal, two-line brand
/// is preferred over the raw image.
class AppBrand extends StatelessWidget {
  const AppBrand({
    super.key,
    this.markHeight = 32,
    this.showSubtitle = false,
    this.light = false,
    this.onTap,
  });

  final double markHeight;
  final bool showSubtitle;
  final bool light;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = light ? Colors.white : AppColors.textPrimary;
    final subtitleColor =
        light ? AppColors.textOnDark.withValues(alpha: .72) : AppColors.textMuted;
    final mark = onTap == null
        ? AppLogo(height: markHeight)
        : GestureDetector(onTap: onTap, child: AppLogo(height: markHeight));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Sickler's Warriors",
              style: TextStyle(
                color: titleColor,
                fontSize: markHeight * .62,
                fontWeight: FontWeight.w800,
                letterSpacing: -.2,
                height: 1.05,
              ),
            ),
            if (showSubtitle)
              Text(
                'Community · Care · Courage',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: markHeight * .34,
                  fontWeight: FontWeight.w500,
                  letterSpacing: .3,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Typographic fallback mark: a navy tile with the two-tone initials and a
/// red accent chevron — keeps the brand present even without raster art.
class _BrandFallbackMark extends StatelessWidget {
  const _BrandFallbackMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final edge = size;
    return Container(
      width: edge,
      height: edge,
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(edge * .24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'SW',
            style: TextStyle(
              color: Colors.white,
              fontSize: edge * .38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              width: edge * .42,
              height: edge * .10,
              decoration: BoxDecoration(
                color: AppColors.emergency,
                borderRadius: BorderRadius.circular(edge * .12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}