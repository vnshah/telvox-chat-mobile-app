import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config/app_config.dart';
import 'call_push.dart';
import 'calls.dart';
import 'connection.dart';
import 'conversation_sync.dart';
import 'local_cache.dart';
import 'media_cache.dart';
import 'notification_sound.dart';
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
    this.unreachable = false,
  });
  final String message;
  final String? code;
  final int? httpStatus;
  final bool uncertain;

  /// The server could not be reached at all: no network, or no answer.
  final bool unreachable;
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

  /// A request got no answer from the server (see [ConnectionMonitor]).
  VoidCallback? onUnreachable;
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
      onUnreachable?.call();
      throw const ApiFailure(
        'Could not reach the server. Check your connection and try again.',
        uncertain: true,
        unreachable: true,
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
    this.callMedia,
    LocalCache? cache,
    ConnectionMonitor? connection,
  }) : cache = cache ?? MemoryLocalCache(),
       connection = connection ?? ConnectionMonitor.always() {
    api.onUnauthorized = _expired;
    api.onUnreachable = this.connection.unreachable;
    this.connection.addListener(_connectionChanged);
  }

  /// Whether the server can be reached; the app covers itself while not.
  final ConnectionMonitor connection;

  /// The app opened without a network. With the account kept from the last
  /// time it was online, the inbox opens from the phone's copy and the
  /// account is refreshed quietly once the server can be reached; without
  /// it, the session finishes loading then. Never the sign-in screen.
  bool awaitingNetwork = false;

  void _connectionChanged() {
    if (!connection.online || !awaitingNetwork || restoring) return;
    unawaited(ready ? _refreshAccount() : restore());
  }

  /// The signed-in account and its number's settings, kept (encrypted, with
  /// the sign-in) so the app can open offline.
  String get _accountKey =>
      'account.${Uri.parse(api.dio.options.baseUrl).host}';

  Future<void> _rememberAccount() async {
    if (user == null || config == null || api.wabaId == null) return;
    try {
      await store.write(
        _accountKey,
        jsonEncode({'user': user, 'config': config, 'waba_id': api.wabaId}),
      );
    } catch (_) {
      // Without it, opening offline waits for the network.
    }
  }

  /// Opened offline: the account as it was last seen, for [wanted].
  Future<bool> _openOffline(int? wanted, Json? saved) async {
    final account = object(decoded(await store.read(_accountKey)));
    final kept = object(account['user']), settings = object(account['config']);
    final id = number(account['waba_id']);
    if (kept.isEmpty || settings.isEmpty || id == null) return false;
    if (wanted != null && wanted != id) return false;
    user = kept;
    business = picksBusiness ? _business(saved?['business']) : null;
    api.wabaId = id;
    config = settings;
    await _openCache();
    return true;
  }

  /// Back online after opening offline: the account and settings are fetched
  /// again in place. The app is not rebuilt, so an open chat stays open.
  Future<void> _refreshAccount() async {
    try {
      final me = await api.get('me');
      final settings = await api.get('config');
      user = me;
      config = settings;
      awaitingNetwork = false;
      await _rememberAccount();
      notifyListeners();
    } on ApiFailure catch (e) {
      if (e.unreachable) return; // Still offline: the next return retries.
      awaitingNetwork = false;
      unawaited(restore());
    }
  }

  final MobileApi api;
  final SessionStore store;

  /// The on-device copy screens render from first; see [LocalCache].
  final LocalCache cache;

  /// The latest message an open chat has synced, from any sender, so the
  /// inbox row follows at once: `{id, last_message, last_message_date,
  /// unread_message_count}`.
  final conversationActivity = ValueNotifier<Json?>(null);

  /// Brings the busiest chats' copies up to date in the background.
  late final conversations = ConversationSync(this);

  /// Chats this phone has told the server it has open, per number: contact
  /// id → open count. The server counts no unread messages for a chat
  /// someone is viewing, and it treats this phone as viewing while the app
  /// is in use, so a "left" that never arrived (the app was swiped away or
  /// lost its network in a chat) would keep that chat's badge from ever
  /// showing. Kept on the phone until the server has heard each one left.
  static const _openChatsKey = 'open_chats';
  Future<void> _openChatsLock = Future.value();

  Future<T> _withOpenChats<T>(
    T Function(Map<String, Map<String, int>> chats) change,
  ) {
    final done = _openChatsLock.then((_) async {
      final saved = object(decoded(await store.read(_openChatsKey)));
      final chats = {
        for (final e in saved.entries)
          e.key: {
            for (final c in object(e.value).entries)
              if (number(c.value) case final int n when n > 0) c.key: n,
          },
      };
      final result = change(chats);
      chats.removeWhere((_, open) => open.isEmpty);
      await store.write(_openChatsKey, jsonEncode(chats));
      return result;
    });
    _openChatsLock = done.then((_) {}, onError: (_) {});
    return done;
  }

  /// Tells the server this phone opened or left a chat, as the web inbox
  /// does: messages arriving while it is open are not counted as unread.
  Future<void> focusChat(int contactId, {required bool open}) async {
    final waba = '${api.wabaId ?? ''}';
    try {
      if (open) {
        await _withOpenChats((chats) {
          final mine = chats.putIfAbsent(waba, () => {});
          mine['$contactId'] = (mine['$contactId'] ?? 0) + 1;
        });
      }
      await api.post('inbox/conversation/focus', {
        open ? 'contact_id' : 'previous_contact_id': contactId,
      });
      if (!open) await _forgetOpen(waba, contactId);
    } catch (_) {
      // A "left" that did not arrive stays listed; releaseOpenChats retries.
    }
  }

  Future<void> _forgetOpen(String waba, int contactId) =>
      _withOpenChats((chats) {
        final mine = chats[waba];
        if (mine == null) return;
        final left = (mine['$contactId'] ?? 0) - 1;
        if (left > 0) {
          mine['$contactId'] = left;
        } else {
          mine.remove('$contactId');
        }
      });

  /// Tells the server again that this phone left any chat it still lists as
  /// open but no longer shows: after a restart, on returning to the app, and
  /// with the heartbeat. Chats on screen keep their own focus.
  Future<void> releaseOpenChats() async {
    final waba = '${api.wabaId ?? ''}';
    if (api.token == null) return;
    try {
      final stale = await _withOpenChats(
        (chats) => {
          for (final e in (chats[waba] ?? const <String, int>{}).entries)
            if (!visibleContacts.contains('contact:${e.key}')) e.key: e.value,
        },
      );
      for (final MapEntry(key: id, value: times) in stale.entries) {
        for (var i = 0; i < times; i++) {
          await api.post('inbox/conversation/focus', {
            'previous_contact_id': int.parse(id),
          });
          await _forgetOpen(waba, int.parse(id));
        }
      }
    } catch (_) {
      // Offline: the next heartbeat or return to the app tries again.
    }
  }

  /// Opens the cache for this server and account. A failure only costs speed.
  Future<void> _openCache() async {
    try {
      await cache.open(cacheOwner(api.dio.options.baseUrl, user?['id']));
    } catch (_) {}
  }

  void _wipeCache() => cache.wipe().catchError((_) {});

  /// Tests replace the websocket transport; the app uses the platform one.
  final RealtimeConnector? realtimeConnector;

  /// Tests replace Firebase; the app uses it when configured.
  final PushTransport? pushTransport;

  /// Live updates for the selected number; started by the signed-in home.
  late final realtime = Realtime(this, connector: realtimeConnector)
    ..addListener(_realtimeChanged);

  /// The live connection is the first to notice internet gone while the
  /// phone still shows a network (Wi-Fi up, router dead): its drop checks
  /// the connection, and its return checks again so the app comes back.
  RealtimeState? _realtimeWas;
  void _realtimeChanged() {
    final now = realtime.state;
    if (now == _realtimeWas) return;
    _realtimeWas = now;
    if (now == RealtimeState.reconnecting || now == RealtimeState.connected) {
      unawaited(connection.check());
    }
  }

  /// Push registration and taps; enabled by the signed-in home.
  late final push = PushService(this, transport: pushTransport);

  /// What a new message sounds like on this phone, chosen in the account
  /// menu and kept on the phone across sign-ins.
  final notificationSound = ValueNotifier(NotificationSound.fallback);
  static const _soundKey = 'notification_sound';

  Future<void> setNotificationSound(NotificationSound sound) async {
    notificationSound.value = sound;
    await store.write(_soundKey, sound.name);
    await push.useSound(sound);
  }

  /// Tests replace WebRTC; the app uses the device's microphone and network.
  final CallMedia Function()? callMedia;

  /// WhatsApp calls on this phone; joined by the signed-in home.
  late final calls = PhoneCalls(this, mediaFactory: callMedia);

  /// `contact:12` / `ticket:7` while that chat is on screen, so a push for it
  /// is not shown on top of the conversation itself.
  String? visibleConversation;

  /// The shared-inbox chat on screen, which the heartbeat names: the server
  /// counts a phone as viewing a chat only while it keeps naming it, so a
  /// phone that dies in a chat stops hiding its new messages within minutes.
  int? get openContactId {
    final visible = visibleConversation ?? '';
    return visible.startsWith('contact:')
        ? int.tryParse(visible.substring(8))
        : null;
  }

  /// `contact:12` for the customer of the chat on screen (shared inbox or
  /// ticket), so a push about them is not shown over their conversation.
  final visibleContacts = <String>{};

  /// A tapped notification waiting for the home screen to open it.
  Json? pendingOpen;

  void openFromPush(Json data) {
    pendingOpen = data;
    notifyListeners();
  }

  /// A call accepted on the system's incoming-call screen, for the home screen
  /// to answer once signed in on its number.
  Json? pendingCall;

  void answerFromPush(Json data) {
    pendingCall = data;
    notifyListeners();
  }

  /// The system incoming-call screen's buttons; started with the app.
  late final callPush = CallPushBridge(this);

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

  /// Whether the composer may send a kind of message from this number
  /// (capabilities.message_types); null when the server did not say.
  bool? canSendType(String type) {
    final types = object(object(config?['capabilities'])['message_types']);
    final allowed = types[type];
    return allowed == null ? null : allowed == true;
  }

  bool allows(String path) {
    final actions = rows(object(config?['capabilities'])['actions']);
    final matches = actions.where((a) => '${a['path']}'.endsWith(path));
    return matches.isEmpty || matches.any((a) => a['allowed'] == true);
  }

  Future<void> restore() async {
    restoring = true;
    awaitingNetwork = false;
    error = null;
    notifyListeners();
    try {
      notificationSound.value = NotificationSound.from(
        await store.read(_soundKey),
      );
      final saved = object(decoded(await store.read(storageKey)));
      api.token = saved['token'] as String?;
      if (api.token != null) {
        user = await api.get('me');
        await _openCache();
        business = picksBusiness ? _business(saved['business']) : null;
        final selected =
            number(user?['bound_waba_user_id']) ?? number(saved['waba_id']);
        if (selected != null) await selectNumber(selected);
      }
    } on ApiFailure catch (e) {
      if (e.unreachable && api.token != null) {
        awaitingNetwork = true;
        final saved = object(decoded(await store.read(storageKey)));
        final opened = await _openOffline(
          number(saved['waba_id']),
          saved,
        ).catchError((_) => false);
        if (!opened) {
          user = null;
          api.wabaId = null;
          config = null;
        }
      } else {
        error = '$e';
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
    business = null;
    config = null;
    await _persist();
    user = await api.get('me');
    await _openCache();
    try {
      final bound = number(user?['bound_waba_user_id']);
      if (bound != null) await selectNumber(bound);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persist() => store.write(
    storageKey,
    jsonEncode({
      'token': api.token,
      'waba_id': api.wabaId,
      'business': ?business,
    }),
  );

  /// The one business this account belongs to: a business owner's own, or
  /// the business of its manager or sub-user. Null for an admin or reseller,
  /// who work across businesses and pick one first. The server holds the
  /// account to it: another business's numbers are refused.
  int? get ownBusinessId => number(user?['business_user_id']);

  /// Whether this account picks a business before a number: admins, super
  /// admins and resellers. Everyone else goes straight to their numbers.
  bool get picksBusiness => canSwitchNumber && ownBusinessId == null;

  /// The business an admin or reseller is working in (`id`, `name`), kept
  /// across number switches and restarts so switching number stays within
  /// it. Null for everyone else: their business is [ownBusinessId].
  Json? business;

  static Json? _business(Object? saved) {
    final b = object(saved);
    final id = number(b['id']);
    return id == null ? null : {'id': id, 'name': '${b['name'] ?? ''}'};
  }

  /// An admin or reseller chose [picked] and is about to choose its number.
  void chooseBusiness(Json? picked) {
    if (!picksBusiness) return;
    business = _business(picked);
  }

  Future<void> selectNumber(int id) async {
    generation++;
    api.wabaId = id;
    config = null;
    try {
      config = await api.get('config');
      await _persist();
      unawaited(_rememberAccount());
      unawaited(releaseOpenChats());
    } catch (_) {
      api.wabaId = null;
      rethrow;
    }
    notifyListeners();
  }

  /// Only an admin, reseller or business owner picks among numbers. A number's
  /// own login, a sub-user or a manager works on the one number it belongs to.
  bool get canSwitchNumber =>
      user != null && number(user!['bound_waba_user_id']) == null;

  void switchNumber() {
    if (!canSwitchNumber) return;
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
    // A session that ended, was revoked or signed out leaves no chats behind,
    // and no media either.
    _wipeCache();
    unawaited(MediaCache.instance.wipe());
    generation++;
    api.token = null;
    api.wabaId = null;
    user = null;
    business = null;
    config = null;
    challenge = null;
    error = 'Your session ended. Please sign in again.';
    // Clear the persisted bearer without delaying navigation. Errors do not expose it.
    store.delete(storageKey).catchError((_) {});
    store.delete(_accountKey).catchError((_) {});
    notifyListeners();
  }

  /// Signs this phone out. The server is told first, while the token is
  /// still known; but the phone forgets the account even when the server
  /// cannot be reached (offline, or already signed out there), so signing
  /// out always works. A token the server never heard about expires there.
  Future<void> logout() async {
    await push.disable();
    try {
      await api.post('auth/logout').timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline or refused: this phone still signs out.
    }
    await store.delete(storageKey).catchError((_) {});
    await store.delete(_openChatsKey).catchError((_) {});
    _expired();
    error = null;
  }

  @override
  void dispose() {
    api.onUnauthorized = null;
    api.onUnreachable = null;
    connection.removeListener(_connectionChanged);
    conversationActivity.dispose();
    notificationSound.dispose();
    realtime.dispose();
    push.dispose();
    calls.dispose();
    callPush.dispose();
    super.dispose();
  }
}
