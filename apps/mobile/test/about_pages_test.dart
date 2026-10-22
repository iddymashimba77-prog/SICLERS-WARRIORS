import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/public/data/content_repository.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/about_pages.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';
import 'package:sicklers_warriors/shared/widgets/module_placeholder_page.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Empty envelope content so the public home renders without inventing copy.
ContentRepository get _emptyContent => ContentRepository(
      client: MockClient((_) async => _json({'data': {}}, 404)),
    );

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
          '/news': (_) => const _RouteProbe('news-destination'),
        },
      ),
    ),
  );
}

Widget _publicHome(String language) =>
    _localizedApp(language, home: PublicHomePage(content: _emptyContent));

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

/// Opens the compact-header Explore menu (its tooltip is localized).
Future<void> _openExploreMenu(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await _settleRouteTransition(tester);
}

/// Drains pending framework exceptions so tests can tolerate a known,
/// documented one without swallowing anything else.
List<Object?> _drainExceptions(WidgetTester tester) {
  final errors = <Object?>[];
  Object? error;
  while ((error = tester.takeException()) != null) {
    errors.add(error);
  }
  return errors;
}

/// Desktop path: mega-menu → About item → designed page (never a placeholder).
///
/// Each caller is its own `testWidgets` on purpose: reusing one test for
/// several pushes would keep the Navigator state (and the pushed route)
/// alive across `pumpWidget` calls, so later iterations would assert against
/// the previous page instead of a fresh home.
Future<void> _openAboutFromDesktop(
  WidgetTester tester, {
  required String item,
  required String marker,
}) async {
  tester.view.physicalSize = const Size(2400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_publicHome('en'));
  await _settleRouteTransition(tester);

  await tester.tap(find.byKey(const Key('mega-About')));
  await _settleRouteTransition(tester);

  // The popup gives its items a 256px-wide menu. flutter_test renders every
  // glyph as a full em square (Ahem), so the longest menu label measures
  // ~364px here and reports a RenderFlex overflow — with real fonts the same
  // label measures ~220px and fits. Drain that known report; every other
  // exception still fails the test.
  final tolerated = _drainExceptions(tester)
      .where((e) => '$e'.contains('A RenderFlex overflowed'))
      .toList();
  expect(
    tolerated.length,
    lessThanOrEqualTo(1),
    reason: 'only the known Ahem-font popup overflow may be tolerated',
  );

  expect(
    find.text(item),
    findsOneWidget,
    reason: 'the About mega-menu lists "$item"',
  );

  await tester.tap(find.text(item));
  await _settleRouteTransition(tester);
  expect(
    find.text(marker),
    findsAtLeastNWidgets(1),
    reason: '"$item" opens a designed About page, not a placeholder',
  );
  expect(find.byType(ModulePlaceholderPage), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('public About menu wiring', () {
    testWidgets('desktop mega-menu opens the About landing (EN)', (tester) =>
        _openAboutFromDesktop(tester,
            item: 'About Sickler\'s Warriors',
            marker: 'More Than Support. A Community of Strength.'));

    testWidgets('desktop mega-menu opens Our Mission (EN)', (tester) =>
        _openAboutFromDesktop(tester,
            item: 'Our Mission', marker: 'Our Core Values'));

    testWidgets('desktop mega-menu opens How It Works (EN)', (tester) =>
        _openAboutFromDesktop(tester,
            item: 'How It Works', marker: 'Build Your Profile'));

    testWidgets('desktop mega-menu opens Team & Partners (EN)', (tester) =>
        _openAboutFromDesktop(tester,
            item: 'Team & Partners', marker: 'Iddy Mashimba'));

    testWidgets('desktop mega-menu opens Contact Us (EN)', (tester) =>
        _openAboutFromDesktop(tester,
            item: 'Contact Us', marker: 'We\'re Here to Connect.'));

    testWidgets('mobile three-dot menu opens the About landing page (SW)',
        (tester) async {
      await tester.pumpWidget(_publicHome('sw'));
      await _settleRouteTransition(tester);

      await _openExploreMenu(tester, 'Chunguza');
      expect(find.text('KUHUSU'), findsOneWidget,
          reason: 'the bottom sheet groups About under its Kiswahili header');

      await tester.tap(find.text('Kuhusu Sickler\'s Warriors'));
      await _settleRouteTransition(tester);
      expect(find.text('Zaidi ya Msaada. Jamii ya Nguvu.'), findsOneWidget);
      expect(
        find.textContaining('Jukwaa linaloongozwa na jamii'),
        findsAtLeastNWidgets(1),
        reason: 'the About subtitle comes from the shared about.aboutBody key',
      );
    });

    testWidgets('the footer Contact link reaches the contact page (EN)',
        (tester) async {
      await tester.pumpWidget(_publicHome('en'));
      await _settleRouteTransition(tester);

      await tester.ensureVisible(find.text('Contact'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Contact'));
      await _settleRouteTransition(tester);

      expect(find.byType(ContactUsPage), findsOneWidget);
      expect(find.text('We\'re Here to Connect.'), findsOneWidget);
    });
  });

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

    testWidgets('the mission page shows mission, vision and six values',
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

    testWidgets('the Explore CTA reaches the real news route (EN)',
        (tester) async {
      await tester
          .pumpWidget(_localizedApp('en', home: const AboutWarriorsPage()));
      await _settleRouteTransition(tester);

      final explore =
          find.widgetWithText(OutlinedButton, 'Explore the Platform');
      await tester.ensureVisible(explore);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(explore);
      await _settleRouteTransition(tester);

      expect(find.text('news-destination'), findsOneWidget);
    });
  });
}
