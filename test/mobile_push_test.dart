import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/push.dart';
import 'package:telvox_chat_mobile_app/mobile/screens.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_test.dart' show details, sampleMessages;

class FakePush implements PushTransport {
  bool allowed = true;
  String? current = 'token-1';
  final refresh = StreamController<String>.broadcast();
  final arrivals = StreamController<PushMessage>.broadcast();
  final taps = StreamController<PushMessage>.broadcast();
  final shown = <PushMessage>[];
  PushMessage? launch;
  bool forgotten = false;
  @override
  Future<bool> start() async => allowed;
  @override
  Future<String?> token() async => current;
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get foreground => arrivals.stream;
  @override
  Stream<PushMessage> get opened => taps.stream;
  @override
  Future<PushMessage?> launchMessage() async => launch;
  @override
  Future<void> show(PushMessage message) async => shown.add(message);
  @override
  Future<void> forget() async => forgotten = true;
}

MobileSession pushSession(
  FakePush push,
  void Function(RequestOptions, RequestInterceptorHandler) handler,
) => MobileSession(fakeApi(handler), MemoryStore(), pushTransport: push)
  ..api.token = 'token'
  ..api.wabaId = 7
  ..user = {'id': 1}
  ..config = {};

void main() {
  test('registers the token once and again when Firebase rotates it', () async {
    final push = FakePush();
    final bodies = <Object?>[];
    final session = pushSession(push, (r, h) {
      if (r.path == 'me/push-token') {
        expect(r.method, 'PUT');
        bodies.add(r.data);
      }
      answer(r, h, {'status': 'ok'});
    });
    await session.push.enable();
    await session.push.enable();
    expect(bodies, [
      {'token': 'token-1', 'provider': 'fcm'},
    ]);
    push.refresh.add('token-2');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bodies.last, {'token': 'token-2', 'provider': 'fcm'});
    session.dispose();
  });

  test('denied permission registers nothing', () async {
    final push = FakePush()..allowed = false;
    var registered = 0;
    final session = pushSession(push, (r, h) {
      if (r.path == 'me/push-token') registered++;
      answer(r, h, {});
    });
    await session.push.enable();
    expect(registered, 0);
    session.dispose();
  });

  test('foreground pushes skip the conversation already on screen', () async {
    final push = FakePush();
    final session = pushSession(push, (r, h) => answer(r, h, {}));
    await session.push.enable();
    session.visibleContacts.add('contact:12');
    push.arrivals
      ..add(const PushMessage(title: 'Alex', data: {'contact_id': '12'}))
      // Same customer, but the message belongs to their open ticket.
      ..add(
        const PushMessage(
          title: 'Alex · #42',
          data: {'contact_id': '12', 'ticket_id': '42'},
        ),
      )
      ..add(const PushMessage(title: 'Sam', data: {'contact_id': '13'}));
    await Future<void>.delayed(Duration.zero);
    expect(push.shown.map((m) => m.title), ['Sam']);
    session.dispose();
  });

  test('signing out forgets the local token', () async {
    final push = FakePush();
    final session = pushSession(push, (r, h) => answer(r, h, {}));
    await session.push.enable();
    await session.logout();
    expect(push.forgotten, isTrue);
    session.dispose();
  });

  testWidgets('tapping a message notification opens that chat', (tester) async {
    final push = FakePush();
    final session = pushSession(
      push,
      (r, h) => answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {
          'success': true,
          'data': {
            ...details(),
            'contact': {
              ...object(details()['contact']),
              'profile_name': 'Alex Morgan',
              'wa_id': '919999999999',
            },
          },
        },
        'inbox/messages' => {
          'success': true,
          'data': sampleMessages,
          'meta': {'has_more': false},
        },
        'inbox/contacts' => <Object>[],
        _ => {'success': true},
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: LiveHome(session),
      ),
    );
    await tester.pumpAndSettle();
    push.taps.add(
      const PushMessage(
        data: {'type': 'message', 'waba_user_id': '7', 'contact_id': '12'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LiveChat), findsOneWidget);
    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(session.pendingOpen, isNull);
    expect(session.visibleConversation, 'contact:12');
    expect(session.visibleContacts, {'contact:12'});
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });
}
