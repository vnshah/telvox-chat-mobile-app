import 'dart:math' as math;
import 'dart:typed_data';

/// A voice note's shape, read from the file itself without decoding it.
///
/// WhatsApp voice notes are Opus in an Ogg container, encoded at a variable
/// bit rate: a loud stretch takes larger packets than a pause. So the packet
/// sizes, bucketed across the note, draw its loudness over time, and the last
/// page's granule position gives its length.
class VoiceWaveform {
  const VoiceWaveform(this.bars, this.duration);

  /// Heights from 0 to 1, oldest first.
  final List<double> bars;
  final Duration duration;

  /// Null when [bytes] is not Ogg/Opus, so the caller draws a plain bar.
  static VoiceWaveform? read(Uint8List bytes, {int count = 32}) {
    final sizes = <int>[];
    var granule = 0, offset = 0, packet = 0;
    while (offset + 27 <= bytes.length) {
      if (bytes[offset] != 0x4f ||
          bytes[offset + 1] != 0x67 ||
          bytes[offset + 2] != 0x67 ||
          bytes[offset + 3] != 0x53) {
        break;
      }
      final segments = bytes[offset + 26];
      if (offset + 27 + segments > bytes.length) break;
      final position = ByteData.sublistView(
        bytes,
        offset + 6,
        offset + 14,
      ).getInt64(0, Endian.little);
      if (position > 0) granule = position;
      var body = 0;
      for (var k = 0; k < segments; k++) {
        final lace = bytes[offset + 27 + k];
        packet += lace;
        body += lace;
        // A lace under 255 ends the packet; 255 continues it on the next.
        if (lace < 255) {
          sizes.add(packet);
          packet = 0;
        }
      }
      offset += 27 + segments + body;
    }
    // The first two packets are the OpusHead and OpusTags headers.
    if (sizes.length < 3 || !_isOpus(bytes)) return null;
    final audio = sizes.sublist(2);
    final preSkip = bytes.length > 39 ? bytes[38] | (bytes[39] << 8) : 0;
    // Opus granule positions always count 48 kHz samples.
    final duration = Duration(
      microseconds: math.max(0, granule - preSkip) * 1000000 ~/ 48000,
    );
    final buckets = List<double>.generate(count, (i) {
      final from = i * audio.length ~/ count;
      final to = math.max(from + 1, (i + 1) * audio.length ~/ count);
      var sum = 0;
      for (var j = from; j < to && j < audio.length; j++) {
        sum += audio[j];
      }
      return sum / (to - from);
    });
    final low = buckets.reduce(math.min), high = buckets.reduce(math.max);
    return VoiceWaveform([
      for (final b in buckets)
        high == low ? .5 : .12 + .88 * ((b - low) / (high - low)),
    ], duration);
  }

  static bool _isOpus(Uint8List bytes) {
    const head = [0x4f, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]; // OpusHead
    if (bytes.length < 36) return false;
    for (var i = 0; i < head.length; i++) {
      if (bytes[28 + i] != head[i]) return false;
    }
    return true;
  }
}
