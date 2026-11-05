import 'dart:io';
import 'dart:math' as math;

import 'package:telvox_chat_mobile_app/mobile/media_quality.dart';

/// The phone's encoders, without the phone: a photo comes back as it was
/// (or as [photoBytes] in turn, one per attempt), a video as it was, and
/// every call is noted.
class FakeCompressor implements MediaCompressor {
  FakeCompressor({this.size = (4000, 3000), this.info, this.photoBytes});

  /// The picked photo's width and height; null where it cannot be read.
  final (int, int)? size;

  /// What the picked video is; null where the phone cannot say.
  final VideoInfo? info;

  /// How large each attempt at a photo comes out, in order.
  final List<int>? photoBytes;
  final calls = <String>[];
  int _attempt = 0;

  @override
  Future<(int, int)?> photoSize(String path) async => size;

  @override
  Future<File> photo(
    String path, {
    required int longest,
    required int quality,
  }) async {
    calls.add('photo $longest $quality');
    final sizes = photoBytes;
    if (sizes == null) return File(path);
    final bytes = sizes[math.min(_attempt++, sizes.length - 1)];
    final out = File(
      '${Directory.systemTemp.path}/fake-photo-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await out.writeAsBytes(List.filled(bytes, 1), flush: true);
    return out;
  }

  @override
  Future<VideoInfo?> probeVideo(String path) async => info;

  @override
  Future<File> video(
    String path,
    VideoPlan plan, {
    void Function(double done)? progress,
  }) async {
    calls.add('video ${plan.quality.name} ${plan.shortSide}');
    progress?.call(.5);
    progress?.call(1);
    return File(path);
  }
}
