import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/firebase_settings.dart';

/// The Firebase project comes from the server's .env, is kept on the phone,
/// and falls back to the build's own values only until the server answers.
void main() {
  late File kept;
  final answer = {
    'firebase': {
      'project_id': 'telvox-chat',
      'messaging_sender_id': '123456789012',
      'android': {
        'api_key': 'android-key',
        'app_id': '1:123456789012:android:abc',
      },
      'ios': null,
    },
  };

  setUp(() {
    kept = File(
      '${Directory.systemTemp.path}/firebase-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    FirebaseSettings.file = () async => kept;
    FirebaseSettings.current = null;
  });

  tearDown(() {
    if (kept.existsSync()) kept.deleteSync();
  });

  test("reads this platform's app from the server's answer", () {
    final android = FirebaseSettings.fromServer(answer, ios: false)!;
    expect(android.projectId, 'telvox-chat');
    expect(android.senderId, '123456789012');
    expect(android.appId, '1:123456789012:android:abc');
    // No iOS app set on the server: no settings for an iPhone.
    expect(FirebaseSettings.fromServer(answer, ios: true), isNull);
    // A server with no project set, or an older one without the endpoint.
    expect(FirebaseSettings.fromServer({'firebase': null}), isNull);
    expect(FirebaseSettings.fromServer('<html>'), isNull);
  });

  test('keeps the answer, and the next start uses it', () async {
    FirebaseSettings.fetch = (_) async => answer;
    await FirebaseSettings.refresh('https://chat.example.test');
    expect(kept.existsSync(), isTrue);
    // No Firebase project before: this run starts with the answer at once.
    expect(FirebaseSettings.current?.projectId, 'telvox-chat');

    FirebaseSettings.current = null;
    final next = await FirebaseSettings.load();
    expect(next?.appId, '1:123456789012:android:abc');
  });

  test('offline, the kept copy stands', () async {
    FirebaseSettings.fetch = (_) async => answer;
    await FirebaseSettings.refresh('https://chat.example.test');
    FirebaseSettings.fetch = (_) async => throw const SocketException('down');
    await FirebaseSettings.refresh('https://chat.example.test');
    FirebaseSettings.current = null;
    expect((await FirebaseSettings.load())?.projectId, 'telvox-chat');
  });

  test('with no copy and no build values, there is no project', () async {
    // Tests are built without Firebase defines.
    expect(await FirebaseSettings.load(), isNull);
  });
}
