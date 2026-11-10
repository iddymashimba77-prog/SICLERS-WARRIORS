import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/about_pages.dart';
import 'package:sicklers_warriors/features/public/presentation/widgets/care_journey_section.dart';

Widget _localizedApp(String language, {required Widget home}) {
  final locale = LocaleController(AppPreferences.memory())
    ..value = Locale(language);
  return LocaleScope(
    controller: locale,
    child: ThemeScope(
      controller: ThemeController(AppPreferences.memory()),
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: materialLocalizationsDelegates(locale),
        supportedLocales: AppLocalizationsDelegate.supportedLocales,
        home: home,
        routes: <String, WidgetBuilder>{
          '/signup': (_) => const _RouteProbe('signup-destination'),
        },
      ),
    ),
  );
}

class _RouteProbe extends StatelessWidget {
  const _RouteProbe(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

/// One frame plus a transition window. The public home keeps at least the
/// ticker running, so [WidgetTester.pumpAndSettle] must be avoided here.
Future<void> _settleRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('contact numbers', () {
    test('supplied numbers stay exact and consistent with their tel paths',
        () {
      expect(ContactNumbers.primaryDisplay, '+255 763 801 187');
      expect(ContactNumbers.primaryLocal, '0763801187');
      expect(ContactNumbers.primaryTel, '+255763801187');
      expect(ContactNumbers.secondaryDisplay, '+255 683 328 789');
      expect(ContactNumbers.secondaryLocal, '0683328789');
      expect(ContactNumbers.secondaryTel, '+255683328789');

      expect(
        ContactNumbers.primaryLocal,
        '0${ContactNumbers.primaryTel.substring(4)}',
        reason: 'the local format is the same number, not a second one',
      );
      expect(
        ContactNumbers.secondaryLocal,
        '0${ContactNumbers.secondaryTel.substring(4)}',
      );
      expect(
        ContactNumbers.telUri(ContactNumbers.primaryTel).toString(),
        'tel:+255763801187',
      );
      expect(
        ContactNumbers.telUri(ContactNumbers.secondaryTel).toString(),
        'tel:+255683328789',
      );
    });

    testWidgets('the contact page displays both formats and dials (EN)',
        (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method == 'launch') {
            final args = (call.arguments as Map).cast<String, Object?>();
            launched.add('${args['url']}');
            return false;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(_localizedApp('en', home: const ContactUsPage()));
      await _settleRouteTransition(tester);

      expect(find.text('+255 763 801 187'), findsOneWidget);
      expect(find.text('0763801187'), findsOneWidget);
      expect(find.text('+255 683 328 789'), findsOneWidget);
      expect(find.text('0683328789'), findsOneWidget);
      expect(find.text('Call us'), findsNWidgets(2));

      await tester.tap(find.text('+255 763 801 187'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      expect(launched, <String>['tel:+255763801187']);
      expect(
        find.textContaining('+255763801187'),
        findsAtLeastNWidgets(1),
        reason: 'a failed dial surfaces the honest fallback with the number '
            'to ring manually',
      );
    });

    testWidgets('the contact page renders in Kiswahili too (SW)',
        (tester) async {
      await tester.pumpWidget(_localizedApp('sw', home: const ContactUsPage()));
      await _settleRouteTransition(tester);

      expect(find.text('Tuko Hapa Kuunganishana.'), findsOneWidget);
      expect(find.text('Piga Simu'), findsNWidgets(2));
      expect(find.text('+255 763 801 187'), findsOneWidget);
      expect(find.text('0763801187'), findsOneWidget);
    });
  });

  group('About page content', () {
    testWidgets('the team page names both members with initials and roles',
        (tester) async {
      await tester.pumpWidget(_localizedApp('en', home: const TeamPage()));
      await _settleRouteTransition(tester);

      expect(find.text('Iddy Mashimba'), findsOneWidget);
      expect(find.text('Michael Yohana'), findsOneWidget);
      expect(find.text('IM'), findsOneWidget);
      expect(find.text('MY'), findsOneWidget);
      expect(find.text('Project Team · Platform Development'), findsNWidgets(2));
      expect(find.text('Growing Through Collaboration'), findsOneWidget);
      expect(
        find.textContaining('not confirmed partnerships'),
        findsOneWidget,
        reason: 'collaboration areas must not read as confirmed partnerships',
      );
    });

    testWidgets('the About landing page keeps the honest feature framing',
        (tester) async {
      await tester
          .pumpWidget(_localizedApp('en', home: const AboutWarriorsPage()));
      await _settleRouteTransition(tester);

      expect(
        find.textContaining('never replaces doctors, hospitals, emergency'),
        findsOneWidget,
      );
      expect(find.text('Who we serve'), findsOneWidget);
      expect(find.text('What the platform brings together'), findsOneWidget);
    });

    testWidgets('How It Works lists six steps and the emergency caveat',
        (tester) async {
      await tester
          .pumpWidget(_localizedApp('en', home: const HowItWorksPage()));
      await _settleRouteTransition(tester);

      expect(find.text('Join the Community'), findsAtLeastNWidgets(1));
      expect(find.text('Build Your Profile'), findsOneWidget);
      expect(find.text('Discover Information and Support'), findsOneWidget);
      expect(find.text('Connect and Coordinate Care'), findsOneWidget);
      expect(find.text('Track and Stay Informed'), findsOneWidget);
      expect(find.text('Find Strength in Support'), findsOneWidget);
      expect(
        find.textContaining('does not replace doctors, hospitals or emergency'),
        findsOneWidget,
      );
    });

    testWidgets(
        'the mission page shows mission, vision, six values and the care journey',
        (tester) async {
      await tester.pumpWidget(_localizedApp('en', home: const MissionPage()));
      await _settleRouteTransition(tester);

      expect(find.text('Mission'), findsOneWidget);
      expect(find.text('Our Vision'), findsOneWidget);
      expect(find.text('Our Core Values'), findsOneWidget);
      for (final value in const [
        'Compassion',
        'Access',
        'Community',
        'Trust',
        'Empowerment',
        'Innovation',
      ]) {
        expect(find.text(value), findsOneWidget, reason: 'value: $value');
      }
      expect(find.byType(CareJourneySection), findsOneWidget);
      expect(
        find.text('A clearer path from first tap to lasting care'),
        findsOneWidget,
      );
      expect(find.text('Join with confidence'), findsOneWidget);
      expect(find.text('Reach the right care'), findsOneWidget);
      expect(find.text('Stay supported'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(CareJourneySection)).dy,
        greaterThan(tester.getTopLeft(find.text('Our Core Values')).dy),
        reason: 'the care journey follows all existing mission content',
      );
    });

    testWidgets('the Join CTA reaches the real signup route (EN)',
        (tester) async {
      await tester
          .pumpWidget(_localizedApp('en', home: const HowItWorksPage()));
      await _settleRouteTransition(tester);

      final join = find.widgetWithText(FilledButton, 'Join the Community');
      await tester.ensureVisible(join);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(join);
      await _settleRouteTransition(tester);

      expect(find.text('signup-destination'), findsOneWidget);
    });
  });
}
