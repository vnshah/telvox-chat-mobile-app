import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/config/app_config.dart';
import 'api.dart';

/// What a push carries, whichever way it reached the app.
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});
  final String? title, body;
  final Json data;

  /// `contact:12` or `ticket:7`; matches [MobileSession.visibleConversation].
  String? get conversation => data['ticket_id'] != null
      ? 'ticket:${data['ticket_id']}'
      : data['contact_id'] != null
      ? 'contact:${data['contact_id']}'
      : null;

  /// The customer this push is about, whichever screen shows them.
  String? get contactKey =>
      data['contact_id'] == null ? null : 'contact:${data['contact_id']}';
}

/// Platform seam: Firebase in the app, a fake in tests.
abstract class PushTransport {
  /// Prepares messaging; false when push cannot run on this device.
  Future<bool> start();
  Future<String?> token();
  Stream<String> get tokenRefresh;
  Stream<PushMessage> get foreground;
  Stream<PushMessage> get opened;
  Future<PushMessage?> launchMessage();
  Future<void> show(PushMessage message);
  Future<void> forget();
}

/// Registers this phone for push with the server, shows pushes that arrive
/// while the app is open (except for the conversation on screen), and turns
/// taps into [MobileSession.pendingOpen] for the home screen to act on.
class PushService {
  PushService(this.session, {PushTransport? transport})
    : _transport =
          transport ??
          (AppConfig.firebaseConfigured ? FirebasePushTransport() : null);
  final MobileSession session;
  final PushTransport? _transport;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _started = false;
  String? _registered;

  bool get available => _transport != null;

  /// Safe to call on every sign-in and number switch; work happens once.
  Future<void> enable() async {
    final transport = _transport;
    if (transport == null || !session.signedIn) return;
    if (!_started) {
      try {
        if (!await transport.start()) return;
      } catch (_) {
        return;
      }
      _started = true;
      _subscriptions
        ..add(transport.tokenRefresh.listen(_register))
        ..add(transport.foreground.listen(_foreground))
        ..add(transport.opened.listen(_open));
      final launch = await transport.launchMessage();
      if (launch != null) _open(launch);
    }
    await _register(await transport.token());
  }

  Future<void> _register(String? token) async {
    if (token == null || token.isEmpty || !session.signedIn) return;
    if (token == _registered) return;
    try {
      await session.api.request(
        'me/push-token',
        method: 'PUT',
        data: {'token': token, 'provider': 'fcm'},
      );
      _registered = token;
    } catch (_) {
      // Retried on the next sign-in, number switch or token refresh.
    }
  }

  /// Nothing to announce for the customer whose chat is on screen, whether
  /// it is their shared-inbox chat or one of their ticket conversations.
  void _foreground(PushMessage message) {
    final contact = message.contactKey;
    if (contact != null && session.visibleContacts.contains(contact)) return;
    _transport?.show(message);
  }

  void _open(PushMessage message) {
    if (message.conversation == null) return;
    session.openFromPush(message.data);
  }

  /// Signing out: the server forgets the token with the device; drop it here
  /// too so a different account on this phone gets a fresh one.
  Future<void> disable() async {
    _registered = null;
    try {
      await _transport?.forget();
    } catch (_) {
      /* Nothing to undo if Firebase never started. */
    }
  }

  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }
}

class FirebasePushTransport implements PushTransport {
  static const channel = AndroidNotificationChannel(
    'inbox',
    'Messages and tickets',
    description: 'New customer messages and ticket activity',
    importance: Importance.high,
  );
  final _local = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<PushMessage>.broadcast();
  int _id = 0;

  @override
  Future<bool> start() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
    }
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_telvox'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final data = object(decoded(response.payload));
        if (data.isNotEmpty) _taps.add(PushMessage(data: data));
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    return true;
  }

  static PushMessage _message(RemoteMessage m) => PushMessage(
    title: m.notification?.title,
    body: m.notification?.body,
    data: Map<String, dynamic>.from(m.data),
  );

  // Registration tokens are what the server's FCM HTTP v1 `message.token`
  // targets. firebase_messaging 17 deprecates them in favour of installation
  // IDs (register/onRegistered); moving needs the server to send by FID too.
  @override
  // ignore: deprecated_member_use
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get tokenRefresh =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<PushMessage> get foreground =>
      FirebaseMessaging.onMessage.map(_message);

  @override
  Stream<PushMessage> get opened => StreamGroupMerge(
    FirebaseMessaging.onMessageOpenedApp.map(_message),
    _taps.stream,
  ).stream;

  @override
  Future<PushMessage?> launchMessage() async {
    final remote = await FirebaseMessaging.instance.getInitialMessage();
    if (remote != null) return _message(remote);
    final local = await _local.getNotificationAppLaunchDetails();
    final data = object(decoded(local?.notificationResponse?.payload));
    return local?.didNotificationLaunchApp == true && data.isNotEmpty
        ? PushMessage(data: data)
        : null;
  }

  @override
  Future<void> show(PushMessage message) => _local.show(
    id: _id++,
    title: message.title,
    body: message.body,
    payload: jsonEncode(message.data),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_telvox',
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );

  @override
  // ignore: deprecated_member_use
  Future<void> forget() => FirebaseMessaging.instance.deleteToken();
}

/// Two streams as one, without adding a package for it.
class StreamGroupMerge<T> {
  StreamGroupMerge(Stream<T> a, Stream<T> b) {
    late StreamSubscription<T> first, second;
    _controller = StreamController<T>(
      onListen: () {
        first = a.listen(_controller.add);
        second = b.listen(_controller.add);
      },
      onCancel: () async {
        await first.cancel();
        await second.cancel();
      },
    );
  }
  late final StreamController<T> _controller;
  Stream<T> get stream => _controller.stream;
}
