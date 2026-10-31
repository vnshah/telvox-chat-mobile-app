import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/app.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/screens.dart';
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
    await tester.pumpAndSettle();
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
    // The shared inbox home, recognised by its one main action.
    expect(find.byTooltip('Add contact'), findsOneWidget);
    expect(find.text('Choose business'), findsNothing);
    api.onUnauthorized!();
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byTooltip('Add contact'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      session.dispose();
    },
  );
  testWidgets('quick add saves from a sheet and opens the new chat', (
    tester,
  ) async {
    Object? saved;
    var duplicate = true;
    final api = fakeApi(
      (r, h) => answer(r, h, switch (r.path) {
        'auth/login' => {'status': 'authenticated', 'token': 'token'},
        'me' => {'id': 1, 'bound_waba_user_id': 5},
        'config' => {'inbox': {}, 'capabilities': {}},
        'inbox/contacts' => <dynamic>[],
        'inbox/contact/new' when duplicate => {
          'success': false,
          'message': 'Validation failed',
          'errors': {
            'phone': ['The phone number already exists.'],
          },
        },
        'inbox/contact/new' => {
          'success': true,
          'data': {'id': 44, 'wa_id': '919811100077', 'profile_name': 'Ananya'},
        },
        'inbox/messages' => {
          'success': true,
          'data': <dynamic>[],
          'meta': {'has_more': false},
        },
        _ => {'success': true},
      }),
    );
    api.dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (r, h) {
          if (r.path == 'inbox/contact/new') saved = r.data;
          h.next(r);
        },
      ),
    );
    final session = MobileSession(api, MemoryStore());
    await tester.pumpWidget(MobileApplication(session: session));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add contact'));
    await tester.pumpAndSettle();
    // A sheet over the inbox, not a new page.
    expect(find.byType(QuickAddContact), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(QuickAddContact),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'Ananya');
    await tester.enterText(fields.at(1), '+91');
    await tester.enterText(fields.at(2), '98111 00077');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('The phone number already exists.'), findsOneWidget);
    expect(find.byType(QuickAddContact), findsOneWidget);

    duplicate = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, {'name': 'Ananya', 'phone': '9811100077', 'country': '91'});
    expect(find.byType(QuickAddContact), findsNothing);
    expect(find.byType(LiveChat), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });
  testWidgets('a sent message stays where it is when the server confirms it', (
    tester,
  ) async {
    final held = <(RequestOptions, RequestInterceptorHandler)>[];
    final earlier = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 1))
        .toIso8601String();
    final api = fakeApi((r, h) {
      if (r.path == 'inbox/send') {
        held.add((r, h));
        return;
      }
      answer(r, h, switch (r.path) {
        'inbox/messages' => {
          'success': true,
          'data': [
            {
              'id': 1,
              'type': 2,
              'message_body': 'Hi, is my order ready?',
              'message_type': 'text',
              'created_at': earlier,
            },
          ],
          'meta': {'has_more': false},
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
        _ => {'success': true},
      });
    });
    final session = MobileSession(api, MemoryStore());
    api.token = 'test';
    api.wabaId = 7;
    session.user = {'id': 1, 'name': 'Renav'};
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
    await tester.enterText(find.byType(TextField), 'Yes, it ships today');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    final text = find.textContaining('Yes, it ships today', findRichText: true);
    final sending = tester.getRect(text);
    final (request, handler) = held.single;
    answer(request, handler, {
      'success': true,
      'sent_message': {
        'id': 9,
        'type': 1,
        'message_type': 'text',
        'message_body': 'Yes, it ships today',
        'message_status': 1,
        'sender_name': 'Renav',
        'temp_message_id': (request.data as Map)['temp_message_id'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    });
    await tester.pump();
    expect(tester.getRect(text), sending);
    await tester.pumpAndSettle();
    expect(tester.getRect(text), sending);
    expect(find.text('Accepted · syncing'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });
}
