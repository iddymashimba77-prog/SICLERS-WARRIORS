import 'package:flutter/material.dart';

/// Sickler's Warriors — shape language (FRONTEND-1).
///
/// One radius scale for the whole product. Every rounded surface resolves to
/// one of these tokens; raw `BorderRadius.circular(...)` literals are banned
/// outside this file and the gate is enforced by `design_token_test.dart`.
///
/// Semantic roles, from tightest to loosest:
///
/// | token    | px  | used for                                            |
/// |----------|-----|-----------------------------------------------------|
/// | [xs]     | 4   | dense rows, progress-bar segments, compact insets    |
/// | [small]  | 8   | chips, badges, small buttons                         |
/// | [medium] | 10  | default controls — buttons, inputs, nav pills         |
/// | [tile]   | 12  | interactive cards and tiles (feature/dashboard cards) |
/// | [card]   | 16  | prominent cards (`rounded-2xl`)                       |
/// | [large]  | 20  | dialogs and bottom-sheet tops                         |
/// | [hero]   | 24  | hero / marketing surfaces                             |
/// | [pill]   | 999 | fully rounded — semantic chips only                   |
///
/// Pills are reserved for semantic chips (status, availability), not for
/// generic controls.
class AppShapes {
  AppShapes._();

  /// 4 px — dense rows, progress-bar segments, compact insets.
  static const BorderRadius xs = BorderRadius.all(Radius.circular(4));

  /// 8 px — chips, badges, small buttons.
  static const BorderRadius small = BorderRadius.all(Radius.circular(8));

  /// 10 px — default control radius (buttons, inputs, nav pills).
  static const BorderRadius medium = BorderRadius.all(Radius.circular(10));

  /// 12 px — interactive tiles (feature cards, dashboard cards).
  static const BorderRadius tile = BorderRadius.all(Radius.circular(12));

  /// Prominent card radius (`rounded-2xl`).
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));

  /// Large surfaces (dialogs, bottom-sheet tops).
  static const BorderRadius large = BorderRadius.all(Radius.circular(20));

  /// 24 px — hero and marketing surfaces.
  static const BorderRadius hero = BorderRadius.all(Radius.circular(24));

  /// Fully rounded pill — semantic chips only.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));

  /// Bottom sheet top edge.
  static const BorderRadius bottomSheetTop =
      BorderRadius.vertical(top: Radius.circular(20));

  /// Subtle border used by cards.
  static BorderSide cardBorder([Color? color]) =>
      BorderSide(color: color ?? Colors.transparent, width: 1);
}
