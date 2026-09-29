import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/donations/data/donations_repository.dart';
import 'package:sicklers_warriors/features/donations/presentation/pages/donations_page.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

String _donationJson({
  String status = 'PENDING',
  String displayStatus = 'INITIATED',
}) =>
    jsonEncode({
      'uid': 'don-1',
      'campaign': {'uid': 'cam-1', 'title': 'Natal Camp'},
      'amount': '10000.00',
      'currency': 'TZS',
      'status': status,
      'display_status': displayStatus,
      'transaction_ref': 'TXN-10001',
      'latest_transaction': {
        'id': 12,
        'provider': 'M_PESA',
        'status': status,
        'provider_ref': 'ref-12',
        'redacted_ref': 'ref…12',
        'attempt': 1,
      },
      'created_at': '2026-09-23T10:00:00Z',
    });

/// Client covering the whole donations flow.
MockClient _donationsClient() {
  final initiated = <String, dynamic>{
    'data': {
      'results': [
        {
          'uid': 'cam-1',
          'title': 'Natal Camp',
          'description': 'Support newborn screening kits.',
          'goal_amount': '1000000.00',
          'raised_amount': '400000.00',
          'currency': 'TZS',
          'status': 'ACTIVE',
          'progress': 0.4,
          'owner': {'uid': 'u1', 'display_name': 'Warriors Org'},
          'created_at': '2026-09-01T08:00:00Z',
        },
      ],
    },
  };
  var confirmNext = false;
  return MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/campaigns/' && request.method == 'GET') {
      return _json(initiated);
    }
    if (path == '/api/campaigns/cam-1/' && request.method == 'GET') {
      final payload = initiated['data'] as Map<String, dynamic>;
      final campaign =
          (payload['results'] as List).first as Map<String, dynamic>;
      return _json({'data': campaign});
    }
    if (path == '/api/donations/' && request.method == 'GET') {
      if (confirmNext) {
        return _json({
          'data': {
            'results': [
              jsonDecode(_donationJson(
                status: 'COMPLETED',
                displayStatus: 'CONFIRMED',
              )),
            ],
          },
        });
      }
      return _json({
        'data': {'results': [jsonDecode(_donationJson())]},
      });
    }
    if (path == '/api/donations/' && request.method == 'POST') {
      return _json({'data': jsonDecode(_donationJson())}, 201);
    }
    if (path == '/api/donations/don-1/' && request.method == 'GET') {
      return _json({'data': jsonDecode(_donationJson())});
    }
    if (path == '/api/donations/don-1/receipt/' && request.method == 'GET') {
      return _json({
        'data': {
          'receipt_number': 'WARRIOR-RCP-TXN-10001',
          'donation_uid': 'don-1',
          'campaign_title': 'Natal Camp',
          'amount': '10000.00',
          'currency': 'TZS',
          'status': 'COMPLETED',
          'transaction_ref': 'TXN-10001',
          'donated_at': '2026-09-23T10:00:00Z',
        },
      });
    }
    if (path == '/api/payments/12/retry/' && request.method == 'POST') {
      confirmNext = true;
      return _json({
        'data': {
          'id': 13,
          'donation_uid': 'don-1',
          'provider': 'M_PESA',
          'status': 'PENDING',
          'provider_ref': 'ref-13',
          'redacted_ref': 'ref…13',
          'attempt': 2,
        },
      });
    }
    return _json({
      'error': {'code': 'NOT_FOUND', 'message': 'None'}
    }, 404);
  });
}

void main() {
  group('Stage 4.12 donations', () {
    testWidgets('DonationsPage guards when signed out', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DonationsPage()));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    });

    test('Campaign parses public projection', () {
      final campaign = Campaign.fromJson({
        'uid': 'cam-1',
        'title': 'Natal Camp',
        'goal_amount': '1000000.00',
        'raised_amount': '400000.00',
        'currency': 'TZS',
        'status': 'ACTIVE',
        'progress': 0.4,
        'owner': {'uid': 'u1', 'display_name': 'Warriors Org'},
      });
      expect(campaign.uid, 'cam-1');
      expect(campaign.isActive, isTrue);
      expect(campaign.ownerName, 'Warriors Org');
      expect(campaign.progress, 0.4);
    });

    test('Donation models display status', () {
      final pending = Donation.fromJson(
        jsonDecode(_donationJson()) as Map<String, dynamic>,
      );
      expect(pending.isInitiated, isTrue);
      expect(pending.canRetry, isTrue);

      final done = Donation.fromJson(
        jsonDecode(_donationJson(
          status: 'COMPLETED',
          displayStatus: 'CONFIRMED',
        )) as Map<String, dynamic>,
      );
      expect(done.isConfirmed, isTrue);
      expect(done.canRetry, isFalse);
    });

    testWidgets('DonationsHomeView lists verified campaigns and history',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DonationsHomeView(
            accessToken: 'test-access',
            repository: DonationsRepository(
              tokenStore: EphemeralTokenStore(),
              client: _donationsClient(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Natal Camp'), findsWidgets);
      expect(find.text(AppStrings.donateNow), findsWidgets);
      expect(
        find.text(
          '${AppStrings.donationsHistory} · 1',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('INITIATED'), findsOneWidget);
    });

    testWidgets('Donating goes through initiate, status and (later) receipt',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = _donationsClient();
      await tester.pumpWidget(
        MaterialApp(
          home: DonationsHomeView(
            accessToken: 'test-access',
            repository: DonationsRepository(
              tokenStore: EphemeralTokenStore(),
              client: client,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.donateNow).first);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.confirmDonation), findsOneWidget);

      // Consent gate disables submission until checked.
      final confirmButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(AppStrings.confirmDonation),
          matching: find.byType(FilledButton),
        ),
      );
      expect(confirmButton.onPressed, isNull);

      // Pick a preset amount, then consent.
      await tester.tap(find.text('10000.0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.shareDonationRef));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.confirmDonation));
      await tester.pumpAndSettle();

      // Initiated snackbar then status sheet.
      expect(find.text(AppStrings.checkStatus), findsOneWidget);
      expect(find.text(AppStrings.retryDonation), findsOneWidget);
      expect(find.text('INITIATED'), findsWidgets);

      // Receipt not offered until confirmed.
      expect(find.text(AppStrings.receiptNotAvailable), findsNothing);

      // Retry re-submits the pending transaction.
      await tester.tap(find.text(AppStrings.retryDonation));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.retryingDonation), findsOneWidget);
    });
  });
}