import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

/// iPhone calls ring a closed app through Apple's VoIP push: the app hands
/// the server the VoIP token iOS gives it, once per token.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_callkit_incoming');
  var voipToken =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
  late List<RequestOptions> sent;

  MobileSession signedIn() {
    sent = [];
    return MobileSession(
        fakeApi((r, h) {
          sent.add(r);
          answer(r, h, {'status': 'ok'});
        }),
        MemoryStore(),
      )
      ..api.token = 'token'
      ..user = {'id': 1};
  }

  Iterable<RequestOptions> registrations() =>
      sent.where((r) => r.path == 'me/voip-token');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getDevicePushTokenVoIP') return voipToken;
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'an iPhone sends its VoIP token once, and again when it changes',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final session = signedIn();
      await session.callPush.registerVoip();
      await session.callPush.registerVoip();
      expect(registrations(), hasLength(1));
      expect(registrations().single.method, 'PUT');
      expect(registrations().single.data, {'token': voipToken});

      voipToken = 'ffff${voipToken.substring(4)}';
      await session.callPush.registerVoip();
      expect(registrations(), hasLength(2));

      // A different account signing in on this phone sends it afresh.
      session.callPush.forgetVoip();
      await session.callPush.registerVoip();
      expect(registrations(), hasLength(3));
      session.dispose();
    },
  );

  test(
    'nothing is sent before sign-in, without a token, or on Android',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final signedOut = MobileSession(
        fakeApi((r, h) {
          sent.add(r);
          answer(r, h, {});
        }),
        MemoryStore(),
      );
      sent = [];
      await signedOut.callPush.registerVoip();
      expect(registrations(), isEmpty);
      signedOut.dispose();

      final session = signedIn();
      final saved = voipToken;
      voipToken = '';
      await session.callPush.registerVoip();
      expect(registrations(), isEmpty);
      voipToken = saved;

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await session.callPush.registerVoip();
      expect(registrations(), isEmpty);
      session.dispose();
    },
  );
}
