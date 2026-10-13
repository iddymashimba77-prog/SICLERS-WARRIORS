import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/reset_password_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/signup_page.dart';

/// The whole auth flow must speak both languages: sign-up, password reset and
/// email verification were the last surfaces still hard-coded to English while
/// the Kiswahili-first fallback is the app's brand default.
Widget _app(String language, Widget home) => MaterialApp(
      locale: Locale(language),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizationsDelegate.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('signup renders in English', (tester) async {
    await tester.pumpWidget(_app('en', const SignupPage()));
    await tester.pumpAndSettle();

    expect(find.text('Create Your Account'), findsOneWidget);
    expect(find.text("I'm creating this account for..."), findsOneWidget);
    expect(find.text('Patient / Sickler'), findsOneWidget);

    // Every non-admin role is self-registerable on the grid.
    final doctor = find.text('Doctor');
    await tester.ensureVisible(doctor);
    await tester.pumpAndSettle();
    expect(doctor, findsOneWidget);
    expect(find.text('Hospital'), findsOneWidget);
    expect(find.text('Clinic'), findsOneWidget);
  });

  testWidgets('signup renders in Kiswahili', (tester) async {
    await tester.pumpWidget(_app('sw', const SignupPage()));
    await tester.pumpAndSettle();

    expect(find.text('Unda Akaunti Yako'), findsOneWidget);
    expect(find.text('Naunda akaunti hii kwa ajili ya...'), findsOneWidget);
    expect(find.text('Mgonjwa / Shujaa'), findsOneWidget);
    final psychologist = find.text('Mwanasaikolojia');
    await tester.ensureVisible(psychologist);
    await tester.pumpAndSettle();
    expect(psychologist, findsOneWidget);
    expect(find.text('Hospitali'), findsOneWidget);
    expect(find.text('Kliniki'), findsOneWidget);
  });

  testWidgets('verification requirement hint localizes in English',
      (tester) async {
    await tester.pumpWidget(_app('en', const SignupPage()));
    await tester.pumpAndSettle();

    final psychologist = find.text('Psychologist');
    await tester.ensureVisible(psychologist);
    await tester.pumpAndSettle();
    await tester.tap(psychologist);
    await tester.pumpAndSettle();

    expect(
      find.text(
          'This account needs 2 documents verified by the government service'),
      findsOneWidget,
    );
  });

  testWidgets('verification requirement hint localizes in Kiswahili',
      (tester) async {
    await tester.pumpWidget(_app('sw', const SignupPage()));
    await tester.pumpAndSettle();

    final socialWorker = find.text('Mfanyakazi wa Jamii');
    await tester.ensureVisible(socialWorker);
    await tester.pumpAndSettle();
    await tester.tap(socialWorker);
    await tester.pumpAndSettle();

    expect(
      find.text('Akaunti hii inahitaji nyaraka 2 zilizothibitishwa na serikali'),
      findsOneWidget,
    );
  });

  testWidgets('password reset request localizes both languages',
      (tester) async {
    await tester.pumpWidget(_app('en', const ForgotPasswordPage()));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send Reset Code'), findsOneWidget);

    await tester.pumpWidget(_app('sw', const ForgotPasswordPage()));
    await tester.pumpAndSettle();
    expect(find.text('Umesahau Nenosiri?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Tuma Msimbo wa Reseti'),
        findsOneWidget);
  });

  testWidgets('password reset confirm localizes both languages',
      (tester) async {
    await tester.pumpWidget(_app('en', const ResetPasswordPage()));
    await tester.pumpAndSettle();
    expect(find.text('Set New Password'), findsOneWidget);
    expect(find.text('Reset code'), findsOneWidget);

    await tester.pumpWidget(_app('sw', const ResetPasswordPage()));
    await tester.pumpAndSettle();
    expect(find.text('Weka Nenosiri Jipya'), findsOneWidget);
    expect(find.text('Msimbo wa reseti'), findsOneWidget);
  });
}
