import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/account_menu.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

/// What the app stores require of an account: a privacy policy, and a
/// sign-out that always works.
void main() {
  testWidgets('the account menu links the privacy policy; no deletion', (
    tester,
  ) async {
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {'success': true})),
      MemoryStore(),
    )..user = {'id': 1, 'name': 'Asha Mehta', 'email': 'a@b.test'};
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
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(privacyPolicyUrl, startsWith('https://'));
    // Accounts are made and removed by the business, not in the app.
    expect(find.text('Delete account'), findsNothing);
    session.dispose();
  });

  test('signing out works offline: the phone forgets the account', () async {
    final store = MemoryStore();
    final session = MobileSession(
      fakeApi((r, h) {
        if (r.path == 'auth/logout') {
          return h.reject(
            DioException.connectionError(
              requestOptions: r,
              reason: 'No network',
            ),
          );
        }
        answer(r, h, {'success': true});
      }),
      store,
    );
    session.api.token = 'token';
    session.user = {'id': 1};
    store.values[session.storageKey] = '{"token":"token"}';

    await session.logout();

    expect(session.api.token, isNull);
    expect(session.user, isNull);
    expect(store.values.containsKey(session.storageKey), isFalse);
    session.dispose();
  });
}
