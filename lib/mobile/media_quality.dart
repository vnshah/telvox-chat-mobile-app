import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'media.dart';

/// How photos and videos are sent, as WhatsApp offers it: Standard by
/// default (smaller, quicker), or HD (sharper, larger), chosen per batch.
enum MediaQuality { standard, hd }

/// WhatsApp Business takes videos up to 16 MB and photos up to 5 MB, HD or
/// not, measured on the file it receives. A little is kept back for the
/// container and the upload's own wrapping.
const maxVideoBytes = 15 * 1024 * 1024;
const maxPhotoBytes = 4800 * 1024;

/// What a video is: its length, its picture as it is shown (turned upright),
/// and its size.
class VideoInfo {
  const VideoInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.bytes,
    this.bitrate,
  });
  final Duration duration;
  final int width, height, bytes;

  /// Bits a second of the original, when the file says.
  final int? bitrate;

  int get shortSide => math.min(width, height);
}

/// How one quality encodes video: WhatsApp sends Standard at 480p and HD at
/// 720p. The bitrates keep detail at those sizes; the floor is where a
/// picture starts to break up, below which a video is too long to fit.
class VideoSpec {
  const VideoSpec(this.shortSide, this.bitrate, this.audioBitrate, this.floor);
  final int shortSide, bitrate, audioBitrate, floor;

  static const standard = VideoSpec(480, 1200000, 96000, 450000);
  static const hd = VideoSpec(720, 3500000, 128000, 1200000);

  static VideoSpec of(MediaQuality quality) =>
      quality == MediaQuality.hd ? hd : standard;
}

/// What a video will be encoded as: its short side, bitrates, and about how
/// large the result will be. [quality] is the one it was planned at, which
/// is Standard when an HD video only fits as Standard.
class VideoPlan {
  const VideoPlan({
    required this.quality,
    required this.shortSide,
    required this.videoBitrate,
    required this.audioBitrate,
    required this.estimate,
  });
  final MediaQuality quality;
  final int shortSide, videoBitrate, audioBitrate, estimate;
}

/// The plan for [video] at [wanted]: the quality's size and bitrate, the
/// bitrate lowered only as far as the video's length needs to fit under
/// [maxVideoBytes]. HD that cannot keep its floor falls back to Standard;
/// null when even Standard cannot (the video is too long to send).
VideoPlan? planVideo(VideoInfo video, MediaQuality wanted) {
  final seconds = math.max(1, video.duration.inMilliseconds) / 1000;
  for (final quality in [
    wanted,
    if (wanted == MediaQuality.hd) MediaQuality.standard,
  ]) {
    final spec = VideoSpec.of(quality);
    // Never larger than the original, and even, as encoders need.
    final side = math.min(spec.shortSide, video.shortSide) ~/ 2 * 2;
    // 3% for the MP4 container's own bytes.
    final fits = (maxVideoBytes * 8 * .97 / seconds - spec.audioBitrate)
        .floor();
    var bitrate = math.min(spec.bitrate, fits);
    // A small original already this light is not given more to spend.
    final original = video.bitrate;
    if (original != null && original > 0) {
      bitrate = math.min(bitrate, math.max(spec.floor, original));
    }
    if (bitrate < spec.floor) continue;
    return VideoPlan(
      quality: quality,
      shortSide: side,
      videoBitrate: bitrate,
      audioBitrate: spec.audioBitrate,
      estimate: ((bitrate + spec.audioBitrate) * seconds / 8 * 1.03).round(),
    );
  }
  return null;
}

/// The longest video each quality can send at its floor, for the message
/// when one is too long.
Duration longestVideo(MediaQuality quality) {
  final spec = VideoSpec.of(quality);
  return Duration(
    seconds: (maxVideoBytes * 8 * .97 / (spec.floor + spec.audioBitrate))
        .floor(),
  );
}

/// How a photo is re-encoded at each quality, best first: the longest side
/// and JPEG quality. WhatsApp sends Standard around 2048 px and HD near the
/// camera's own size; the later steps are only taken when a photo is still
/// over [maxPhotoBytes].
const photoSteps = <MediaQuality, List<(int, int)>>{
  MediaQuality.standard: [(2048, 80), (2048, 70), (1600, 70)],
  MediaQuality.hd: [(4096, 90), (4096, 85), (3072, 85), (2560, 80), (2048, 80)],
};

