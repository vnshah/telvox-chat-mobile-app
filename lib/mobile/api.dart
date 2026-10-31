import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config/app_config.dart';
import 'push.dart';
import 'realtime.dart';

typedef Json = Map<String, dynamic>;
Json object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> rows(Object? value) =>
    value is List ? value.map(object).toList() : [];
int? number(Object? value) => int.tryParse('$value');
Object? decoded(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

String newRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ApiFailure implements Exception {
  const ApiFailure(
    this.message, {
    this.code,
    this.httpStatus,
    this.uncertain = false,
  });
  final String message;
  final String? code;
  final int? httpStatus;
  final bool uncertain;
  @override
  String toString() => message;
}

abstract class SessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSessionStore implements SessionStore {
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: 'mobile.$key');
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: 'mobile.$key', value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: 'mobile.$key');
}

/// One API instance per session. No automatic retries on mutations.
class MobileApi {
  MobileApi({Dio? dio, String baseUrl = AppConfig.apiBaseUrl})
    : dio = dio ?? Dio() {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    this.dio.options = BaseOptions(
      baseUrl: base.endsWith('/api/mobile/v1')
          ? '$base/'
          : '$base/api/mobile/v1/',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
      followRedirects: false,
      validateStatus: (status) => status != null && status < 600,
    );
  }
  final Dio dio;
  String? token;
  int? wabaId;
  VoidCallback? onUnauthorized;
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    Json? query,
    bool authenticated = true,
    String? idempotencyKey,
    ProgressCallback? onSendProgress,
  }) async {
    final requestToken = token;
    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        onSendProgress: onSendProgress,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {
            if (authenticated && requestToken != null)
              'Authorization': 'Bearer $requestToken',
            if (authenticated && wabaId != null) 'X-Waba-User-Id': '$wabaId',
            'Idempotency-Key': ?idempotencyKey,
          },
        ),
      );
      final body = object(response.data);
      final status = response.statusCode ?? 0;
      if (status == 401 && authenticated && requestToken == token) {
        onUnauthorized?.call();
      }
      if (status < 200 ||
          status >= 300 ||
          body['success'] == false ||
          body['status'] == false) {
        final validation = object(body['errors']).values
            .expand((v) => v is List ? v : [v])
            .join('\n');
        final message =
            path == 'inbox/send' &&
                body['message'] == 'Your user session is expired.'
            ? 'This contact’s messaging window has expired. Ask the customer '
                  'to message you again, or send an approved template.'
            : '${body['message'] ?? 'Request failed ($status). Please try again.'}';
        final provider = object(body['error']);
        final providerDetail =
            object(provider['error_data'])['details'] ?? provider['message'];
        throw ApiFailure(
          validation.isNotEmpty
              ? validation
              : providerDetail is String && providerDetail.isNotEmpty
              ? providerDetail
              : message,
          code: '${body['code'] ?? body['status'] ?? ''}',
          httpStatus: status,
          uncertain: status >= 500 || body['code'] == 'send_in_progress',
        );
      }
      if (response.data is! Map && response.data is! List) {
        throw const ApiFailure('The server returned an unexpected response.');
      }
      return response.data;
    } on DioException catch (_) {
      throw const ApiFailure(
        'Could not reach the server. Check your connection and try again.',
        uncertain: true,
      );
    }
  }

  Future<Json> get(String path, {Json? query}) async =>
      object(await request(path, query: query));
  Future<Json> post(String path, [Json? body]) async =>
      object(await request(path, method: 'POST', data: body));
}

/// Which inbox the selected number gets. TheMessenger's ticketing mode
/// replaces the shared inbox rather than adding to it, so a number has one.
enum InboxMode { shared, tickets, none }

/// Session state is kept separate from preview data and scoped to the API host.
class MobileSession extends ChangeNotifier {
  MobileSession(
    this.api,
    this.store, {
    this.realtimeConnector,
    this.pushTransport,
  }) {
    api.onUnauthorized = _expired;
  }
  final MobileApi api;
  final SessionStore store;

  /// Tests replace the websocket transport; the app uses the platform one.
  final RealtimeConnector? realtimeConnector;

  /// Tests replace Firebase; the app uses it when configured.
  final PushTransport? pushTransport;

  /// Live updates for the selected number; started by the signed-in home.
  late final realtime = Realtime(this, connector: realtimeConnector);

  /// Push registration and taps; enabled by the signed-in home.
  late final push = PushService(this, transport: pushTransport);

  /// `contact:12` / `ticket:7` while that chat is on screen, so a push for it
  /// is not shown on top of the conversation itself.
  String? visibleConversation;

  /// `contact:12` for the customer of the chat on screen (shared inbox or
  /// ticket), so a push about them is not shown over their conversation.
  final visibleContacts = <String>{};

  /// A tapped notification waiting for the home screen to open it.
  Json? pendingOpen;

  void openFromPush(Json data) {
    pendingOpen = data;
    notifyListeners();
  }

  /// Phone of the selected WhatsApp number; names the inbox list channel.
  String? get wabaPhone {
    final phone = object(object(config?['inbox'])['waba_user'])['phone'];
    return phone == null || '$phone'.isEmpty ? null : '$phone';
  }

  /// Name of the selected WhatsApp number, shown on the number switcher.
  String get wabaName {
    final waba = object(object(config?['inbox'])['waba_user']);
    return '${waba['name'] ?? waba['phone'] ?? 'Number'}';
  }

