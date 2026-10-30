import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';

class MemoryStore implements SessionStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

MobileApi fakeApi(
  void Function(RequestOptions, RequestInterceptorHandler) handler,
) {
  final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: handler));
  return MobileApi(dio: dio, baseUrl: 'https://dev.example.test');
}

void answer(
  RequestOptions request,
  RequestInterceptorHandler handler,
  dynamic data, [
  int status = 200,
]) {
  handler.resolve(
    Response(requestOptions: request, data: data, statusCode: status),
  );
}

void main() {
  test('single base URL supports origin or full API prefix', () {
    expect(
      MobileApi(baseUrl: 'https://example.test/').dio.options.baseUrl,
      'https://example.test/api/mobile/v1/',
    );
    expect(
      MobileApi(baseUrl: 'https://example.test/api/mobile/v1/')
          .dio
          .options
          .baseUrl,
      'https://example.test/api/mobile/v1/',
    );
  });
  test('requests attach bearer and current number, auth does not', () async {
    final requests = <RequestOptions>[];
    final api = fakeApi((r, h) {
      requests.add(r);
      answer(r, h, {'success': true});
    });
    api.token = 'test-token';
    api.wabaId = 7;
    await api.get('config');
    await api.request('auth/login', authenticated: false, method: 'POST');
    expect(requests.first.headers['Authorization'], 'Bearer test-token');
    expect(requests.first.headers['X-Waba-User-Id'], '7');
    expect(requests.last.headers.containsKey('Authorization'), false);
    expect(requests.last.headers.containsKey('X-Waba-User-Id'), false);
  });
  test(
    'HTTP 200 business failure and template status:false are errors',
    () async {
      for (final body in [
        {'success': false, 'message': 'Window closed'},
        {'status': false, 'message': 'Not allowed'},
      ]) {
        final api = fakeApi((r, h) => answer(r, h, body));
        await expectLater(api.post('inbox/send'), throwsA(isA<ApiFailure>()));
      }
    },
  );
  test('expired messaging window does not expire the login', () async {
    final api = fakeApi(
      (r, h) => answer(r, h, {
        'success': false,
        'message': 'Your user session is expired.',
      }),
    );
    api.token = 'test-token';
    var expired = false;
    api.onUnauthorized = () => expired = true;
    await expectLater(
      api.post('inbox/send'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'message',
          contains('contact’s messaging window'),
        ),
      ),
    );
    expect(expired, false);
    expect(api.token, 'test-token');
  });
  test(
    'provider failures expose the useful reason instead of generic error',
    () async {
      final api = fakeApi(
        (r, h) => answer(r, h, {
          'status': false,
          'message': 'Something went wrong',
          'error': {
            'error_data': {'details': 'Template does not exist in en'},
          },
        }, 400),
      );
      await expectLater(
        api.post('inbox/send-template-by-contact'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            'Template does not exist in en',
          ),
        ),
      );
    },
  );
  test('401 clears session but forbidden does not', () async {
    var status = 403;
    final store = MemoryStore();
    final api = fakeApi((r, h) => answer(r, h, {'message': 'Denied'}, status));
    final session = MobileSession(api, store);
    api.token = 'test';
    session.user = {'id': 1};
    await expectLater(api.get('me'), throwsA(isA<ApiFailure>()));
    expect(session.signedIn, true);
    status = 401;
    await expectLater(api.get('me'), throwsA(isA<ApiFailure>()));
    expect(session.signedIn, false);
    session.dispose();
  });
  test('retry preserves message key and exact payload after timeout', () async {
    final requests = <RequestOptions>[];
    final api = fakeApi((r, h) {
      requests.add(r);
      if (requests.length == 1) {
        h.reject(
          DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          ),
        );
      } else {
        answer(r, h, {
          'success': true,
          'sent_message': {'id': 9},
        });
      }
    });
    final repo = InboxRepository(api),
        message = PendingSend({'body': 'Hello', 'contact_id': 1});
    await expectLater(
      repo.send(message),
      throwsA(isA<ApiFailure>().having((e) => e.uncertain, 'uncertain', true)),
    );
    await repo.send(message);
    expect(
      requests[0].headers['Idempotency-Key'],
      requests[1].headers['Idempotency-Key'],
    );
    expect(requests[0].data, requests[1].data);
  });
  test('merge replaces optimistic and deduplicates inclusive updates', () {
    final result = mergeMessages(
      [
        ApiMessage({
          'id': 'tmp',
          'temp_message_id': 'abc',
          'created_at': '2026-01-01',
        }),
      ],
      [
        ApiMessage({
          'id': 1,
          'temp_message_id': 'abc',
          'message_status': 1,
          'created_at': '2026-01-01',
        }),
        ApiMessage({'id': 1, 'message_status': 3, 'created_at': '2026-01-01'}),
      ],
    );
    expect(result.length, 1);
    expect(result.single.status, 3);
  });
  test('2FA stores no password and reuses install id', () async {
    final requests = <RequestOptions>[];
    final store = MemoryStore();
    final api = fakeApi((r, h) {
      requests.add(r);
      answer(r, h, {
        'status': 'two_factor_required',
        'challenge_token': 'challenge',
        'default_method': 'totp',
      }, 202);
    });
    final session = MobileSession(api, store);
    await session.login('person@example.test', 'password');
    await session.login('person@example.test', 'password');
    expect(session.signedIn, false);
    expect(session.challenge?['challenge_token'], 'challenge');
    expect(
      requests.first.data['device_uuid'],
      requests.last.data['device_uuid'],
    );
    expect(jsonEncode(store.values).contains('password'), false);
    session.dispose();
  });
  test(
    'bound account skips business picker and persists scoped session',
    () async {
      final store = MemoryStore();
      final api = fakeApi((r, h) {
        answer(r, h, switch (r.path) {
          'auth/login' => {'status': 'authenticated', 'token': 'token'},
          'me' => {'id': 1, 'bound_waba_user_id': 5},
          'config' => {'inbox': {}, 'capabilities': {}},
          _ => {},
        });
      });
      final session = MobileSession(api, store);
      await session.login('person@example.test', 'password');
      expect(session.ready, true);
      expect(api.wabaId, 5);
      expect(store.values.keys, contains('session.dev.example.test'));
      session.dispose();
    },
  );
  test('India timestamp presentation converts zoned instants centrally', () {
    expect(const MobileClock().time('2026-10-29T10:00:00Z'), '15:30');
    expect(const MobileClock().time('2026-10-29 10:00:00'), '10:00');
    expect(const MobileClock().time(null), '');
  });
}
