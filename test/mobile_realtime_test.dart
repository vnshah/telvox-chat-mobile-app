import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/realtime.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_test.dart' show details, sampleMessages;

class FakeSocket implements RealtimeSocket {
  final incoming = StreamController<dynamic>();
  final sent = <Json>[];
  bool closed = false;
  @override
  Stream<dynamic> get messages => incoming.stream;
  @override
  void send(String data) => sent.add(object(jsonDecode(data)));
  @override
  Future<void> close() async {
    closed = true;
    unawaited(incoming.close());
  }

  void server(String event, Object data, {String? channel}) => incoming.add(
    jsonEncode({
      'event': event,
      'data': data is String ? data : jsonEncode(data),
      'channel': ?channel,
    }),
  );

  void established() => server('pusher:connection_established', {
    'socket_id': '123.456',
    'activity_timeout': 120,
  });
}

const realtimeConfig = {
  'realtime': {
    'driver': 'reverb',
    'key': 'app-key',
    'host': 'ws.example.test',
    'port': 443,
    'scheme': 'https',
    'auth_endpoint': 'https://dev.example.test/api/mobile/v1/broadcasting/auth',
    'device_channel': 'private-mobile.device.9',
  },
  'inbox': {
    'waba_user': {'id': 7, 'phone': '919426555485'},
    'auth_user': {'id': 1},
  },
};

void main() {
  testWidgets('connects, authorises private channels and dispatches events', (
    tester,
  ) async {
    final sockets = <FakeSocket>[];
    final uris = <Uri>[];
    final auths = <Json>[];
    final authHeaders = <Map<String, dynamic>>[];
    final api =
        fakeApi((r, h) {
            if (r.path.endsWith('broadcasting/auth')) {
              auths.add(object(r.data));
              authHeaders.add(r.headers);
              return answer(r, h, {'auth': 'app-key:signature'});
            }
            answer(r, h, {'success': true});
          })
          ..token = 'token'
          ..wabaId = 7;
    final session = MobileSession(
      api,
      MemoryStore(),
      realtimeConnector: (uri) async {
        uris.add(uri);
        final socket = FakeSocket();
        sockets.add(socket);
        return socket;
      },
    )..config = realtimeConfig;
    final events = <(String, Object?)>[];
    var resyncs = 0;
    final sub = session.realtime.listen(
      'receive.message.7.919999999999',
      (event, data) => events.add((event, data)),
      onResync: () => resyncs++,
    );
    session.realtime.start();
    await tester.pump();
    expect(
      uris.single.toString(),
      startsWith('wss://ws.example.test:443/app/app-key?'),
    );
    expect(session.realtime.state, RealtimeState.connecting);

    sockets.last.established();
    await tester.pumpAndSettle();
    expect(session.realtime.state, RealtimeState.connected);
    expect(auths.single, {
      'socket_id': '123.456',
      'channel_name': 'private-receive.message.7.919999999999',
    });
    expect(authHeaders.single['Authorization'], 'Bearer token');
    expect(authHeaders.single['X-Waba-User-Id'], '7');
    expect(sockets.last.sent.last, {
      'event': 'pusher:subscribe',
      'data': {
        'channel': 'private-receive.message.7.919999999999',
        'auth': 'app-key:signature',
      },
    });
    sockets.last.server(
      'pusher_internal:subscription_succeeded',
      {},
      channel: 'private-receive.message.7.919999999999',
    );
    sockets.last.server('receive.message', {
      'id': 41,
    }, channel: 'private-receive.message.7.919999999999');
    sockets.last.server('pusher:ping', {});
    await tester.pumpAndSettle();
    expect(events.single.$1, 'receive.message');
    expect(object(events.single.$2)['id'], 41);
    expect(sockets.last.sent.last['event'], 'pusher:pong');
    expect(resyncs, 0, reason: 'the first join is not a resync');

    // A dropped socket reconnects with backoff and rejoins: that is a resync.
    await sockets.last.incoming.close();
    await tester.pump();
    expect(session.realtime.state, RealtimeState.reconnecting);
    await tester.pump(const Duration(seconds: 1));
    expect(sockets, hasLength(2));
    sockets.last.established();
    await tester.pumpAndSettle();
    sockets.last.server(
      'pusher_internal:subscription_succeeded',
      {},
      channel: 'private-receive.message.7.919999999999',
    );
    await tester.pump();
    expect(resyncs, 1);

    sub.cancel();
    expect(sockets.last.sent.last, {
      'event': 'pusher:unsubscribe',
      'data': {'channel': 'private-receive.message.7.919999999999'},
    });
    session.realtime.stop();
    expect(session.realtime.state, RealtimeState.off);
    session.dispose();
  });

  testWidgets('without websocket settings the client stays off', (
    tester,
  ) async {
    var connects = 0;
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {})),
      MemoryStore(),
      realtimeConnector: (_) async {
        connects++;
        return FakeSocket();
      },
    )..config = {};
    expect(session.realtime.available, isFalse);
    session.realtime.start();
    await tester.pump();
    expect(connects, 0);
    expect(session.realtime.state, RealtimeState.off);
    session.dispose();
  });

  testWidgets('an incoming-message event updates the open chat at once', (
    tester,
  ) async {
    final socket = FakeSocket();
    var history = <Json>[...sampleMessages];
    var messageRequests = 0;
    final api = fakeApi((r, h) {
      if (r.path.endsWith('broadcasting/auth')) {
        return answer(r, h, {'auth': 'app-key:signature'});
      }
      if (r.path == 'inbox/messages') messageRequests++;
      answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {'success': true, 'data': details()},
        'inbox/messages' => {
          'success': true,
          'data': history,
          'meta': {'has_more': false, 'sync_from': '2026-10-29T10:01:00Z'},
        },
        _ => {'success': true},
      });
    })..wabaId = 7;
    final session =
        MobileSession(
            api,
            MemoryStore(),
            realtimeConnector: (_) async => socket,
          )
          ..user = {'id': 1}
          ..config = realtimeConfig;
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: LiveChat(session, {
          'id': 12,
          'profile_name': 'Alex',
          'wa_id': '919999999999',
        }),
      ),
    );
    session.realtime.start();
    await tester.pumpAndSettle();
    socket.established();
    await tester.pumpAndSettle();
    final subscribed = socket.sent
        .where((m) => m['event'] == 'pusher:subscribe')
        .map((m) => object(m['data'])['channel'])
        .toSet();
    expect(subscribed, {
      'private-send.message.7.919999999999',
      'private-receive.message.7.919999999999',
      'private-receive.reaction.7.919999999999',
      'private-change.log.7.919999999999',
    });

    // No timer-driven requests while idle.
    final before = messageRequests;
    await tester.pump(const Duration(seconds: 30));
    expect(messageRequests, before);

    history = [
      {
        'id': 99,
        'type': 2,
        'message_type': 'text',
        'message_body': 'Is my order ready?',
        'created_at': '2026-10-29T10:05:00Z',
      },
    ];
    socket.server('receive.message', {
      'id': 99,
    }, channel: 'private-receive.message.7.919999999999');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(messageRequests, before + 1);
    expect(
      find.textContaining('Is my order ready?', findRichText: true),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    session.realtime.stop();
    await tester.pump();
    session.dispose();
  });
}
