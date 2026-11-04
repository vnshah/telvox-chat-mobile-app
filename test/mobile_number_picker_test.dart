import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/screens.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

/// Choosing what to work on, by role: a business's own people pick only
/// among its WhatsApp numbers; admins and resellers pick a business first.
void main() {
  late List<RequestOptions> requests;
  late MemoryStore store;
  var forbidden = <Object?>{};

  MobileSession account(Json user) {
    requests = [];
    store = MemoryStore();
    return MobileSession(
        fakeApi((r, h) {
          requests.add(r);
          switch (r.path) {
            case 'businesses':
              return answer(r, h, {
                'data': [
                  {'id': 10, 'name': 'Acme Foods'},
                  {'id': 20, 'name': 'Bright Travels'},
                ],
                'next_page_url': null,
              });
            case 'numbers':
              final asked = r.queryParameters['business_user_id'];
              if (forbidden.contains(asked)) {
                return answer(r, h, {
                  'status': 'business_forbidden',
                  'message': 'You cannot use that business.',
                }, 403);
              }
              final owner = asked ?? user['business_user_id'];
              return answer(r, h, {
                'data': [
                  {'id': 100 + (owner as int), 'name': 'Sales', 'phone': '911'},
                  {'id': 200 + owner, 'name': 'Support', 'phone': '912'},
                ],
              });
            case 'config':
              return answer(r, h, {'inbox': <String, dynamic>{}});
          }
          answer(r, h, {'success': true});
        }),
        store,
      )
      ..api.token = 'token'
      ..user = user;
  }

  Iterable<String> paths() => requests.map((r) => r.path);

  Future<void> picker(WidgetTester tester, MobileSession session) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: NumberPicker(session),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Choosing a number hands over to the home screen in the app; here the
  /// picker's spinner stays up, so step frames instead of settling.
  Future<void> choose(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  tearDown(() => forbidden = {});

  testWidgets('a business user picks only among its own numbers', (
    tester,
  ) async {
    final session = account({
      'id': 3,
      'role': 'is_business',
      'business_user_id': 3,
    });
    expect(session.picksBusiness, isFalse);
    await picker(tester, session);

    expect(find.text('Choose WhatsApp number'), findsOneWidget);
    expect(find.text('Choose business'), findsNothing);
    expect(paths(), isNot(contains('businesses')));
    // The server lists the account's own business; the app names none.
    final numbers = requests.firstWhere((r) => r.path == 'numbers');
    expect(numbers.queryParameters, isNot(contains('business_user_id')));
    // Nothing to go back to: no other business can be reached from here.
    expect(find.byKey(const ValueKey('picker-change-business')), findsNothing);
    expect(find.byType(BackButton), findsNothing);

    await choose(tester, 'number-203');
    expect(session.api.wabaId, 203);
    expect(session.business, isNull);
    session.dispose();
  });

  testWidgets('a manager not tied to one number stays in its business', (
    tester,
  ) async {
    final session = account({
      'id': 9,
      'role': 'is_manager',
      'business_user_id': 3,
    });
    await picker(tester, session);
    expect(find.text('Choose business'), findsNothing);
    expect(find.byKey(const ValueKey('number-103')), findsOneWidget);
    expect(paths(), isNot(contains('businesses')));
    session.dispose();
  });

  testWidgets('an admin picks a business, then one of its numbers', (
    tester,
  ) async {
    final session = account({
      'id': 1,
      'role': 'is_admin',
      'business_user_id': null,
    });
    expect(session.picksBusiness, isTrue);
    await picker(tester, session);

    expect(find.text('Choose business'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('business-20')));
    await tester.pumpAndSettle();
    expect(find.text('Choose WhatsApp number'), findsOneWidget);
    expect(find.byKey(const ValueKey('picker-business')), findsOneWidget);
    expect(find.text('Bright Travels'), findsOneWidget);
    expect(requests.lastWhere((r) => r.path == 'numbers').queryParameters, {
      'business_user_id': 20,
    });

    // Back to the businesses, and into another one.
    await tester.tap(find.byKey(const ValueKey('picker-change-business')));
    await tester.pumpAndSettle();
    expect(find.text('Choose business'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('business-10')));
    await tester.pumpAndSettle();
    await choose(tester, 'number-110');

    expect(session.api.wabaId, 110);
    expect(session.business, {'id': 10, 'name': 'Acme Foods'});
    final saved = jsonDecode(store.values[session.storageKey]!) as Map;
    expect(saved['business'], {'id': 10, 'name': 'Acme Foods'});
    expect(saved['waba_id'], 110);
    session.dispose();
  });

  testWidgets('switching number keeps an admin in the same business', (
    tester,
  ) async {
    final session = account({
      'id': 1,
      'role': 'is_reseller',
      'business_user_id': null,
    });
    session.chooseBusiness({'id': 10, 'name': 'Acme Foods'});
    await tester.runAsync(() => session.selectNumber(110));
    session.switchNumber();
    expect(session.business, {'id': 10, 'name': 'Acme Foods'});

    requests.clear();
    await picker(tester, session);
    expect(find.text('Choose WhatsApp number'), findsOneWidget);
    expect(find.text('Acme Foods'), findsOneWidget);
    expect(paths(), isNot(contains('businesses')));
    expect(
      find.byKey(const ValueKey('picker-change-business')),
      findsOneWidget,
    );
    session.dispose();
  });

  testWidgets(
    'a business the account may no longer use goes back to the list',
    (tester) async {
      final session = account({
        'id': 2,
        'role': 'is_reseller',
        'business_user_id': null,
      });
      session.chooseBusiness({'id': 20, 'name': 'Bright Travels'});
      forbidden = {20};
      await picker(tester, session);
      expect(find.text('Choose business'), findsOneWidget);
      expect(session.business, isNull);
      session.dispose();
    },
  );

  test('a business user cannot be given another business', () {
    final session = account({
      'id': 3,
      'role': 'is_business',
      'business_user_id': 3,
    })..chooseBusiness({'id': 20, 'name': 'Bright Travels'});
    expect(session.business, isNull);
    session.dispose();
  });

  test(
    'restoring keeps an admin\'s business, never a business user\'s',
    () async {
      for (final (user, kept) in [
        ({'id': 1, 'role': 'is_admin', 'business_user_id': null}, true),
        ({'id': 3, 'role': 'is_business', 'business_user_id': 3}, false),
      ]) {
        final saved = MemoryStore();
        final session = MobileSession(
          fakeApi(
            (r, h) => answer(r, h, switch (r.path) {
              'me' => user,
              _ => {'inbox': <String, dynamic>{}},
            }),
          ),
          saved,
        );
        saved.values[session.storageKey] = jsonEncode({
          'token': 'token',
          'waba_id': 110,
          'business': {'id': 10, 'name': 'Acme Foods'},
        });
        await session.restore();
        expect(
          session.business,
          kept ? {'id': 10, 'name': 'Acme Foods'} : isNull,
          reason: '${user['role']}',
        );
        expect(session.api.wabaId, 110);
        session.dispose();
      }
    },
  );
}
