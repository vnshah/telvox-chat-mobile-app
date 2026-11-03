import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Files another app shared to Telvox Chat through the phone's share sheet.
/// A seam so tests need no platform channel.
abstract class SharedFiles {
  /// What the app was opened with, if it was opened by a share.
  Future<List<XFile>> initial();

  /// Shares that arrive while the app is already running.
  Stream<List<XFile>> get arriving;

  /// Forgets the share, so it is not offered again on the next launch.
  Future<void> done();
}

/// Android's share sheet (intent filters on MainActivity) and iOS's share
/// extension, through receive_sharing_intent. The files are copies the plugin
/// keeps in this app's own cache, so nothing outside the app is read later.
class DeviceSharedFiles implements SharedFiles {
  static List<XFile> _files(List<SharedMediaFile> shared) => [
    for (final f in shared)
      // Shared text and links are not files to send.
      if (f.type != SharedMediaType.text && f.type != SharedMediaType.url)
        XFile(f.path, mimeType: f.mimeType),
  ];

  @override
  Future<List<XFile>> initial() async =>
      _files(await ReceiveSharingIntent.instance.getInitialMedia());

  @override
  Stream<List<XFile>> get arriving =>
      ReceiveSharingIntent.instance.getMediaStream().map(_files);

  @override
  Future<void> done() => ReceiveSharingIntent.instance.reset();
}

/// Replaced in tests.
SharedFiles sharedFiles = DeviceSharedFiles();

/// Holds a share until the app can act on it: signed in, a number chosen,
/// the home screen up. [pending] is what is waiting; [take] hands it over.
class ShareIntake {
  ShareIntake([SharedFiles? source]) : _source = source ?? sharedFiles;
  final SharedFiles _source;
  final pending = ValueNotifier<List<XFile>?>(null);
  StreamSubscription<List<XFile>>? _arriving;

  Future<void> start() async {
    _arriving = _source.arriving.listen(_offer, onError: (_) {});
    try {
      _offer(await _source.initial());
    } catch (_) {
      // No share, or the platform cannot say: nothing to do.
    }
  }

  void _offer(List<XFile> files) {
    if (files.isNotEmpty) pending.value = files;
  }

  /// The waiting share, once; the next share replaces it.
  List<XFile>? take() {
    final files = pending.value;
    pending.value = null;
    if (files != null) unawaited(_source.done().catchError((_) {}));
    return files;
  }

  void dispose() {
    _arriving?.cancel();
    pending.dispose();
  }
}
