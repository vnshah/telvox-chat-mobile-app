import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/call_history.dart';
import 'package:telvox_chat_mobile_app/mobile/message_info.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

final today = DateTime.now().toUtc();
String iso(Duration ago) => today.subtract(ago).toIso8601String();

final calls = [
  {
    'id': 3,
    'call_id': 'wacid.MISSED',
    'direction': 'incoming',
    'status': 'missed',
    'started_at': iso(const Duration(minutes: 5)),
    'duration_seconds': 0,
    'ring_seconds': 25,
    'agent': null,
  },
  {
    'id': 2,
    'call_id': 'wacid.OUT',
    'direction': 'outgoing',
    'status': 'rejected',
    'started_at': iso(const Duration(minutes: 30)),
    'duration_seconds': 0,
    'ring_seconds': 7,
    'agent': {'id': 9, 'name': 'Priya'},
  },
  {
    'id': 1,
    'call_id': 'wacid.IN',
    'direction': 'incoming',
    'status': 'answered',
    'started_at': iso(const Duration(hours: 1)),
    'ring_started_at': iso(const Duration(hours: 1)),
    'answered_at': iso(const Duration(minutes: 59, seconds: 54)),
    'ended_at': iso(const Duration(minutes: 59, seconds: 21)),
    'duration_seconds': 33,
    'ring_seconds': 6,
    'agent': {'id': 7, 'name': 'Ravin'},
    'failure_reason': null,
    'recorded': false,
  },
];

void main() {
  testWidgets('call history lists each call and shows its details', (
    tester,
  ) async {
    final asked = <RequestOptions>[];
    final session = MobileSession(
      fakeApi((r, h) {
        asked.add(r);
        answer(r, h, {'success': true, 'data': calls});
      }),
      MemoryStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: CallHistoryPage(session, const {
          'id': 12,
          'profile_name': 'Rahil',
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked.single.path, 'inbox/call-history');
    expect(asked.single.data, {'contact_id': 12, 'limit': 100});
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Rejected · from Priya'), findsOneWidget);
    expect(find.text('Answered · by Ravin · 33 secs'), findsOneWidget);
    // Unanswered calls are red, as in a phone's call log.
    final missedTitle = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('call-log-3')),
        matching: find.text('Incoming call'),
      ),
    );
    expect(missedTitle.style?.color, T.danger);

    await tester.tap(find.byKey(const ValueKey('call-log-1')));
    await tester.pumpAndSettle();
    expect(find.text('Answered by'), findsOneWidget);
    expect(find.text('Ravin'), findsOneWidget);
    expect(find.text('6 secs'), findsOneWidget);
    expect(find.textContaining('wacid.IN'), findsOneWidget);
    session.dispose();
  });

  testWidgets('an empty history says so', (tester) async {
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {'success': true, 'data': []})),
      MemoryStore(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CallHistoryPage(session, const {'id': 12})),
    );
    await tester.pumpAndSettle();
    expect(find.text('No calls with this customer yet'), findsOneWidget);
    session.dispose();
  });

  Future<void> openInfo(WidgetTester tester, Json json) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessageInfo(context, ApiMessage(json)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String row(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      )
      .last
      .data!;

  testWidgets('message info shows WhatsApp’s receipts, and never a guess', (
    tester,
  ) async {
    await openInfo(tester, {
      'id': 1,
      'type': 1,
      'message_type': 'text',
      'message_body': 'Your order ships today',
      'message_status': 2,
      'sent_at': '2026-11-02 10:00:00',
      'delivered_at': '2026-11-02 10:00:05',
      'read_at': null,
    });
    expect(find.text('Message info'), findsOneWidget);
    expect(row(tester, 'info-sent'), isNot('—'));
    expect(row(tester, 'info-delivered'), isNot('—'));
    // Not read yet, or read receipts are off: no time is invented.
    expect(row(tester, 'info-read'), '—');
    expect(find.byKey(const ValueKey('info-played')), findsNothing);
  });

  testWidgets('a failed message says it was not delivered, and why', (
    tester,
  ) async {
    await openInfo(tester, {
      'id': 2,
      'type': 1,
      'message_type': 'text',
      'message_body': 'Hello',
      'message_status': 4,
      'failed_reason': 'Message undeliverable',
      'sent_at': null,
    });
    expect(row(tester, 'info-failed'), 'Message undeliverable');
    expect(find.byKey(const ValueKey('info-read')), findsNothing);
    expect(row(tester, 'info-sent'), '—');
  });
}