/// About how large a photo of [width] × [height] will be at [quality]: JPEG
/// at these settings runs to roughly these bytes a pixel.
int estimatePhoto(int width, int height, MediaQuality quality) {
  final (longest, _) = photoSteps[quality]!.first;
  final long = math.max(width, height), short = math.min(width, height);
  final scale = long > longest ? longest / long : 1.0;
  final pixels = (long * scale) * (short * scale);
  final perPixel = quality == MediaQuality.hd ? .24 : .13;
  return math.min(pixels * perPixel, maxPhotoBytes.toDouble()).round();
}

/// The device's encoders, behind a seam so tests need none.
abstract class MediaCompressor {
  /// A photo's width and height, if it can be read without decoding it.
  Future<(int, int)?> photoSize(String path);

  /// [path] as a JPEG at most [longest] px on its long side, at [quality].
  Future<File> photo(String path, {required int longest, required int quality});

  /// What a video is, or null where the phone cannot say (no encoder here).
  Future<VideoInfo?> probeVideo(String path);

  /// [path] re-encoded by [plan], as H.264 and AAC in an MP4 WhatsApp plays.
  Future<File> video(
    String path,
    VideoPlan plan, {
    void Function(double done)? progress,
  });
}

/// Replaced in tests.
MediaCompressor mediaCompressor = DeviceMediaCompressor();

/// Photos through flutter_image_compress (the phone's own JPEG encoder, which
/// also turns HEIC upright into JPEG); videos through Android's Media3
/// Transformer (see VideoCompressor.kt), hardware H.264 and AAC.
class DeviceMediaCompressor implements MediaCompressor {
  static const _video = MethodChannel('telvox/video');
  final _progress = <String, void Function(double)>{};
  int _next = 0;

