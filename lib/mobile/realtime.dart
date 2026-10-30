import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';

/// Transport seam so the protocol can be tested without a network.
abstract class RealtimeSocket {
  Stream<dynamic> get messages;
  void send(String data);
  Future<void> close();
}

class _IoSocket implements RealtimeSocket {
  _IoSocket(this._socket);
  final WebSocket _socket;
  @override
  Stream<dynamic> get messages => _socket;
  @override
  void send(String data) => _socket.add(data);
  @override
  Future<void> close() => _socket.close();
}

typedef RealtimeConnector = Future<RealtimeSocket> Function(Uri uri);

Future<RealtimeSocket> _connectIo(Uri uri) async => _IoSocket(
  await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 15)),
);

enum RealtimeState { off, connecting, connected, reconnecting }

typedef RealtimeHandler = void Function(String event, Object? data);

/// One listener on a channel. [onResync] runs after the channel is joined
/// again following a dropped connection, so screens can catch up on events
/// they missed while offline.
class RealtimeSubscription {
  RealtimeSubscription._(
    this._owner,
    this.channel,
    this.onEvent,
    this.onResync,
  );
  final Realtime _owner;
  final String channel;
  final RealtimeHandler onEvent;
  final VoidCallback? onResync;
  bool _active = true;
  void cancel() {
    if (!_active) return;
    _active = false;
    _owner._remove(this);
  }
}

/// Minimal Pusher-protocol client for Laravel Reverb, the same server the web
/// inbox uses through Laravel Echo. Private channels are authorised through
/// the mobile `broadcasting/auth` endpoint with the session's bearer token and
/// pinned number. Reconnects with backoff; the app disconnects in background.
class Realtime extends ChangeNotifier {
  Realtime(this.session, {RealtimeConnector? connector})
    : _connector = connector ?? _connectIo;
  final MobileSession session;
  final RealtimeConnector _connector;

  RealtimeState state = RealtimeState.off;
  RealtimeSocket? _socket;
  StreamSubscription<dynamic>? _incoming;
  String? _socketId;
  bool _wanted = false;
  int _attempt = 0, _connection = 0;
  Timer? _retry, _idle, _pong;
  Duration _activityTimeout = const Duration(seconds: 120);

  /// Channel name (with `private-` prefix) to its listeners.
  final _listeners = <String, List<RealtimeSubscription>>{};

  /// Channels joined on the current connection.
  final _joined = <String>{};

  /// Channels joined on any earlier connection; rejoining one triggers resync.
  final _everJoined = <String>{};

  Json get _settings => object(session.config?['realtime']);

  /// False when the server sends no websocket settings; screens then rely on
  /// refreshing when they open and when the app returns to the foreground.
  bool get available =>
      '${_settings['key'] ?? ''}'.isNotEmpty &&
      '${_settings['host'] ?? ''}'.isNotEmpty;

  void start() {
    if (_wanted) return;
    _wanted = true;
    _connect();
  }

  /// Leaves every channel's listeners registered, so [start] rejoins them.
  void stop() {
    _wanted = false;
    _retry?.cancel();
    _closeSocket();
    _setState(RealtimeState.off);
  }

  RealtimeSubscription listen(
    String channel,
    RealtimeHandler onEvent, {
    VoidCallback? onResync,
  }) {
    final name = channel.startsWith('private-') ? channel : 'private-$channel';
    final sub = RealtimeSubscription._(this, name, onEvent, onResync);
    final list = _listeners.putIfAbsent(name, () => []);
    list.add(sub);
    if (list.length == 1 && state == RealtimeState.connected) _subscribe(name);
    return sub;
  }

  void _remove(RealtimeSubscription sub) {
    final list = _listeners[sub.channel];
    if (list == null) return;
    list.remove(sub);
    if (list.isNotEmpty) return;
    _listeners.remove(sub.channel);
    if (_joined.remove(sub.channel)) {
      _write('pusher:unsubscribe', {'channel': sub.channel});
    }
    _everJoined.remove(sub.channel);
  }

  Uri? get _uri {
    if (!available) return null;
    final secure = '${_settings['scheme'] ?? 'https'}' == 'https';
    final port = number(_settings['port']) ?? (secure ? 443 : 80);
    return Uri(
      scheme: secure ? 'wss' : 'ws',
      host: '${_settings['host']}',
      port: port,
      path: '/app/${_settings['key']}',
      queryParameters: {
        'protocol': '7',
        'client': 'telvox-dart',
        'version': '1.0',
        'flash': 'false',
      },
    );
  }

