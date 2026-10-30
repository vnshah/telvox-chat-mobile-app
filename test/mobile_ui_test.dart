import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/app.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

void main() {
  testWidgets('live login contains no demo credentials or admin navigation', (
    tester,
  ) async {
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {})),
      MemoryStore(),
    );
    await tester.pumpWidget(MobileApplication(session: session));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('renav@studionorth.co'), findsNothing);
    expect(find.text('Create account'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('bound login opens real inbox and expiry clears navigation', (
    tester,
  ) async {
    final api = fakeApi(
      (r, h) => answer(r, h, switch (r.path) {
        'auth/login' => {'status': 'authenticated', 'token': 'token'},
        'me' => {'id': 1, 'bound_waba_user_id': 5},
        'config' => {'inbox': {}, 'capabilities': {}},
        'inbox/contacts' => <dynamic>[],
        _ => {'success': true},
      }),
    );
    final session = MobileSession(api, MemoryStore());
    await tester.pumpWidget(MobileApplication(session: session));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'test@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Choose business'), findsNothing);
    api.onUnauthorized!();
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets(
    'real chat displays fetched text and failed sends never appear sent',
    (tester) async {
      final api = fakeApi(
        (r, h) => answer(r, h, switch (r.path) {
          'inbox/messages' => {
            'success': true,
            'data': [
              {
                'id': 1,
                'message_id': 'wamid.one',
                'type': 2,
                'message_body': 'Real server message',
                'message_type': 'text',
                'created_at': '2026-10-29 11:00:00',
              },
            ],
            'meta': {'has_more': false, 'sync_from': '2026-10-29T06:00:00Z'},
          },
          'inbox/getContactDetails' => {
            'success': true,
            'data': {
              'contact': {
                'service_expiration_timestamp': '2099-01-01T00:00:00Z',
                'assigned_to': 1,
                'conversation_status': 1,
              },
              'assignUser': {'id': 1},
              'child_user_ids': [1],
            },
          },
          'inbox/send' => {
            'success': false,
            'message': 'Customer session expired',
          },
          _ => {'success': true},
        }),
      );
      final session = MobileSession(api, MemoryStore());
      api.token = 'test';
      api.wabaId = 7;
      session.user = {'id': 1};
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: LiveChat(session, {
            'id': 2,
            'wa_id': '919999999999',
            'profile_name': 'Customer',
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Real server message', findRichText: true),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'A real draft');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Customer session expired'), findsOneWidget);
      expect(find.byTooltip('Delete for me'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
