import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Whether the phone can reach the Telvox server: true online, false offline.
///
/// The phone says at once when Wi-Fi and mobile data are both gone; a
/// network that is up is confirmed by asking the server's health check,
/// since Wi-Fi without internet (a captive portal, a dead router) looks
/// connected too. A request that cannot reach the server checks again. While
/// offline it keeps checking, so the app comes back by itself.
class ConnectionMonitor extends ValueNotifier<bool> {
  ConnectionMonitor({
    required this.probe,
    this.links,
    this.linked,
    this.retry = const Duration(seconds: 5),
  }) : super(true);

  /// The phone's own network events and the server's health check.
  factory ConnectionMonitor.platform(Uri server) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        // Any answer at all means the server is reachable.
        validateStatus: (_) => true,
      ),
    );
    final health = server.replace(path: '/up', query: '');
    bool anyNetwork(List<ConnectivityResult> r) =>
        r.any((c) => c != ConnectivityResult.none);
    return ConnectionMonitor(
      probe: () async {
        try {
          await dio.headUri<void>(health);
          return true;
        } catch (_) {
          return false;
        }
      },
      links: Connectivity().onConnectivityChanged.map(anyNetwork),
      linked: () async => anyNetwork(await Connectivity().checkConnectivity()),
    );
  }

  /// Always online, checking nothing: tests and builds without a monitor.
  ConnectionMonitor.always() : this(probe: () async => true);

  /// Whether the server answers.
  final Future<bool> Function() probe;

  /// Whether the phone has any network, as it changes, and right now.
  final Stream<bool>? links;
  final Future<bool> Function()? linked;

  /// How often to check again while offline.
  final Duration retry;
  StreamSubscription<bool>? _events;
  Timer? _again;
  Future<bool>? _checking;
  Future<bool>? _next;
  bool _started = false;
  bool _paused = false;

  bool get online => value;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _events = links?.listen(_link, onError: (_) {});
    try {
      final linked = this.linked;
      if (linked != null && !await linked()) {
        _set(false);
        return;
      }
    } catch (_) {
      // The phone could not say: the health check decides.
    }
    await check();
  }

  void _link(bool up) {
    if (!up) {
      _set(false);
    } else {
      unawaited(check());
    }
  }

  /// Asks the server now, one check at a time. Asked while a check is
  /// running, it checks once more after it: the network may have come back
  /// since that one began.
  Future<bool> check() {
    if (!_started) return Future.value(value);
    final running = _checking;
    if (running != null) {
      return _next ??= running.then((_) {
        _next = null;
        return check();
      });
    }
    return _checking = _ask();
  }

  Future<bool> _ask() async {
    try {
      final reachable = await probe();
      _set(reachable);
      return reachable;
    } finally {
      _checking = null;
    }
  }

  /// A request could not reach the server: find out whether the phone is
  /// offline.
  void unreachable() => unawaited(check());

  /// The app went to the background: no checking while nobody is looking.
  void pause() {
    _paused = true;
    _again?.cancel();
  }

  /// The app is open again: one check now, and the offline retries resume.
  void resume() {
    if (!_paused) return;
    _paused = false;
    unawaited(check());
  }

  void _set(bool reachable) {
    _again?.cancel();
    // Only while the app is open and offline: no polling otherwise.
    if (!reachable && _started && !_paused) {
      _again = Timer(retry, () => check());
    }
    value = reachable;
  }

  @override
  void dispose() {
    _events?.cancel();
    _again?.cancel();
    super.dispose();
  }
}
