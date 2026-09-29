import 'package:flutter/material.dart';

/// Sickler's Warriors — shape language (FRONTEND-1).
///
/// Modern rounded surfaces. Cards are the most round (`rounded-2xl` ≈ 16),
/// controls keep subtler rounding. Pills are reserved for semantic chips
/// (status, availability), not for generic controls.
class AppShapes {
  AppShapes._();

  /// Small control radius (chips, badges, small buttons).
  static const BorderRadius small = BorderRadius.all(Radius.circular(8));

  /// Default control radius (buttons, inputs).
  static const BorderRadius medium = BorderRadius.all(Radius.circular(10));

  /// Card radius (`rounded-2xl`).
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));

  /// Large surfaces (dialogs, bottom-sheet tops).
  static const BorderRadius large = BorderRadius.all(Radius.circular(20));

  /// Bottom sheet top edge.
  static const BorderRadius bottomSheetTop =
      BorderRadius.vertical(top: Radius.circular(20));

  /// Subtle border used by cards.
  static BorderSide cardBorder([Color? color]) =>
      BorderSide(color: color ?? Colors.transparent, width: 1);
}