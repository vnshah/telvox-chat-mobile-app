import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
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
}
