import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/config/app_config.dart';
import 'api.dart';
import 'call_push.dart';
import 'crash_reports.dart';
import 'notification_sound.dart';

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
  Future<void> show(PushMessage message, NotificationSound sound);

  /// Makes [sound] the one new messages play from now on.
  Future<void> useSound(NotificationSound sound);
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
    // iPhone calls ring through Apple's VoIP push, which needs neither
    // Firebase nor permission to show notifications.
    unawaited(session.callPush.registerVoip());
    final transport = _transport;
    if (transport == null || !session.signedIn) return;
    if (!_started) {
      try {
        if (!await transport.start()) return;
      } catch (_) {
        return;
      }
      _started = true;
      await transport.useSound(session.notificationSound.value);
      _subscriptions
        ..add(transport.tokenRefresh.listen(_register))
        ..add(transport.foreground.listen(_foreground))
        ..add(transport.opened.listen(_open));
      final launch = await transport.launchMessage();
      if (launch != null) _open(launch);
    }
    await _register(await transport.token());
  }

  /// Tells the server where this phone gets pushes and which sound its new
  /// messages ring with, so pushes posted while the app is closed use the
  /// sound's channel (`messages_<sound>`) too.
  Future<void> _register(String? token) async {
    if (token == null || token.isEmpty || !session.signedIn) return;
    final sound = session.notificationSound.value;
    final registration = '$token|${sound.name}';
    if (registration == _registered) return;
    try {
      await session.api.request(
        'me/push-token',
        method: 'PUT',
        data: {'token': token, 'provider': 'fcm', 'sound': sound.serverName},
      );
      _registered = registration;
      _token = token;
    } catch (_) {
      // Retried on the next sign-in, number switch, token refresh or sound.
    }
  }

  String? _token;

  /// Nothing to announce for the customer whose chat is on screen, whether
  /// it is their shared-inbox chat or one of their ticket conversations.
  void _foreground(PushMessage message) {
    // Calls ring an open app over the websocket; a push only stops a ring.
    final type = message.data['type'];
    if (type == 'call' || type == 'call_cancel') {
      if (type == 'call_cancel') unawaited(showCallFromPush(message.data));
      return;
    }
    // Whatever it says, the chat it is about is fetched onto the phone now,
    // so opening it from the notification shows the message at once.
    unawaited(session.conversations.arrived(message.data));
    final contact = message.contactKey;
    if (contact != null && session.visibleContacts.contains(contact)) return;
    _transport?.show(message, session.notificationSound.value);
  }

  /// A new sound applies once push has started; before then, start uses it.
  /// The channel is made before the server hears of it, so a push for the
  /// new sound never names a channel the phone does not have yet.
  Future<void> useSound(NotificationSound sound) async {
    if (!_started) return;
    try {
      await _transport?.useSound(sound);
    } catch (_) {
      // Shown pushes keep the previous sound until the next start.
    }
    await _register(_token);
  }

  void _open(PushMessage message) {
    if (message.conversation == null) return;
    session.openFromPush(message.data);
  }

  /// Signing out: the server forgets the token with the device; drop it here
  /// too so a different account on this phone gets a fresh one.
  Future<void> disable() async {
    _registered = null;
    _token = null;
    session.callPush.forgetVoip();
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
    await startFirebase();
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
    try {
      await installIosSounds();
    } catch (_) {
      // Without them an iPhone plays its default sound.
    }
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

  /// The channel new messages ring on with [sound]: one of the app's own,
  /// or the server's [channel] for the phone's default sound. The server's
  /// channel also carries the notifications it posts while the app is
  /// closed for a phone that picked the default.
  static AndroidNotificationChannel soundChannel(NotificationSound sound) {
    final resource = sound.resource;
    if (resource == null) return channel;
    return AndroidNotificationChannel(
      sound.channelId,
      'New messages',
      description: 'New customer messages, with the ${sound.label} sound',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound(resource),
    );
  }

  @override
  Future<void> useSound(NotificationSound sound) async {
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await android.createNotificationChannel(soundChannel(sound));
    // One "New messages" entry in the phone's settings, not one per sound.
    // The server's own channel always stays.
    for (final other in NotificationSound.values) {
      if (other != sound && !other.isSystem) {
        await android.deleteNotificationChannel(channelId: other.channelId);
      }
    }
  }

  @override
  Future<void> show(PushMessage message, NotificationSound sound) {
    final ring = soundChannel(sound);
    return _local.show(
      id: _id++,
      title: message.title,
      body: message.body,
      payload: jsonEncode(message.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ring.id,
          ring.name,
          channelDescription: ring.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_telvox',
          sound: ring.sound,
        ),
        iOS: DarwinNotificationDetails(
          sound: sound.resource == null ? null : '${sound.resource}.wav',
        ),
      ),
    );
  }

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
