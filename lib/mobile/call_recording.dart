import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Where a call's recording is written while it records. Replaced in tests.
Future<String> Function() callRecordingFolder = () async =>
    '${(await getTemporaryDirectory()).path}/call-recordings';

/// A recorded call's two sides, this phone's microphone and the customer's
/// voice (recorded to separate files), as one AAC recording, the way the web
/// inbox records a call. Null when they cannot be mixed. Replaced in tests.
@visibleForTesting
Future<File?> Function(String microphone, String customer, String out)
mixCallRecording = (microphone, customer, out) async {
  try {
    final path = await const MethodChannel('telvox/video')
        .invokeMethod<String>('mixAudio', {
          'inputs': [microphone, customer],
          'out': out,
        });
    return path == null ? null : File(path);
  } catch (_) {
    return null;
  }
};

/// The recording to upload: the two sides mixed, or, where mixing fails, the
/// larger of the two (better one voice than none). Null with nothing to send.
Future<File?> callRecordingFile(
  String microphone,
  String customer,
  String out,
) async {
  final mixed = await mixCallRecording(microphone, customer, out);
  if (mixed != null && await mixed.exists() && await mixed.length() > 0) {
    return mixed;
  }
  File? best;
  var size = 0;
  for (final path in [microphone, customer]) {
    final file = File(path);
    if (!await file.exists()) continue;
    final length = await file.length();
    if (length > size) {
      best = file;
      size = length;
    }
  }
  return best;
}
