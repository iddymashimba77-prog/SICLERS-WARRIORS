import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shapes.dart';

/// One bar destination. Labels are rendered only for screen readers (the
/// reference design hides them visually); icons carry the meaning.
class NavDestination {
  const NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  /// Outline icon shown when the destination is not selected.
  final IconData icon;

  /// Filled icon shown when the destination is selected.
  final IconData selectedIcon;

  /// Accessible name announced by screen readers.
  final String label;

  /// Optional unread/attention count; `0` hides the brand-red badge.
  final int badgeCount;
}

/// The raised center action living in the bar's wave crest.
///
/// Patient shells use it for "Ask Sickler AI"; role shells pass `null` and the
/// crest stays decorative.
class NavCenterAction {
  const NavCenterAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Curved, wave-topped bottom navigation (brand redesign).
///
/// A wide navy panel with a wave-shaped upper edge, large rounded corners and a
/// raised center crest. The five destinations sit on the flat deck; the crest
/// hosts an optional [centerAction] (the AI assistant for patient shells).
/// Active destination = white icon on a primary-red rounded square; inactive
/// icons are light-on-navy. Geometry is theme-independent so light/dark/system
/// modes never change the silhouette.
class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({
    super.key,
    required this.index,
    required this.onIndexChanged,
    required this.destinations,
    this.centerAction,
  });

  final int index;
  final ValueChanged<int> onIndexChanged;
  final List<NavDestination> destinations;
  final NavCenterAction? centerAction;

  // --- geometry (logical px) ------------------------------------------------
  /// Height of the flat deck that holds the destination icons.
  static const double deckHeight = 56;

  /// Height of the raised center plateau that hosts the center action.
  static const double crestHeight = 40;

  /// Total painted height of the bar content (crest + deck).
  static const double barHeight = deckHeight + crestHeight;

  static const double _corner = 26;
  static const double _centerButtonHeight = 44;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: SizedBox(
        height: barHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: const _WaveBarPainter(
                  color: AppColors.navy,
                  deckTop: crestHeight,
                  crestTop: 0,
                  corner: _corner,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: crestHeight,
              bottom: 0,
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _NavBarTab(
                        key: ValueKey<String>('bottom-nav-$i'),
                        destination: destinations[i],
                        selected: i == index,
                        onTap: () => onIndexChanged(i),
                      ),
                    ),
                ],
              ),
            ),
            if (centerAction != null)
              Positioned(
                left: 0,
                right: 0,
                top: 1,
                child: Center(child: _CenterAction(action: centerAction!)),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavBarTab extends StatelessWidget {
  const _NavBarTab({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        selected ? AppColors.onPrimary : AppColors.textOnDark;
    final Widget icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      color: iconColor,
      size: 24,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.tile,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 46,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.emergency : Colors.transparent,
                  borderRadius: AppShapes.tile,
                ),
                child: icon,
              ),
              if (destination.badgeCount > 0)
                Positioned(
                  top: 0,
                  right: 2,
                  child: _Badge(count: destination.badgeCount),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String text = count > 9 ? '9+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.emergency,
        borderRadius: AppShapes.pill,
        border: Border.all(color: AppColors.navy, width: 1.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.onPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _CenterAction extends StatelessWidget {
  const _CenterAction({required this.action});

  final NavCenterAction action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: AppShapes.hero,
          child: Container(
            height: FloatingBottomNav._centerButtonHeight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppColors.navyDeep, AppColors.blue],
              ),
              borderRadius: AppShapes.hero,
              border: Border.all(color: AppColors.emergency, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, color: AppColors.onPrimary, size: 20),
                const SizedBox(width: 8),
                Text(
                  action.label,
                  style: const TextStyle(
                    color: AppColors.onPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the navy panel: a flat deck whose top edge steps up over a wide,
/// shoulder-rounded plateau that hosts the center action, with straight sides
/// and large rounded bottom corners.
class _WaveBarPainter extends CustomPainter {
  const _WaveBarPainter({
    required this.color,
    required this.deckTop,
    required this.crestTop,
    required this.corner,
  });

  final Color color;
  final double deckTop;
  final double crestTop;
  final double corner;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cr = corner;
    final double top = deckTop;
    final double crest = crestTop;
    final double cx = w / 2;
    // Half-width of the raised plateau; hugs the widest center action.
    final double plateauHalf = math.min(w * 0.30, 120);
    final double lsx = cx - plateauHalf;
    final double rsx = cx + plateauHalf;

    final Path path = Path()
      ..moveTo(0, h - cr)
      ..quadraticBezierTo(0, h, cr, h)
      ..lineTo(w - cr, h)
      ..quadraticBezierTo(w, h, w, h - cr)
      ..lineTo(w, top + cr)
      ..quadraticBezierTo(w, top, w - cr, top)
      // right shoulder rising to the plateau
      ..cubicTo(w - cr - 46, top, rsx + 46, crest, rsx, crest)
      ..lineTo(lsx, crest)
      // left shoulder dropping back to the deck
      ..cubicTo(lsx - 46, crest, cr + 46, top, cr, top)
      ..quadraticBezierTo(0, top, 0, top + cr)
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.35), 10, true);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WaveBarPainter old) =>
      old.color != color ||
      old.deckTop != deckTop ||
      old.crestTop != crestTop ||
      old.corner != corner;
}
