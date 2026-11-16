import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/device_identity.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

/// Sign-in tells the server which phone it is, for the sign-in history.
void main() {
  tearDown(forgetDeviceIdentity);

  test('the phone describes itself, and its version reads as on Play', () {
    const phone = DeviceIdentity(
      model: 'Google Pixel 9',
      os: 'Android 16',
      version: '1.0.0',
      build: '70',
    );
    expect(phone.appVersion, '1.0.0 (70)');
    expect(
      phone.userAgent,
      'TelvoxChat/1.0.0 (70; Android 16; Google Pixel 9)',
    );
    expect(phone.loginFields, {
      'device_model': 'Google Pixel 9',
      'os_version': 'Android 16',
      'app_version': '1.0.0 (70)',
    });
    expect(const DeviceIdentity().loginFields, isEmpty);
    expect(const DeviceIdentity().userAgent, 'TelvoxChat/0');
  });

  test('sign-in sends the model, system and app version, and names the app '
      'on every request', () async {
    describeDevice = () async => const DeviceIdentity(
      model: 'Samsung SM-S918B',
      os: 'Android 15',
      version: '1.0.0',
      build: '71',
    );
    final sent = <RequestOptions>[];
    final api = fakeApi((r, h) {
      sent.add(r);
      answer(r, h, switch (r.path) {
        'auth/login' => {'status': 'authenticated', 'token': 'token'},
        'me' => {'id': 1, 'bound_waba_user_id': 5},
        'config' => {'inbox': {}, 'capabilities': {}},
        _ => {},
      });
    });
    final session = MobileSession(api, MemoryStore());
    await session.login('person@example.test', 'password');

    final login = sent.firstWhere((r) => r.path == 'auth/login');
    expect(login.data, containsPair('device_model', 'Samsung SM-S918B'));
    expect(login.data, containsPair('device_name', 'Samsung SM-S918B'));
    expect(login.data, containsPair('os_version', 'Android 15'));
    expect(login.data, containsPair('app_version', '1.0.0 (71)'));
    expect(
      sent.last.headers['User-Agent'],
      'TelvoxChat/1.0.0 (71; Android 15; Samsung SM-S918B)',
    );
    session.dispose();
  });

  test('a phone that cannot say still signs in', () async {
    describeDevice = () async => const DeviceIdentity();
    final sent = <RequestOptions>[];
    final api = fakeApi((r, h) {
      sent.add(r);
      answer(r, h, switch (r.path) {
        'auth/login' => {'status': 'authenticated', 'token': 'token'},
        'me' => {'id': 1, 'bound_waba_user_id': 5},
        'config' => {'inbox': {}, 'capabilities': {}},
        _ => {},
      });
    });
    final session = MobileSession(api, MemoryStore());
    await session.login('person@example.test', 'password');
    final login = sent.firstWhere((r) => r.path == 'auth/login');
    expect(login.data, isNot(contains('device_model')));
    expect(login.data['device_name'], isNotEmpty);
    session.dispose();
  });
}
