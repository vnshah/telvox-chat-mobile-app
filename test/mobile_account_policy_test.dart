import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/account_menu.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

/// What the app stores require of an account: a privacy policy and a way to
/// ask for deletion from inside the app, and a sign-out that always works.
void main() {
  group('delete account, as the stores require', () {
    late List<RequestOptions> requests;
    late MobileSession session;

    Future<void> openMenu(
      WidgetTester tester, {
      Json? user,
      int status = 202,
    }) async {
      requests = [];
      session = MobileSession(
        fakeApi((r, h) {
          requests.add(r);
          if (r.path == 'me/deletion-request') {
            return status == 202
                ? answer(r, h, {
                    'status': 'requested',
                    'requested_at': '2026-11-04T06:30:00Z',
                  }, 202)
                : answer(r, h, {
                    'success': false,
                    'message': 'Please try again in a minute.',
                  }, status);
          }
          answer(r, h, {'success': true});
        }),
        MemoryStore(),
      )..user = user ?? {'id': 1, 'name': 'Asha Mehta', 'email': 'a@b.test'};
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
    }

    Iterable<RequestOptions> deletions() =>
        requests.where((r) => r.path == 'me/deletion-request');

    testWidgets('the menu offers the privacy policy and deletion', (
      tester,
    ) async {
      await openMenu(tester);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(privacyPolicyUrl, startsWith('https://'));
      session.dispose();
    });

    testWidgets('confirming sends one request and says what happens next', (
      tester,
    ) async {
      await openMenu(tester);
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pumpAndSettle();

      expect(deletions(), hasLength(1));
      expect(deletions().single.method, 'POST');
      expect(find.text('Request sent'), findsOneWidget);
      expect(session.user!['deletion_requested_at'], '2026-11-04T06:30:00Z');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Asking again only says when it was asked.
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Deletion requested'), findsOneWidget);
      expect(find.textContaining('04/11/2026'), findsOneWidget);
      expect(deletions(), hasLength(1));
      session.dispose();
    });

    testWidgets('cancelling sends nothing', (tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletions(), isEmpty);
      expect(session.user!['deletion_requested_at'], isNull);
      session.dispose();
    });

    testWidgets('a request the server refuses is reported, not recorded', (
      tester,
    ) async {
      await openMenu(tester, status: 429);
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Please try again in a minute.'), findsOneWidget);
      expect(session.user!['deletion_requested_at'], isNull);
      session.dispose();
    });

    testWidgets('an account already marked by the server is not asked twice', (
      tester,
    ) async {
      await openMenu(
        tester,
        user: {'id': 1, 'deletion_requested_at': '2026-11-01T10:00:00Z'},
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Deletion requested'), findsOneWidget);
      expect(deletions(), isEmpty);
      session.dispose();
    });
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
