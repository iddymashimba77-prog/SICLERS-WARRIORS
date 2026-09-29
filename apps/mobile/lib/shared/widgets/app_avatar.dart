import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Sickler's Warriors — avatar (FRONTEND-1).
///
/// Renders an image when provided, otherwise initials against a token-based
/// background. Falls back gracefully and always carries a semantic label.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.radius = 20,
    this.backgroundColor,
    this.onTap,
  });

  final String? imageUrl;
  final String? name;
  final double radius;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  String get _initials {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppColors.navy,
      foregroundImage: (imageUrl != null && imageUrl!.isNotEmpty)
          ? NetworkImage(imageUrl!)
          : null,
      child: imageUrl == null || imageUrl!.isEmpty
          ? Text(
              _initials,
              style: TextStyle(
                color: AppColors.textOnDark,
                fontWeight: FontWeight.w600,
                fontSize: radius * 0.8 - 2,
              ),
            )
          : null,
    );

    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: name ?? 'Profile',
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: child),
    );
  }
}