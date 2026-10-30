import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/mobile/screens.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_test.dart' show details, sampleMessages;

const contact = {'id': 12, 'profile_name': 'Alex', 'wa_id': '919999999999'};

Widget app(Widget home) =>
    MaterialApp(theme: T.themeFor(TargetPlatform.android), home: home);

void main() {
  testWidgets('sending a template returns straight to the conversation', (
    tester,
  ) async {
    var sent = 0;
    final api = fakeApi((r, h) {
      if (r.path == 'inbox/send-template-by-contact') sent++;
      answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {
          'success': true,
          'data': details(expiry: '2020-01-01T00:00:00Z'),
        },
        'inbox/messages' => {
          'success': true,
          'data': sampleMessages,
          'meta': {'has_more': false},
        },
        'inbox/templates' => {
          'success': true,
          'data': [
            {
              'id': 5,
              'name': 'order_update',
              'category': 'UTILITY',
              'language': 'en',
            },
          ],
        },
        'inbox/templates/5' => {
          'success': true,
          'data': {
            'id': 5,
            'name': 'order_update',
            'category': 'UTILITY',
            'rowdata': [
              {'type': 'BODY', 'text': 'Your order is ready.'},
            ],
          },
        },
        _ => {'success': true},
      });
    });
    final session = MobileSession(api, MemoryStore())..user = {'id': 1};
    await tester.pumpWidget(app(LiveChat(session, contact)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('order_update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send template'));
    await tester.pumpAndSettle();
    expect(sent, 1);
    expect(find.text('Templates'), findsNothing);
    expect(find.byType(LiveChat), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('idle chat polls messages without refetching contact details', (
    tester,
  ) async {
    final calls = <String, int>{};
    final api = fakeApi((r, h) {
      calls.update(r.path, (n) => n + 1, ifAbsent: () => 1);
      answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {'success': true, 'data': details()},
        'inbox/messages' => {
          'success': true,
          'data': sampleMessages,
          'meta': {'has_more': false},
        },
        _ => {'success': true},
      });
    });
    final session = MobileSession(api, MemoryStore())..user = {'id': 1};
    await tester.pumpWidget(app(LiveChat(session, contact)));
    await tester.pumpAndSettle();
    expect(calls['inbox/getContactDetails'], 1);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(calls['inbox/messages'], 6);
    expect(calls['inbox/getContactDetails'], 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls['inbox/getContactDetails'], 2);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'reopening a chat shows cached permissions without a layout swap',
    (tester) async {
      final api = fakeApi(
        (r, h) => answer(r, h, switch (r.path) {
          'inbox/getContactDetails' => {'success': true, 'data': details()},
          'inbox/messages' => {
            'success': true,
            'data': sampleMessages,
            'meta': {'has_more': false},
          },
          _ => {'success': true},
        }),
      );
      final session = MobileSession(api, MemoryStore())..user = {'id': 1};
      await tester.pumpWidget(app(LiveChat(session, contact)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(LiveChat(session, contact)));
      // First frame, before any response: composer already usable from cache.
      expect(find.textContaining('Checking conversation'), findsNothing);
      expect(find.byTooltip('Send message'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('inbox survives app resume and shares rows with Contacts', (
    tester,
  ) async {
    var listRequests = 0;
    final api = fakeApi((r, h) {
      if (r.path == 'inbox/contacts') listRequests++;
      answer(r, h, switch (r.path) {
        'inbox/contacts' => [
          {'id': 12, 'profile_name': 'Alex', 'wa_id': '919999999999'},
        ],
        _ => {'success': true},
      });
    });
    final session = MobileSession(api, MemoryStore())
      ..user = {'id': 1}
      ..config = {};
    await tester.pumpWidget(app(LiveHome(session)));
    await tester.pumpAndSettle();
    expect(listRequests, 1);
    final before = tester.state(find.byType(LiveList));

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    // One quiet refresh, no rebuild of the list and no loading strip.
    expect(tester.state(find.byType(LiveList)), same(before));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(listRequests, 2);

    await tester.tap(find.text('Contacts'));
    await tester.pump();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  test('list times read like WhatsApp: time, Yesterday, weekday, date', () {
    // Thursday 30 Oct 2026, 12:00 in Asia/Kolkata.
    final now = DateTime.utc(2026, 10, 30, 6, 30);
    const clock = MobileClock();
    expect(clock.listTime('2026-10-30T04:35:00Z', now: now), '10:05');
    expect(clock.listTime('2026-10-29T04:35:00Z', now: now), 'Yesterday');
    expect(clock.listTime('2026-10-26T04:35:00Z', now: now), 'Monday');
    expect(clock.listTime('2026-10-20T04:35:00Z', now: now), '20/10/26');
    expect(clock.listTime(null, now: now), '');
  });

  testWidgets('inbox rows show unread, ticks and conversation markers', (
    tester,
  ) async {
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {})),
      MemoryStore(),
    )..user = {'id': 1};
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Column(
            children: [
              LiveConversationRow(
                session: session,
                onTap: () {},
                item: {
                  'id': 12,
                  'profile_name': 'Alex',
                  'unread_message_count': 99,
                  'favourite': '[1]',
                  'conversation_status': 0,
                  'conversation_owner_type': 1,
                  'is_blocked': true,
                  'is_dnd': 1,
                  'last_message': {
                    'type': 1,
                    'message_status': 3,
                    'message_type': 'text',
                    'message_body': 'Order shipped',
                    'created_at': '2026-10-30T04:35:00Z',
                  },
                },
              ),
              LiveConversationRow(
                session: session,
                onTap: () {},
                item: {'id': 13, 'waba_profile_name': 'Sam'},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('Order shipped'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    for (final label in [
      'Closed',
      'Bot',
      'Blocked',
      'Do not disturb',
      'Favourite',
    ]) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  test('date separators read Today, Yesterday, weekday, then full date', () {
    final now = DateTime.utc(2026, 10, 30, 6, 30);
    const clock = MobileClock();
    expect(clock.dayLabel('2026-10-30T04:35:00Z', now: now), 'Today');
    expect(clock.dayLabel('2026-10-29T04:35:00Z', now: now), 'Yesterday');
    expect(clock.dayLabel('2026-10-26T04:35:00Z', now: now), 'Monday');
    expect(clock.dayLabel('2026-10-20T04:35:00Z', now: now), '20 Oct 2026');
  });

  testWidgets('ticket rows show status, priority and assignee', (tester) async {
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {})),
      MemoryStore(),
    )..user = {'id': 1};
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Column(
            children: [
              LiveConversationRow(
                session: session,
                ticket: true,
                onTap: () {},
                people: const {2: 'Priya Shah'},
                item: {
                  'id': 7,
                  'subject': 'Refund request',
                  'assign_user_id': 2,
                  'status': {'name': 'Open'},
                  'priority': {'name': 'High'},
                  'contact': {'profile_name': 'Alex'},
                },
              ),
              LiveConversationRow(
                session: session,
                ticket: true,
                onTap: () {},
                item: {'id': 8, 'subject': 'Login issue', 'contact': {}},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Refund request'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.byTooltip('Assigned to Priya Shah'), findsOneWidget);
    expect(find.text('PS'), findsOneWidget);
    expect(find.text('UNASSIGNED'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
