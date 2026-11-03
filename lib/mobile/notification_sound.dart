import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// What a new message sounds like on this phone. The pick is the user's and
/// stays on the phone (MobileSession.notificationSound).
enum NotificationSound {
  /// The phone's own notification sound, for anyone who wants none of ours.
  system('Default'),
  tap('Tap'),
  pebble('Pebble'),
  chime('Chime');

  const NotificationSound(this.label);
  final String label;

  bool get isSystem => this == system;

  /// The Android raw resource the channel plays (android/app/src/main/res/raw),
  /// and the app's own copy in assets/sounds; none for the phone's default.
  String? get resource => isSystem ? null : 'telvox_$name';
  String? get asset => isSystem ? null : 'assets/sounds/$resource.wav';

  /// Android fixes a channel's sound when the channel is made, so each sound
  /// has a channel of its own. The phone's default uses the server's own
  /// channel, `inbox`, which rings with the system sound.
  String get channelId => isSystem ? 'inbox' : 'messages_$name';

  /// What the server stores for this phone (config('mobile.push.sounds'));
  /// null leaves it on `inbox` and the system sound.
  String? get serverName => isSystem ? null : name;

  static const fallback = NotificationSound.tap;

  static NotificationSound from(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => fallback);
}

/// iPhones play a notification's sound from the app's Library/Sounds folder
/// (or its bundle), for the server's pushes as well as the app's own. The
/// app's copies are put there once, so no Xcode step is needed for them.
Future<void> installIosSounds() async {
  if (kIsWeb || !Platform.isIOS) return;
  final home = Platform.environment['HOME'];
  if (home == null) return;
  final folder = await Directory('$home/Library/Sounds')
      .create(recursive: true);
  for (final sound in NotificationSound.values) {
    final asset = sound.asset;
    if (asset == null) continue;
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    final file = File('${folder.path}/${sound.resource}.wav');
    if (await file.exists() && await file.length() == bytes.length) continue;
    await file.writeAsBytes(bytes, flush: true);
  }
}

/// Plays a sound once while the user is choosing, as the system's own sound
/// picker does; picking another stops the one still playing. On Android it
/// plays as a notification would, at the notification volume, so what the
/// user hears here is what a new message will sound like.
class SoundPreview {
  static const _android = MethodChannel('telvox/notification_sound');
  VideoPlayerController? _player;

  bool get _native => !kIsWeb && Platform.isAndroid;

  Future<void> play(NotificationSound sound) async {
    await stop();
    try {
      if (_native) {
        await _android.invokeMethod('preview', sound.resource);
        return;
      }
      final asset = sound.asset;
      if (asset == null) return;
      final player = _player = VideoPlayerController.asset(asset);
      await player.initialize();
      if (_player != player) return;
      await player.play();
    } catch (_) {
      // A preview that cannot play changes nothing about the choice.
    }
  }

  Future<void> stop() async {
    final player = _player;
    _player = null;
    try {
      if (_native) await _android.invokeMethod('stop');
      await player?.dispose();
    } catch (_) {}
  }
}