  Future<void> _connect() async {
    _retry?.cancel();
    final uri = _uri;
    if (!_wanted || uri == null) {
      _setState(RealtimeState.off);
      return;
    }
    final connection = ++_connection;
    _setState(
      _everJoined.isEmpty && _attempt == 0
          ? RealtimeState.connecting
          : RealtimeState.reconnecting,
    );
    try {
      final socket = await _connector(uri);
      if (!_wanted || connection != _connection) {
        await socket.close();
        return;
      }
      _socket = socket;
      _incoming = socket.messages.listen(
        _receive,
        onDone: () => _dropped(connection),
        onError: (_) => _dropped(connection),
        cancelOnError: true,
      );
    } catch (_) {
      if (connection == _connection) _scheduleRetry();
    }
  }

  void _dropped(int connection) {
    if (connection != _connection) return;
    _closeSocket();
    if (_wanted) _scheduleRetry();
  }

  void _scheduleRetry({Duration? after}) {
    if (!_wanted) return;
    _setState(RealtimeState.reconnecting);
    final seconds = min(30, pow(2, _attempt).toInt());
    _attempt++;
    _retry?.cancel();
    _retry = Timer(after ?? Duration(seconds: seconds), _connect);
  }

  void _closeSocket() {
    _connection++;
    _idle?.cancel();
    _pong?.cancel();
    _incoming?.cancel();
    _incoming = null;
    _socket?.close().catchError((_) {});
    _socket = null;
    _socketId = null;
    _joined.clear();
  }

  void _receive(dynamic raw) {
    _touch();
    final message = object(decoded(raw is String ? raw : utf8.decode(raw)));
    final event = '${message['event'] ?? ''}';
    final data = message['data'] is String
        ? decoded(message['data']) ?? message['data']
        : message['data'];
    switch (event) {
      case 'pusher:connection_established':
        final info = object(data);
        _socketId = '${info['socket_id'] ?? ''}';
        _activityTimeout = Duration(
          seconds: (number(info['activity_timeout']) ?? 120).clamp(10, 300),
        );
        _attempt = 0;
        _setState(RealtimeState.connected);
        _touch();
        for (final channel in _listeners.keys.toList()) {
          _subscribe(channel);
        }
      case 'pusher:ping':
        _write('pusher:pong', {});
      case 'pusher:pong':
        _pong?.cancel();
      case 'pusher_internal:subscription_succeeded':
        final channel = '${message['channel'] ?? ''}';
        _joined.add(channel);
        if (!_everJoined.add(channel)) {
          for (final sub in [...?_listeners[channel]]) {
            sub.onResync?.call();
          }
        }
      case 'pusher:error':
        final code = number(object(data)['code']) ?? 0;
        _closeSocket();
        if (code >= 4000 && code < 4100) {
          // Application or protocol problem: retrying will not help soon.
          _scheduleRetry(after: const Duration(seconds: 60));
        } else {
          _scheduleRetry(
            after: code >= 4200 && code < 4300 ? Duration.zero : null,
          );
        }
      case 'pusher:subscription_error':
        break;
      default:
        final channel = '${message['channel'] ?? ''}';
        if (event.startsWith('pusher')) return;
        for (final sub in [...?_listeners[channel]]) {
          if (sub._active) sub.onEvent(event, data);
        }
    }
  }

  Future<void> _subscribe(String channel) async {
    final socketId = _socketId;
    final endpoint = '${_settings['auth_endpoint'] ?? ''}';
    if (socketId == null || endpoint.isEmpty) return;
    final connection = _connection;
    try {
      final auth = object(
        await session.api.request(
          endpoint,
          method: 'POST',
          data: {'socket_id': socketId, 'channel_name': channel},
        ),
      );
      if (connection != _connection || !_listeners.containsKey(channel)) {
        return;
      }
      _write('pusher:subscribe', {'channel': channel, 'auth': auth['auth']});
    } catch (_) {
      // Not authorised for this channel (or offline): the screen still works
      // through its own refreshes; the next reconnect tries again.
    }
  }

  void _write(String event, Json data) {
    _socket?.send(jsonEncode({'event': event, 'data': data}));
  }

  /// Any traffic proves the link is alive. After a quiet spell, ping; no pong
  /// within 30s means the connection is dead even if the OS has not noticed.
  void _touch() {
    _idle?.cancel();
    if (state != RealtimeState.connected) return;
    final connection = _connection;
    _idle = Timer(_activityTimeout, () {
      if (connection != _connection) return;
      _write('pusher:ping', {});
      _pong?.cancel();
      _pong = Timer(const Duration(seconds: 30), () => _dropped(connection));
    });
  }

  void _setState(RealtimeState next) {
    if (state == next) return;
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _listeners.clear();
    super.dispose();
  }
}
