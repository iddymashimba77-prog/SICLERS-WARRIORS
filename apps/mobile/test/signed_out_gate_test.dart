import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
import 'package:sicklers_warriors/features/doctor/presentation/pages/doctor_home_page.dart';
import 'package:sicklers_warriors/features/home/presentation/pages/home_page.dart';
import 'package:sicklers_warriors/shared/widgets/signed_out_gate.dart';

Widget _app(Widget home) => MaterialApp(
      home: home,
      routes: {LoginPage.routeName: (_) => const LoginPage()},
    );

/// Every guarded role screen now falls back to the same branded gate instead
/// of a bare sentence: a title, an honest message and a way forward.
void main() {
  testWidgets('the doctor home signs out through the shared gate',
      (tester) async {
    await tester.pumpWidget(_app(const DoctorHomePage()));
    await tester.pumpAndSettle();

    expect(find.byType(SignedOutGate), findsOneWidget);
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    expect(find.widgetWithText(FilledButton, AppStrings.login), findsOneWidget);
    expect(find.widgetWithText(TextButton, AppStrings.register), findsOneWidget);
  });

  testWidgets('the patient home uses the same signed-out surface',
      (tester) async {
    await tester.pumpWidget(_app(const HomePage()));
    await tester.pumpAndSettle();

    expect(find.byType(SignedOutGate), findsOneWidget);
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
  });

  testWidgets('the gate hands the user to the login screen', (tester) async {
    await tester.pumpWidget(_app(const DoctorHomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });
}
