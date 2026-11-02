import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/call_push.dart';
import 'package:telvox_chat_mobile_app/mobile/calls.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_realtime_test.dart' show FakeSocket, realtimeConfig;

/// WebRTC without a microphone: records what the call asked of it.
class FakeCallMedia implements CallMedia {
  final calls = <String>[];
  final _connected = ValueNotifier(false);
  String? remote;
  @override
  ValueListenable<bool> get connected => _connected;
  void connect() => _connected.value = true;
  @override
  Future<String> offer() async {
    calls.add('offer');
    return 'v=0\r\nlocal-offer\r\n';
  }

  @override
  Future<String> answer(String offer) async {
    calls.add('answer:$offer');
    return 'v=0\r\nlocal-answer\r\n';
  }

  @override
  Future<void> remoteAnswer(String sdp) async => remote = sdp;
  @override
  Future<void> mute(bool muted) async => calls.add('mute:$muted');
  @override
  Future<void> speaker(bool on) async => calls.add('speaker:$on');
  @override
  Future<void> close() async => calls.add('close');
}

typedef Harness = ({
  MobileSession session,
  FakeSocket socket,
  FakeCallMedia media,
  List<RequestOptions> posts,
});

Future<Harness> harness(WidgetTester tester) async {
  final socket = FakeSocket();
  final media = FakeCallMedia();
  final posts = <RequestOptions>[];
  final api = fakeApi((r, h) {
    if (r.path.endsWith('broadcasting/auth')) {
      return answer(r, h, {'auth': 'app-key:signature'});
    }
    if (r.path.startsWith('inbox/calls/')) posts.add(r);
    if (r.path == 'inbox/calls/offer' &&
        (r.data as Map)['call_id'] == 'wacid.GONE') {
      return answer(r, h, {
        'success': false,
        'message': 'This call is no longer ringing.',
      }, 410);
    }
    answer(r, h, switch (r.path) {
      'inbox/calls/offer' => {
        'success': true,
        'data': {
          'call_id': 'wacid.PUSH',
          'sdp': 'v=0\r\npushed-offer\r\n',
          'contact': {'id': 12, 'profile_name': 'Rahil Patel'},
        },
      },
      'inbox/calls/initiate' => {
        'success': true,
        'data': {
          'calls': [
            {'id': 'wacid.OUT'},
          ],
        },
      },
      _ => {'success': true},
    });
  })..wabaId = 7;
  final session =
      MobileSession(
          api,
          MemoryStore(),
          realtimeConnector: (_) async => socket,
          callMedia: () => media,
        )
        ..user = {
          'id': 1,
          'device': {'id': 12},
        }
        ..config = {
          ...realtimeConfig,
          'inbox': {
            'waba_user': {
              'id': 7,
              'name': 'Telvox Sales',
              'allow_voice_calling': true,
              'call_status_and_working_hours': true,
            },
          },
        };
  session.calls.attach();
  session.realtime.start();
  await tester.pump();
  socket.established();
  await tester.pump();
  return (session: session, socket: socket, media: media, posts: posts);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const permitted = {
  'id': 12,
  'profile_name': 'Rahil Patel',
  'wa_id': '919099801380',
  'call_permission': 'accept',
  'call_permission_permanent': true,
};

void main() {
  test('the call button follows the number, call hours and permission', () {
    Json config({bool calling = true, bool open = true}) => {
      'inbox': {
        'waba_user': {
          'allow_voice_calling': calling,
          'call_status_and_working_hours': open,
        },
      },
    };
    expect(callEligibility(config(calling: false), permitted).shown, false);
    expect(callEligibility(config(), permitted).blocked, isNull);
    expect(
      callEligibility(config(open: false), permitted).blocked,
      contains('call hours'),
    );
    expect(
      callEligibility(config(), {'id': 12}).blocked,
      contains('call permission'),
    );
    // Permission with an end date counts until it passes.
    expect(
      callEligibility(config(), {
        'call_permission': 'accept',
        'call_permission_expiration': DateTime.now()
            .add(const Duration(days: 2))
            .toUtc()
            .toIso8601String(),
      }).blocked,
      isNull,
    );
    expect(
      callEligibility(config(), {
        'call_permission': 'accept',
        'call_permission_expiration': '2020-01-01T00:00:00Z',
      }).blocked,
      isNotNull,
    );
  });

  test('an SDP arrives quoted or escaped and leaves as CRLF lines', () {
    expect(
      cleanSdp(r'"v=0\r\no=- 1 1 IN IP4 0.0.0.0"'),
      'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n',
    );
    expect(cleanSdp('v=0\na=x\n'), 'v=0\r\na=x\r\n');
  });

  testWidgets('a call we start rings, connects on the answer and hangs up', (
    tester,
  ) async {
    final h = await harness(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: CallButton(session: h.session, contact: permitted),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Voice call'));
    await settle(tester);
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('Rahil Patel'), findsOneWidget);
    final initiate = h.posts.singleWhere(
      (r) => r.path == 'inbox/calls/initiate',
    );
    expect(initiate.data, {'contact_id': 12, 'sdp': 'v=0\r\nlocal-offer\r\n'});
    expect(h.session.calls.state, CallState.ringing);
    expect(find.text('Ringing…'), findsOneWidget);

    // Another agent's call on the same number is not ours.
    h.socket.server('calls', {
      'call_id': 'wacid.OTHER',
      'event': 'connect',
      'direction': 'BUSINESS_INITIATED',
      'sdp': 'v=0\r\nnot-ours\r\n',
    }, channel: 'private-calls.7');
    await settle(tester);
    expect(h.media.remote, isNull);

    h.socket.server('calls', {
      'call_id': 'wacid.OUT',
      'event': 'connect',
      'direction': 'BUSINESS_INITIATED',
      'sdp': 'v=0\r\ncustomer-answer\r\n',
    }, channel: 'private-calls.7');
    await settle(tester);
    expect(h.media.remote, 'v=0\r\ncustomer-answer\r\n');
    expect(h.session.calls.state, CallState.active);
    expect(find.text('00:00'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Mute'));
    await settle(tester);
    expect(h.media.calls, contains('mute:true'));

    await tester.tap(find.bySemanticsLabel('End call'));
    await settle(tester);
    expect(
      h.posts.where((r) => r.path == 'inbox/calls/terminate').single.data,
      containsPair('call_id', 'wacid.OUT'),
    );
    expect(h.media.calls.last, 'close');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(CallScreen), findsNothing);
    h.session.realtime.stop();
    await tester.pump();
    h.session.dispose();
  });

  testWidgets(
    'a customer calling rings this phone only, and answering connects it',
    (tester) async {
      final h = await harness(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: Builder(
            builder: (context) {
              h.session.calls.addListener(() {
                if (h.session.calls.state == CallState.incoming) {
                  showCallScreen(context, h.session.calls);
                }
              });
              return const Scaffold();
            },
          ),
        ),
      );
      Json ringing(String target) => {
        'event_type': 'call_ringing',
        'call_id': 'wacid.IN',
        'contact': {
          'id': 12,
          'profile_name': 'Rahil Patel',
          'phone': '919099801380',
        },
        'sdp': 'v=0\r\ncustomer-offer\r\n',
        'expires_at': DateTime.now()
            .add(const Duration(seconds: 25))
            .toUtc()
            .toIso8601String(),
        'target_client_session_id': target,
      };
      // Offered to the agent's browser tab: not this phone.
      h.socket.server(
        'call_ringing',
        ringing('tab-1'),
        channel: 'private-App.Models.User.1',
      );
      await settle(tester);
      expect(h.session.calls.state, CallState.idle);

      h.socket.server(
        'call_ringing',
        ringing('mobile:12'),
        channel: 'private-App.Models.User.1',
      );
      await settle(tester);
      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('Incoming voice call'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Accept'));
      await settle(tester);
      expect(h.media.calls, contains('answer:v=0\r\ncustomer-offer\r\n'));
      final accept = h.posts.singleWhere((r) => r.path == 'inbox/calls/accept');
      expect(accept.data, {
        'call_id': 'wacid.IN',
        'sdp': 'v=0\r\nlocal-answer\r\n',
        'contact_id': 12,
      });
      // Connected is only reported once audio flows.
      expect(h.posts.where((r) => r.path == 'inbox/calls/connected'), isEmpty);
      expect(find.text('Connecting…'), findsOneWidget);
      h.media.connect();
      await settle(tester);
      expect(
        h.posts.singleWhere((r) => r.path == 'inbox/calls/connected').data,
        {'call_id': 'wacid.IN'},
      );
      expect(h.session.calls.state, CallState.active);

      // The customer hangs up.
      h.socket.server('call_ended', {
        'call_id': 'wacid.IN',
      }, channel: 'private-App.Models.User.1');
      await settle(tester);
      expect(find.text('Call ended'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(CallScreen), findsNothing);
      h.session.realtime.stop();
      await tester.pump();
      h.session.dispose();
    },
  );

  testWidgets('another agent answering stops this phone ringing', (
    tester,
  ) async {
    final h = await harness(tester);
    h.socket.server('call_ringing', {
      'call_id': 'wacid.IN2',
      'contact': {'id': 12},
      'sdp': 'v=0\r\noffer\r\n',
      'target_client_session_id': 'mobile:12',
    }, channel: 'private-App.Models.User.1');
    await settle(tester);
    expect(h.session.calls.state, CallState.incoming);
    h.socket.server('call_answered', {
      'call_id': 'wacid.IN2',
      'answered_client_session_id': 'tab-9',
    }, channel: 'private-App.Models.User.1');
    await settle(tester);
    expect(h.session.calls.state, CallState.ended);
    expect(h.session.calls.notice, 'Answered by another agent');
    expect(h.posts.where((r) => r.path == 'inbox/calls/accept'), isEmpty);
    await tester.pump(const Duration(seconds: 2));
    h.session.realtime.stop();
    await tester.pump();
    h.session.dispose();
  });

  testWidgets(
    'the phone tells the server it can ring, and stops when it leaves',
    (tester) async {
      final h = await harness(tester);
      unawaited(h.session.calls.ready());
      await settle(tester);
      unawaited(h.session.calls.gone());
      await settle(tester);
      expect(
        [for (final r in h.posts) '${r.method} ${r.path}'],
        ['POST inbox/calls/ready', 'DELETE inbox/calls/ready'],
      );
      h.session.realtime.stop();
      await tester.pump();
      h.session.dispose();
    },
  );

  test(
    'a call id always maps to the same UUID, as the system call UI needs',
    () {
      final uuid = callUuid('wacid.HBgMOTE5MDk5ODAxMzgwFQIAEhggQ0Y');
      expect(uuid, callUuid('wacid.HBgMOTE5MDk5ODAxMzgwFQIAEhggQ0Y'));
      expect(uuid, isNot(callUuid('wacid.other')));
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-a[0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(uuid),
        true,
      );
    },
  );

  testWidgets(
    'accepting a call that woke the phone fetches the offer and answers it',
    (tester) async {
      final h = await harness(tester);
      unawaited(
        h.session.calls.acceptPushed({
          'type': 'call',
          'call_id': 'wacid.PUSH',
          'waba_user_id': '7',
          'contact_id': '12',
          'contact_name': 'Rahil Patel',
        }),
      );
      await settle(tester);
      expect(h.session.calls.state, CallState.connecting);
      expect(h.posts.singleWhere((r) => r.path == 'inbox/calls/offer').data, {
        'call_id': 'wacid.PUSH',
      });
      expect(h.media.calls, contains('answer:v=0\r\npushed-offer\r\n'));
      expect(
        h.posts.singleWhere((r) => r.path == 'inbox/calls/accept').data,
        containsPair('call_id', 'wacid.PUSH'),
      );
      h.media.connect();
      await settle(tester);
      expect(h.session.calls.state, CallState.active);
      expect(h.session.calls.contact['profile_name'], 'Rahil Patel');
      h.session.realtime.stop();
      await tester.pump();
      h.session.dispose();
    },
  );

  testWidgets('a call answered elsewhere before the phone woke says so', (
    tester,
  ) async {
    final h = await harness(tester);
    unawaited(h.session.calls.acceptPushed({'call_id': 'wacid.GONE'}));
    await settle(tester);
    expect(h.session.calls.state, CallState.ended);
    expect(h.session.calls.notice, 'This call is no longer ringing');
    expect(h.posts.where((r) => r.path == 'inbox/calls/accept'), isEmpty);
    await tester.pump(const Duration(seconds: 2));
    h.session.realtime.stop();
    await tester.pump();
    h.session.dispose();
  });

  testWidgets('declining on the system screen gives the call back', (
    tester,
  ) async {
    final h = await harness(tester);
    unawaited(h.session.calls.declinePushed('wacid.NO'));
    await settle(tester);
    expect(h.posts.singleWhere((r) => r.path == 'inbox/calls/decline').data, {
      'call_id': 'wacid.NO',
    });
    h.session.realtime.stop();
    await tester.pump();
    h.session.dispose();
  });
}
