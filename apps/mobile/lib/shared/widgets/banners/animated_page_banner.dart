import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/banner_art_tokens.dart';
import '../../../core/theme/app_spacing.dart';
import 'healthcare_banner_art.dart';

/// Brand-approved background treatments for the in-app banner family.
enum BannerPalette { midnight, ocean, crimson }

extension BannerPaletteColors on BannerPalette {
  List<Color> get gradient => switch (this) {
    BannerPalette.midnight => const [
      BannerArtColors.c081A33,
      BannerArtColors.c16406D,
    ],
    BannerPalette.ocean => const [
      BannerArtColors.c0E4A84,
      BannerArtColors.c2473BD,
    ],
    BannerPalette.crimson => const [
      BannerArtColors.c711525,
      BannerArtColors.cA9253A,
    ],
  };

  Color get accent => switch (this) {
    BannerPalette.midnight => BannerArtColors.cEF5B6B,
    BannerPalette.ocean => BannerArtColors.cFF7C8A,
    BannerPalette.crimson => BannerArtColors.cFFD4DB,
  };
}

/// Compact, premium healthcare banner used at the top of authenticated pages.
///
/// The composition follows the product reference: message on the left, a
/// diverse animated care team on the right, a rounded brand surface, and the
/// page content immediately below. It is deliberately a banner — never a
/// fullscreen hero or page background.
///
/// The illustration is built from bundled vectors, so there is no network
/// download and no missing-animation state. Motion runs once through a calm,
/// finite care-team sequence; when [animate] is false or the platform requests
/// reduced motion, the exact same artwork renders as a static fallback.
class AnimatedPageBanner extends StatefulWidget {
  const AnimatedPageBanner({
    super.key,
    required this.title,
    required this.description,
    required this.scene,
    required this.semanticsLabel,
    this.palette = BannerPalette.midnight,
    this.accentColor,
    this.height,
    this.characterAlignment = Alignment.centerRight,
    this.textAlignment = TextAlign.start,
    this.compact,
    this.animate = true,
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      0,
    ),
  });

  final String title;
  final String description;
  final BannerScene scene;
  final String semanticsLabel;
  final BannerPalette palette;
  final Color? accentColor;
  final double? height;
  final Alignment characterAlignment;
  final TextAlign textAlignment;
  final bool? compact;
  final bool animate;
  final EdgeInsetsGeometry margin;

  @override
  State<AnimatedPageBanner> createState() => _AnimatedPageBannerState();
}

class _AnimatedPageBannerState extends State<AnimatedPageBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 8000),
  );

  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (reduce) {
        _motion
          ..stop()
          ..value = 0.32;
        _started = false;
      }
    }
    if (!_reduceMotion && widget.animate && !_started) {
      _started = true;
      _motion.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedPageBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      if (widget.animate && !_reduceMotion) {
        _started = true;
        _motion.forward(from: 0);
      } else {
        _motion
          ..stop()
          ..value = 0.32;
        _started = false;
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = widget.compact ?? width < 480;
    final bannerHeight = widget.height ?? (compact ? 136.0 : 154.0);
    final accent = widget.accentColor ?? widget.palette.accent;
    final colors = widget.palette.gradient;
    final motion = (_reduceMotion || !widget.animate) ? null : _motion;

    return Padding(
      padding: widget.margin,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppShapes.hero,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: AppShapes.hero,
            child: SizedBox(
              height: bannerHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final artWidth = math.min<double>(
                    constraints.maxWidth * (compact ? 0.44 : 0.42),
                    330,
                  );
                  final textWidth = math.max<double>(
                    120,
                    constraints.maxWidth - artWidth - (compact ? 28 : 36),
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _background(colors, accent),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: textWidth,
                        child: _copy(context, compact: compact),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: artWidth,
                        child: IgnorePointer(
                          child: Semantics(
                            image: true,
                            label: widget.semanticsLabel,
                            child: ExcludeSemantics(
                              child: Align(
                                alignment: widget.characterAlignment,
                                child: HealthcareBannerArt(
                                  key: ValueKey<String>(
                                    motion == null
                                        ? 'banner-art-static'
                                        : 'banner-art-animated',
                                  ),
                                  scene: widget.scene,
                                  accentColor: accent,
                                  motion: motion,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _background(List<Color> colors, Color accent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -42,
            child: _halo(126, Colors.white.withValues(alpha: 0.055)),
          ),
          Positioned(
            right: 88,
            bottom: -58,
            child: _halo(124, accent.withValues(alpha: 0.12)),
          ),
          Positioned(
            left: -22,
            bottom: -34,
            child: _halo(84, Colors.white.withValues(alpha: 0.035)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _halo(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _copy(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final titleSize = compact ? 18.0 : 22.0;
    final bodySize = compact ? 12.0 : 13.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? AppSpacing.md + 2 : AppSpacing.lg + 4,
        compact ? AppSpacing.md : AppSpacing.lg,
        compact ? AppSpacing.xs : AppSpacing.sm,
        compact ? AppSpacing.md : AppSpacing.lg,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.textAlignment,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
                height: 1.12,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              widget.description,
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.textAlignment,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: bodySize,
                height: 1.32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
