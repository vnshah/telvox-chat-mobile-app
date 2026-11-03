import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// "1:05" for a recording's length.
String recordingClock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// The microphone's level as bars, newest on the right, as WhatsApp draws a
/// recording while it is made.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform(this.levels, {super.key, this.color = T.secondary});

  /// 0 (silence) to 1, oldest first.
  final List<double> levels;
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(double.infinity, 30),
    painter: _WaveformPainter(levels, color),
  );
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.levels, this.color);
  final List<double> levels;
  final Color color;
  static const bar = 3.0, gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = bar
      ..strokeCap = StrokeCap.round;
    final fits = (size.width / (bar + gap)).floor();
    final shown = levels.length > fits
        ? levels.sublist(levels.length - fits)
        : levels;
    final mid = size.height / 2;
    for (var i = 0; i < shown.length; i++) {
      final x = size.width - (shown.length - i) * (bar + gap) + bar / 2;
      final half = math.max(1.5, shown[i] * size.height / 2);
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.levels.length != levels.length ||
      (levels.isNotEmpty && old.levels.last != levels.last);
}

/// The padlock above the held microphone: drag up to it to lock the
/// recording and let go. It closes as the finger nears it.
class LockTab extends StatelessWidget {
  const LockTab({super.key, required this.progress, required this.hint});

  /// 0 at the microphone, 1 when the recording locks.
  final double progress;

  /// "Slide up to lock recording", shown once the hold has lasted a moment.
  final bool hint;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AnimatedOpacity(
        opacity: hint && progress < .3 ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Container(
          margin: const EdgeInsets.only(right: 8, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xE6302A25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Slide up to lock recording',
            style: TextStyle(fontSize: 12.5, color: Colors.white),
          ),
        ),
      ),
      Container(
        key: const ValueKey('voice-lock'),
        width: 40,
        height: 92 - progress * 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Icon(
              progress > .85 ? Icons.lock : Icons.lock_open_outlined,
              size: 20,
              color: progress > .85 ? T.green : T.secondary,
            ),
            if (progress < .6)
              Transform.translate(
                offset: Offset(0, -progress * 10),
                child: const Icon(
                  Icons.keyboard_arrow_up,
                  size: 20,
                  color: T.muted,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// A locked recording: its length and live waveform, then Delete, Pause or
/// Resume, and Send — WhatsApp's hands-free recording panel.
class LockedRecordingPanel extends StatelessWidget {
  const LockedRecordingPanel({
    super.key,
    required this.elapsed,
    required this.levels,
    required this.paused,
    required this.onDelete,
    required this.onPause,
    required this.onSend,
  });
  final Duration elapsed;
  final List<double> levels;
  final bool paused;
  final VoidCallback onDelete, onPause, onSend;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 10, 4, 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: 6),
            Text(
              recordingClock(elapsed),
              key: const ValueKey('voice-clock'),
              semanticsLabel: 'Recorded ${recordingClock(elapsed)}',
              style: const TextStyle(fontSize: 17, color: T.ink),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: LiveWaveform(
                levels,
                color: paused ? T.muted : T.secondary,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Material(
              color: const Color(0xFFF6E0E7),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Delete recording',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: T.danger),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: T.incoming,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: onPause,
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          paused ? Icons.mic : Icons.pause,
                          color: paused ? T.danger : T.ink,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          paused ? 'Resume' : 'Pause',
                          style: const TextStyle(fontSize: 15, color: T.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: T.green,
              shape: const CircleBorder(),
              elevation: 1,
              child: IconButton(
                tooltip: 'Send voice note',
                onPressed: onSend,
                icon: const Icon(Icons.send, color: Colors.white, size: 21),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// WhatsApp's cancel: the red microphone jumps, turns over and drops into a
/// bin that opens beside the message box, which then closes and goes.
class BinDrop extends StatelessWidget {
  const BinDrop(this.animation, {super.key});
  final Animation<double> animation;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        // Up for the first 35%, then down into the bin by 75%.
        final rise = Curves.easeOut.transform((t / .35).clamp(0, 1));
        final fall = Curves.easeIn.transform(((t - .35) / .4).clamp(0, 1));
        final y = -56 * rise + 62 * fall;
        final bin = t < .3
            ? 0.0
            : t < .45
            ? (t - .3) / .15
            : t > .85
            ? (1 - t) / .15
            : 1.0;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: bin,
              child: const Icon(
                Icons.delete,
                key: ValueKey('voice-bin'),
                color: T.secondary,
                size: 24,
              ),
            ),
            if (t < .75)
              Transform.translate(
                offset: Offset(0, y),
                child: Transform.rotate(
                  angle: math.pi * rise,
                  child: const Icon(Icons.mic, color: T.danger, size: 22),
                ),
              ),
          ],
        );
      },
    ),
  );
}
