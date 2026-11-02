import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'api.dart';

/// A customer's call reaching a phone whose app is closed or in the
/// background: the server sends a data-only push (`type: call`), shown here as
/// Android's full-screen incoming call with the phone's ringtone, and
/// `type: call_cancel` once it was answered elsewhere, moved on or missed.
///
/// Runs in Firebase's background isolate, so it touches nothing but the
/// system call UI; answering happens in the app, see [CallPushBridge].
@pragma('vm:entry-point')
Future<void> backgroundCallPush(RemoteMessage message) async {
  final data = Map<String, dynamic>.from(message.data);
  await showCallFromPush(data);
  if (data['type'] == 'call') await _declineWhileClosed(data);
}

/// Decline on the incoming-call screen of a closed app: the app is not
/// running to tell the server, so this isolate does — with the sign-in the
/// app keeps in secure storage — and the call moves on to the other agents
/// at once rather than after the ring timeout.
Future<void> _declineWhileClosed(Map<String, dynamic> data) async {
  final id = '${data['call_id'] ?? ''}';
  final uuid = callUuid(id);
  final declined = Completer<bool>();
  StreamSubscription<CallEvent?>? events;
  try {
    events = FlutterCallkitIncoming.onEvent.listen((event) {
      final same = switch (event) {
        CallEventActionCallDecline(:final callKitParams) =>
          callKitParams.id == uuid,
        CallEventActionCallAccept(:final callKitParams) =>
          callKitParams.id == uuid,
        CallEventActionCallEnded(:final callKitParams) =>
          callKitParams.id == uuid,
        CallEventActionCallTimeout(:final id) => id == uuid,
        _ => false,
      };
      if (same && !declined.isCompleted) {
        declined.complete(event is CallEventActionCallDecline);
      }
    });
    final expires = DateTime.tryParse('${data['expires_at'] ?? ''}');
    final wait = expires == null
        ? const Duration(seconds: 35)
        : expires.difference(DateTime.now()) + const Duration(seconds: 5);
    final declinedHere = await declined.future.timeout(
      wait.isNegative ? Duration.zero : wait,
      onTimeout: () => false,
    );
    if (!declinedHere) return;
    final api = MobileApi();
    final saved = object(
      decoded(
        await SecureSessionStore().read(
          'session.${Uri.parse(api.dio.options.baseUrl).host}',
        ),
      ),
    );
    final token = saved['token'];
    if (token == null || '$token'.isEmpty) return;
    api
      ..token = '$token'
      ..wabaId = number(data['waba_user_id']) ?? number(saved['waba_id']);
    await api.post('inbox/calls/decline', {'call_id': id});
  } catch (_) {
    /* The ring timeout moves the call on. */
  } finally {
    await events?.cancel();
  }
}

Future<void> showCallFromPush(Map<String, dynamic> data) async {
  final id = '${data['call_id'] ?? ''}';
  if (id.isEmpty) return;
  try {
    switch (data['type']) {
      case 'call':
        final name = '${data['contact_name'] ?? ''}'.trim();
        final phone = '${data['contact_phone'] ?? ''}'.trim();
        final expires = DateTime.tryParse('${data['expires_at'] ?? ''}');
        final ring = expires == null
            ? 30000
            : expires
                  .difference(DateTime.now())
                  .inMilliseconds
                  .clamp(5000, 60000);
        await FlutterCallkitIncoming.showCallkitIncoming(
          CallKitParams(
            id: callUuid(id),
            nameCaller: name.isNotEmpty
                ? name
                : (phone.isNotEmpty ? '+$phone' : 'WhatsApp caller'),
            appName: 'Telvox Chat',
            handle: phone.isEmpty ? null : '+$phone',
            type: 0,
            duration: ring,
            extra: data,
            // The server sends its own missed-call notification.
            missedCallNotification: const NotificationParams(
              showNotification: false,
            ),
            android: const AndroidParams(
              isCustomNotification: true,
              isShowLogo: false,
              ringtonePath: 'system_ringtone_default',
              backgroundColor: '#14432C',
              actionColor: '#25A35A',
              textColor: '#FFFFFF',
              incomingCallNotificationChannelName: 'Incoming calls',
              missedCallNotificationChannelName: 'Missed calls',
              isShowFullLockedScreen: true,
              isImportant: true,
              textAccept: 'Accept',
              textDecline: 'Decline',
            ),
          ),
        );
      case 'call_cancel':
        await FlutterCallkitIncoming.endCall(callUuid(id));
    }
  } catch (e) {
    debugPrint('Call push not shown: $e');
  }
}

/// The system call UI needs a UUID; WhatsApp call ids are not one. The same
/// call id always maps to the same UUID, so a cancel finds its ring.
String callUuid(String callId) {
  final hex = StringBuffer();
  for (var seed = 0; seed < 4; seed++) {
    var h = (0x811c9dc5 ^ (seed * 0x9e3779b9)) & 0xffffffff;
    for (final unit in callId.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    hex.write(h.toRadixString(16).padLeft(8, '0'));
  }
  final s = hex.toString();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-4${s.substring(13, 16)}'
      '-a${s.substring(17, 20)}-${s.substring(20, 32)}';
}

/// Turns the system call UI's buttons into the app's call flow: Accept opens
/// the app and answers through [MobileSession.answerFromPush]; Decline hands
/// the call back to the other agents.
class CallPushBridge {
  CallPushBridge(this.session);
  final MobileSession session;
  StreamSubscription<CallEvent?>? _events;

  void start() {
    try {
      _events ??= FlutterCallkitIncoming.onEvent.listen(_event);
    } catch (_) {
      return; // No plugin (tests, desktop).
    }
    unawaited(_acceptedWhileClosed());
  }

  /// Accept on a closed app launches it before this listens: pick the call up.
  Future<void> _acceptedWhileClosed() async {
    try {
      for (final call in await FlutterCallkitIncoming.activeCalls()) {
        final extra = call.extra;
        if (call.isAccepted && extra != null) {
          session.answerFromPush(Map<String, dynamic>.from(extra));
        }
      }
    } catch (_) {
      /* Nothing to resume. */
    }
  }

  void _event(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        final extra = callKitParams.extra;
        if (extra != null) {
          session.answerFromPush(Map<String, dynamic>.from(extra));
        }
      case CallEventActionCallDecline(:final callKitParams):
        final extra = callKitParams.extra;
        if (extra != null) {
          unawaited(session.calls.declinePushed('${extra['call_id']}'));
        }
      case CallEventActionCallEnded(:final callKitParams):
        final id = '${callKitParams.extra?['call_id'] ?? ''}';
        if (id.isNotEmpty && session.calls.callId == id) {
          unawaited(session.calls.hangUp());
        }
      default:
        break;
    }
  }

  void dispose() => _events?.cancel();
}

/// The system call UI, quietly absent where the plugin is (tests, desktop).
Future<void> callkit(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    /* No system call UI here. */
  }
}

/// Android 14 asks the user before an app may show a full-screen incoming
/// call over the lock screen. Asked once, with the reason, the first time the
/// signed-in home opens; without it a call still rings as a notification.
Future<void> askForFullScreenCalls(
  BuildContext context,
  SessionStore store,
) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    if (await store.read('asked_full_screen_calls') != null) return;
    if (await FlutterCallkitIncoming.canUseFullScreenIntent()) return;
    await store.write('asked_full_screen_calls', '1');
    if (!context.mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show incoming WhatsApp calls'),
        content: const Text(
          'Allow Telvox Chat to show customers’ calls on the full screen, '
          'even when the phone is locked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow == true) {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    }
  } catch (_) {
    /* No system call UI here. */
  }
}
