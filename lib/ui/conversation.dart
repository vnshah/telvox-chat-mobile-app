import 'package:flutter/material.dart';

export 'chat_message.dart' show MessageBubble, ProductArt, VoiceWave;
import 'theme.dart';

class SwipeReply extends StatefulWidget {
  const SwipeReply({super.key, required this.child, required this.onReply});
  final Widget child;

  /// Null while a message cannot be replied to yet (still sending): the row
  /// keeps its shape, so it is not rebuilt when it becomes repliable.
  final VoidCallback? onReply;
  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply> {
  double distance = 0;
  bool dragging = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragStart: widget.onReply == null
        ? null
        : (_) => setState(() => dragging = true),
    onHorizontalDragUpdate: widget.onReply == null
        ? null
        : (d) => setState(
            () => distance = (distance + d.delta.dx * .8).clamp(0, 60),
          ),
    onHorizontalDragEnd: widget.onReply == null
        ? null
        : (_) {
            if (distance >= 38) widget.onReply!();
            setState(() {
              dragging = false;
              distance = 0;
            });
          },
    onHorizontalDragCancel: widget.onReply == null
        ? null
        : () => setState(() {
            dragging = false;
            distance = 0;
          }),
    child: Stack(
      alignment: Alignment.centerLeft,
      children: [
        if (distance > 8)
          Opacity(
            opacity: (distance / 48).clamp(0, 1),
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: distance >= 38 ? T.selected : T.wash,
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                Icons.reply_rounded,
                color: T.green,
                size: 18,
              ),
            ),
          ),
        AnimatedContainer(
          duration: Duration(
            milliseconds: dragging || MediaQuery.disableAnimationsOf(context)
                ? 0
                : 140,
          ),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(distance, 0, 0),
          child: widget.child,
        ),
      ],
    ),
  );
}

class ChatWallpaper extends CustomPainter {
  const ChatWallpaper();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = T.chatWallpaper);
    // A faint trace of the Telvox motif, as WhatsApp's doodles sit on its
    // beige; the bubbles carry the contrast.
    final line = Paint()
      ..color = T.brass.withValues(alpha: .11)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var y = -24.0; y < size.height + 80; y += 108) {
      for (var x = -10.0; x < size.width + 80; x += 116) {
        canvas.save();
        canvas.translate(x + ((y ~/ 108).isEven ? 0 : 50), y);
        canvas.rotate(-.20);
        // Small chat, leaf and spark motifs echo the Telvox mark and earthy palette.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 8, 27, 19),
            const Radius.circular(6),
          ),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(15, 27)
            ..lineTo(13, 32)
            ..lineTo(22, 27),
          line,
        );
        canvas.drawLine(const Offset(15, 16), const Offset(28, 16), line);
        canvas.drawLine(const Offset(15, 21), const Offset(23, 21), line);
        canvas.drawPath(
          Path()
            ..moveTo(66, 69)
            ..quadraticBezierTo(43, 46, 72, 42)
            ..quadraticBezierTo(84, 61, 66, 69)
            ..moveTo(63, 76)
            ..lineTo(72, 49),
          line,
        );
        canvas.drawLine(const Offset(82, 15), const Offset(82, 25), line);
        canvas.drawLine(const Offset(77, 20), const Offset(87, 20), line);
        canvas.drawCircle(const Offset(25, 76), 2.5, line);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChatWallpaper oldDelegate) => false;
}