  DeviceMediaCompressor() {
    _video.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        _progress['${args['id']}']?.call(
          ((args['value'] as num?) ?? 0).toDouble(),
        );
      }
    });
  }

  Future<String> _target(String extension) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/outgoing');
    await dir.create(recursive: true);
    return '${dir.path}/${DateTime.now().microsecondsSinceEpoch}-${_next++}.$extension';
  }

  @override
  Future<(int, int)?> photoSize(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (descriptor.width, descriptor.height);
      descriptor.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<File> photo(
    String path, {
    required int longest,
    required int quality,
  }) async {
    final size = await photoSize(path);
    // The encoder scales a photo until its shorter side meets the smaller
    // of these, so both are the short side the long side's limit gives;
    // that holds whichever way up the photo is stored.
    var short = (longest * .75).round();
    if (size != null) {
      final (w, h) = size;
      final long = math.max(w, h), s = math.min(w, h);
      short = long <= longest ? s : (longest * s / long).round();
    }
    final out = await FlutterImageCompress.compressAndGetFile(
      path,
      await _target('jpg'),
      minWidth: short,
      minHeight: short,
      quality: quality,
      format: CompressFormat.jpeg,
    );
    if (out == null) {
      throw const ApiFailure('This photo could not be prepared to send.');
    }
    return File(out.path);
  }

  @override
  Future<VideoInfo?> probeVideo(String path) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final info = Map<String, Object?>.from(
        await _video.invokeMethod('probe', {'path': path}) as Map,
      );
      int at(String key) => (info[key] as num?)?.toInt() ?? 0;
      final rotated = at('rotation') % 180 == 90;
      return VideoInfo(
        duration: Duration(milliseconds: at('duration')),
        width: rotated ? at('height') : at('width'),
        height: rotated ? at('width') : at('height'),
        bytes: at('bytes'),
        bitrate: at('bitrate') > 0 ? at('bitrate') : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<File> video(
    String path,
    VideoPlan plan, {
    void Function(double done)? progress,
  }) async {
    final id = '${_next++}';
    if (progress != null) _progress[id] = progress;
    try {
      final out = await _target('mp4');
      await _video.invokeMethod('compress', {
        'id': id,
        'path': path,
        'out': out,
        'shortSide': plan.shortSide,
        'videoBitrate': plan.videoBitrate,
        'audioBitrate': plan.audioBitrate,
      });
      return File(out);
    } on PlatformException catch (e) {
      throw ApiFailure(
        'This video could not be prepared to send'
        '${e.message == null ? '' : ' (${e.message})'}.',
      );
    } finally {
      _progress.remove(id);
    }
  }
}

/// [attachment] as it will be sent at [quality]: a photo re-encoded until it
/// is within WhatsApp's 5 MB, a video re-encoded to fit 16 MB; anything else
/// as it is. [progress] follows a video's encoding, 0 to 1.
Future<Attachment> prepareMedia(
  Attachment attachment,
  MediaQuality quality, {
  void Function(double done)? progress,
  MediaCompressor? compressor,
}) async {
  final codec = compressor ?? mediaCompressor;
  final path = attachment.file.path;
  final base = attachment.name.contains('.')
      ? attachment.name.substring(0, attachment.name.lastIndexOf('.'))
      : attachment.name;
  switch (attachment.kind) {
    case 'image':
      for (final (longest, q) in photoSteps[quality]!) {
        final out = await codec.photo(path, longest: longest, quality: q);
        final size = await out.length();
        if (size > 0 && size <= maxPhotoBytes) {
          return Attachment(
            await _named(out, path, '$base.jpg', 'image/jpeg'),
            'image',
            size,
            'image/jpeg',
          );
        }
      }
      throw const ApiFailure(
        'This photo is too large for WhatsApp, even made smaller.',
      );
    case 'video':
      final info = await codec.probeVideo(path);
      if (info == null) {
        // No encoder on this phone: the original, if WhatsApp takes it.
        if (attachment.size <= 16 * 1024 * 1024) return attachment;
        throw const ApiFailure(
          'WhatsApp accepts videos up to 16 MB. Choose a shorter one.',
        );
      }
      final plan = planVideo(info, quality);
      if (plan == null) throw ApiFailure(tooLongMessage());
      final out = await codec.video(path, plan, progress: progress);
      final size = await out.length();
      if (size <= 0 || size > 16 * 1024 * 1024) {
        throw const ApiFailure('This video could not be made small enough.');
      }
      return Attachment(
        await _named(out, path, '$base.mp4', 'video/mp4'),
        'video',
        size,
        'video/mp4',
      );
    default:
      return attachment;
  }
}

/// [made] under the name it is sent with ([name]: the original's, in the
/// new format), as a file's name on the phone is its path's last part.
/// Each goes in a folder of its own so two IMG_1.jpg never meet; one the
/// encoder left as [original] is copied, never moved.
Future<XFile> _named(
  File made,
  String original,
  String name,
  String mime,
) async {
  final dir = Directory(
    '${made.parent.path}/${DateTime.now().microsecondsSinceEpoch}',
  );
  await dir.create(recursive: true);
  final target = '${dir.path}/$name';
  final out = made.path == original
      ? await made.copy(target)
      : await made.rename(target);
  return XFile(out.path, mimeType: mime);
}

/// About how large one photo or video will be at each quality, as the
/// quality choice shows it. [sizes] is null where that cannot be told;
/// [tooLong] is a video WhatsApp's 16 MB cannot hold at any quality.
class MediaEstimate {
  const MediaEstimate(this.sizes, {this.tooLong = false});
  final Map<MediaQuality, int>? sizes;
  final bool tooLong;

  /// Each quality's total over [estimates]; null if any cannot be told.
  static Map<MediaQuality, int>? total(Iterable<MediaEstimate> estimates) {
    final totals = {for (final q in MediaQuality.values) q: 0};
    for (final e in estimates) {
      final sizes = e.sizes;
      if (sizes == null) return null;
      for (final q in MediaQuality.values) {
        totals[q] = totals[q]! + sizes[q]!;
      }
    }
    return totals;
  }
}

/// [attachment] as each quality would send it, without encoding anything.
Future<MediaEstimate> estimateMedia(
  Attachment attachment, {
  MediaCompressor? compressor,
}) async {
  final codec = compressor ?? mediaCompressor;
  final path = attachment.file.path;
  switch (attachment.kind) {
    case 'image':
      final size = await codec.photoSize(path);
      if (size == null) return const MediaEstimate(null);
      return MediaEstimate({
        for (final q in MediaQuality.values)
          // Re-encoding a small JPEG can only make it about this large.
          q: math.min(estimatePhoto(size.$1, size.$2, q), attachment.size),
      });
    case 'video':
      final info = await codec.probeVideo(path);
      if (info == null) {
        return MediaEstimate(null, tooLong: attachment.size > 16 * 1024 * 1024);
      }
      final plans = {
        for (final q in MediaQuality.values) q: planVideo(info, q),
      };
      if (plans.values.any((p) => p == null)) {
        return const MediaEstimate(null, tooLong: true);
      }
      return MediaEstimate({
        for (final q in MediaQuality.values) q: plans[q]!.estimate,
      });
    default:
      return MediaEstimate({
        for (final q in MediaQuality.values) q: attachment.size,
      });
  }
}

/// What to tell someone whose video is too long, with how long fits.
String tooLongMessage() {
  final longest = longestVideo(MediaQuality.standard);
  return 'This video is too long to send on WhatsApp. Videos up to about '
      '${longest.inMinutes} min ${longest.inSeconds % 60} s fit its 16 MB '
      'limit.';
}
