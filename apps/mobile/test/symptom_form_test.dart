import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/health/data/health_repository.dart';
import 'package:sicklers_warriors/features/health/presentation/pages/symptom_form_page.dart';

/// The patient's "Log how I'm feeling" flow: the check-in card on the home
/// dashboard and the Health Tracking page both push [SymptomFormPage], so a
/// patient must be able to load the catalog, fill the form and save it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('patient fills in how they feel and saves', (tester) async {
    // A tall surface so the whole form (including the notes field, which the
    // ListView only builds once it is near the viewport) is laid out.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <String>[];
    String? postedBody;

    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET') {
        // ApiEnvelopeRenderer shape for an unpaginated vocabulary: `data` is a
        // bare list, not a `{results: …}` page.
        return http.Response(
          jsonEncode({
            'data': [
              {'code': 'pain_crisis', 'name': 'Pain crisis', 'is_pain_related': true},
              {'code': 'headache', 'name': 'Headache', 'is_pain_related': false},
            ],
            'meta': {'correlation_id': ''},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      postedBody = request.body;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {
            'uid': 'sym-9',
            'symptom_type_code': body['symptom_type_code'],
            'pain_level': body['pain_level'],
            'triggers': body['triggers'],
            'duration_minutes': body['duration_minutes'],
            'notes': body['notes'] ?? '',
            'recorded_at': body['recorded_at'],
          },
          'meta': {'correlation_id': ''},
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    });

    final repository = HealthRepository(
      tokenStore: EphemeralTokenStore(),
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(home: _CheckInHost(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open check-in'));
    await tester.pumpAndSettle();

    // The catalog loaded, so the real form renders — not the load-error state.
    expect(find.text(AppStrings.retry), findsNothing);
    expect(find.text(AppStrings.symptomSaveFailed), findsNothing);
    expect(find.text('Pain crisis'), findsOneWidget);
    expect(find.text(AppStrings.save), findsOneWidget);
    expect(requests, contains('GET /api/symptom-types/'));

    // Record how the warrior feels.
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged?.call(8);
    await tester.pump();
    expect(find.text('8/10'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'Maumivu makali jioni.',
    );
    await tester.tap(find.text(AppStrings.save));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requests, contains('POST /api/symptoms/'));
    expect(postedBody, isNotNull);
    final posted = jsonDecode(postedBody!) as Map<String, dynamic>;
    expect(posted['symptom_type_code'], 'pain_crisis');
    expect(posted['pain_level'], 8);
    expect(posted['notes'], 'Maumivu makali jioni.');
    expect(posted['recorded_at'], isA<String>());

    // The caller (home dashboard check-in card) receives `saved == true`.
    expect(find.text('saved:true'), findsOneWidget);
  });

  testWidgets('an empty catalog still surfaces the retry state', (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'data': <dynamic>[], 'meta': {'correlation_id': ''}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SymptomFormPage(
          accessToken: 'token',
          repository: HealthRepository(
            tokenStore: EphemeralTokenStore(),
            client: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.retry), findsOneWidget);
  });
}

class _CheckInHost extends StatefulWidget {
  const _CheckInHost({required this.repository});

  final HealthRepository repository;

  @override
  State<_CheckInHost> createState() => _CheckInHostState();
}

class _CheckInHostState extends State<_CheckInHost> {
  String _result = 'idle';

  Future<void> _open() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SymptomFormPage(
          accessToken: 'token',
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _result = 'saved:$saved');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(onPressed: _open, child: const Text('Open check-in')),
            const SizedBox(height: 12),
            Text(_result),
          ],
        ),
      ),
    );
  }
}
