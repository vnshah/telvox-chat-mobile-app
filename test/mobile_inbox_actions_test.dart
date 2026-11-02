import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
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
}
