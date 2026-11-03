import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/conversation_window.dart';
import 'package:telvox_chat_mobile_app/mobile/screens.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

/// Lets the fake server answer, then lets the list redraw.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  Future<MobileSession> inbox(
    WidgetTester tester,
    List<Json> Function() list,
    List<String> calls,
  ) async {
    final api = fakeApi((r, h) {
      calls.add(r.path);
      answer(r, h, switch (r.path) {
        'inbox/contacts' => list(),
        _ => {'success': true, 'data': <dynamic>[]},
      });
    })..wabaId = 7;
    final session = MobileSession(api, MemoryStore())..user = {'id': 1};
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(body: LiveList(session, kind: 0)),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('a long press favourites a chat without opening it', (
    tester,
  ) async {
    final calls = <String>[];
    var favourite = '[]';
    final session = await inbox(
      tester,
      () => [
        {
          'id': 5,
          'profile_name': 'Asha',
          'conversation_status': 1,
          'favourite': favourite,
        },
      ],
      calls,
    );
    await tester.longPress(find.text('Asha'));
    await tester.pumpAndSettle();
    expect(find.text('Open chat'), findsOneWidget);
    expect(find.text('Close conversation'), findsOneWidget);
    favourite = '[1]';
    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();
    expect(calls, contains('inbox/contacts/5/favorite'));
    expect(find.text('Added to favourites.'), findsOneWidget);

    // The list refreshed quietly: the next long press offers the reverse.
    await tester.longPress(find.text('Asha'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from favourites'), findsOneWidget);
    await tester.tap(find.text('Close conversation'));
    await tester.pumpAndSettle();
    expect(calls, contains('inbox/conversation/close'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });

  testWidgets('swiping a row marks it read or closes it, and keeps it', (
    tester,
  ) async {
    final calls = <String>[];
    final session = await inbox(
      tester,
      () => [
        {
          'id': 6,
          'profile_name': 'Ravi',
          'conversation_status': 1,
          'unread_message_count': 2,
        },
      ],
      calls,
    );
    await tester.timedDrag(
      find.text('Ravi'),
      const Offset(500, 0),
      const Duration(milliseconds: 300),
    );
    await settle(tester);
    expect(calls, contains('inbox/mark-read'));
    expect(find.text('Ravi'), findsOneWidget);

    await tester.timedDrag(
      find.text('Ravi'),
      const Offset(-500, 0),
      const Duration(milliseconds: 300),
    );
    await settle(tester);
    expect(calls, contains('inbox/conversation/close'));
    expect(find.text('Conversation closed.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });

  testWidgets('an empty inbox says what is missing, not that it failed', (
    tester,
  ) async {
    final session = await inbox(tester, () => [], []);
    expect(find.textContaining('No chats yet'), findsOneWidget);
    expect(find.text('No results in this view.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });

  group('conversation window', () {
    final now = DateTime.utc(2026, 11, 2, 12);
    String at(Duration d) => now.add(d).toIso8601String();

    test(
      'opens from WhatsApp\'s expiry, or 24 hours after the customer wrote',
      () {
        expect(
          windowOpen(
            windowExpiresAt({
              'service_expiration_timestamp': at(const Duration(hours: 3)),
            }),
            now,
          ),
          isTrue,
        );
        // Expired on the contact, but a newer message from the customer reopened it.
        final reopened = windowExpiresAt(
          {'service_expiration_timestamp': at(const Duration(hours: -1))},
          [
            {'type': 2, 'created_at': at(const Duration(hours: -2))},
          ],
        );
        expect(reopened, now.add(const Duration(hours: 22)));
        // Our own message never opens it.
        expect(
          windowExpiresAt({}, [
            {'type': 1, 'created_at': at(Duration.zero)},
          ]),
          isNull,
        );
        expect(windowOpen(null, now), isFalse);
        expect(
          windowLabel(now.add(const Duration(minutes: 90)), now),
          '1h 30m left',
        );
        expect(
          windowLabel(now.subtract(const Duration(minutes: 1)), now),
          'Window closed',
        );
      },
    );
  });

  testWidgets(
    'the green dot marks chats whose window is open, not recent ones',
    (tester) async {
      final soon = DateTime.now().toUtc().add(const Duration(hours: 5));
      final gone = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final session = await inbox(
        tester,
        () => [
          {
            'id': 1,
            'profile_name': 'Open window',
            'service_expiration_timestamp': soon.toIso8601String(),
          },
          {
            'id': 2,
            'profile_name': 'Closed window',
            'service_expiration_timestamp': gone.toIso8601String(),
            // Read a minute ago: recent, but the window is shut.
            'last_message': {
              'type': 1,
              'read_at': DateTime.now().toUtc().toIso8601String(),
            },
          },
        ],
        [],
      );
      Finder dotIn(String name) => find.descendant(
        of: find
            .ancestor(of: find.text(name), matching: find.byType(InkWell))
            .first,
        matching: find.byKey(const ValueKey('online-dot')),
      );
      expect(dotIn('Open window'), findsOneWidget);
      expect(dotIn('Closed window'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
    },
  );

  testWidgets(
    'a list without window fields shows the dot an opened chat learned',
    (tester) async {
      knownWindows.value = {};
      addTearDown(() => knownWindows.value = {});
      final soon = DateTime.now().toUtc().add(const Duration(hours: 6));
      // As an older server lists it: no expiry, our message last.
      final session = await inbox(
        tester,
        () => [
          {
            'id': 3,
            'profile_name': 'Nikunj',
            'last_message': {
              'type': 1,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          },
        ],
        [],
      );
      Finder dot() => find.byKey(const ValueKey('online-dot'));
      expect(dot(), findsNothing);

      // Opening the chat loads the contact in full; the row follows at once.
      rememberWindow(3, soon);
      await tester.pump();
      expect(dot(), findsOneWidget);

      // An older expiry never takes the dot away.
      rememberWindow(3, soon.subtract(const Duration(hours: 10)));
      expect(knownWindows.value['3'], soon);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
    },
  );
}
