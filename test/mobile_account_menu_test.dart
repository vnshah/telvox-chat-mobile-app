import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/account_menu.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/notification_sound.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

void main() {
  testWidgets('the account menu names who is signed in and picks the sound', (
    tester,
  ) async {
    final store = MemoryStore();
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {'success': true})),
      store,
    )..user = {'id': 1, 'name': 'Rahil Gothadiya', 'email': 'rahil@renav.test'};
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(
          appBar: AppBar(
            actions: [AccountMenu(session: session, onSignOut: () {})],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Rahil Gothadiya'), findsOneWidget);
    // The address sits under the name, smaller.
    final email = tester.widget<Text>(find.text('rahil@renav.test'));
    expect(email.style!.fontSize, lessThan(12));
    // WhatsApp's menu: text-only rows, nothing for developers.
    expect(find.text('Notification sound'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Performance log'), findsNothing);

    await tester.tap(find.text('Notification sound'));
    await tester.pumpAndSettle();
    // The phone's own sound is offered first, as Android's pickers do.
    expect(find.byKey(const ValueKey('sound-system')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sound-chime')));
    await tester.pump();
    // Nothing changes until OK.
    expect(session.notificationSound.value, NotificationSound.tap);
    await tester.tap(find.byKey(const ValueKey('sound-ok')));
    await tester.pumpAndSettle();

    expect(session.notificationSound.value, NotificationSound.chime);
    expect(store.values['notification_sound'], 'chime');
    session.dispose();
  });
}