  int? get authUserId =>
      number(object(object(config?['inbox'])['auth_user'])['id']) ??
      number(user?['id']);

  /// This phone's own channel, where the server announces a remote sign-out.
  String? get deviceChannel {
    final channel = object(config?['realtime'])['device_channel'];
    return channel == null ? null : '$channel';
  }

  /// The server revoked this device (signed out elsewhere).
  void deviceRevoked() => _expired();
  Json? user, challenge, config;
  final viewCache = <String, Object>{};
  bool restoring = true;
  String? error;
  int generation = 0;
  String get storageKey => 'session.${Uri.parse(api.dio.options.baseUrl).host}';
  bool get signedIn => api.token != null && user != null;
  bool get ready => signedIn && api.wabaId != null && config != null;

  /// Whether the server lets this account use a route, by its name in the
  /// capabilities list (which already applies permissions, the plan and
  /// ticketing mode). Null when the server sent no capabilities.
  bool? canRoute(String name) {
    final actions = rows(object(config?['capabilities'])['actions']);
    if (actions.isEmpty) return null;
    return actions.any((a) => a['name'] == name && a['allowed'] == true);
  }

  /// Shared inbox when its list is allowed; otherwise the ticket inbox when
  /// that is (ticketing mode); otherwise neither. Re-read on number switch.
  InboxMode get inboxMode {
    final shared = canRoute('inbox.contacts.list');
    if (shared == null || shared) return InboxMode.shared;
    return canRoute('ticket-inbox-api.tickets.list') == true
        ? InboxMode.tickets
        : InboxMode.none;
  }

  bool allows(String path) {
    final actions = rows(object(config?['capabilities'])['actions']);
    final matches = actions.where((a) => '${a['path']}'.endsWith(path));
    return matches.isEmpty || matches.any((a) => a['allowed'] == true);
  }

  Future<void> restore() async {
    restoring = true;
    error = null;
    notifyListeners();
    try {
      final saved = object(decoded(await store.read(storageKey)));
      api.token = saved['token'] as String?;
      if (api.token != null) {
        user = await api.get('me');
        final selected =
            number(user?['bound_waba_user_id']) ?? number(saved['waba_id']);
        if (selected != null) await selectNumber(selected);
      }
    } catch (e) {
      error = '$e';
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    var install = await store.read('install_id');
    if (install == null) {
      install = newRequestId();
      await store.write('install_id', install);
    }
    final result = object(
      await api.request(
        'auth/login',
        method: 'POST',
        authenticated: false,
        data: {
          'email': email.trim(),
          'password': password,
          'device_uuid': install,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 1 : 2,
          'device_name': defaultTargetPlatform == TargetPlatform.iOS
              ? 'iPhone'
              : 'Android phone',
        },
      ),
    );
    if (result['status'] == 'two_factor_required') {
      challenge = result;
      notifyListeners();
      return;
    }
    await _authenticated(result);
  }

  Future<void> verify(
    String code,
    String method, {
    bool recovery = false,
  }) async {
    await _authenticated(
      object(
        await api.request(
          'auth/two-factor',
          method: 'POST',
          authenticated: false,
          data: {
            'challenge_token': challenge?['challenge_token'],
            'code': code.trim(),
            'method': method,
            'recovery': recovery,
          },
        ),
      ),
    );
  }

  Future<void> resend(String method) async {
    await api.request(
      'auth/two-factor/resend',
      method: 'POST',
      authenticated: false,
      data: {
        'challenge_token': challenge?['challenge_token'],
        'method': method,
      },
    );
  }

  void cancelChallenge() {
    challenge = null;
    notifyListeners();
  }

  Future<void> _authenticated(Json result) async {
    if (result['status'] != 'authenticated' || result['token'] is! String) {
      throw const ApiFailure('Sign-in was not completed. Please try again.');
    }
    api.token = result['token'];
    challenge = null;
    api.wabaId = null;
    config = null;
    await _persist();
    user = await api.get('me');
    try {
      final bound = number(user?['bound_waba_user_id']);
      if (bound != null) await selectNumber(bound);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persist() => store.write(
    storageKey,
    jsonEncode({'token': api.token, 'waba_id': api.wabaId}),
  );
  Future<void> selectNumber(int id) async {
    generation++;
    api.wabaId = id;
    config = null;
    try {
      config = await api.get('config');
      await _persist();
    } catch (_) {
      api.wabaId = null;
      rethrow;
    }
    notifyListeners();
  }

  void switchNumber() {
    realtime.stop();
    viewCache.clear();
    generation++;
    api.wabaId = null;
    config = null;
    notifyListeners();
  }

  void _expired() {
    realtime.stop();
    viewCache.clear();
    generation++;
    api.token = null;
    api.wabaId = null;
    user = null;
    config = null;
    challenge = null;
    error = 'Your session ended. Please sign in again.';
    // Clear the persisted bearer without delaying navigation. Errors do not expose it.
    store.delete(storageKey).catchError((_) {});
    notifyListeners();
  }

  Future<void> logout() async {
    await push.disable();
    await api.post('auth/logout');
    await store.delete(storageKey);
    _expired();
    error = null;
  }

  @override
  void dispose() {
    api.onUnauthorized = null;
    realtime.dispose();
    push.dispose();
    super.dispose();
  }
}
