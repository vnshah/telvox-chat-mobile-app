import 'package:flutter/widgets.dart';

/// A sent message's delivery mark, drawn as the web inbox draws it (its
/// thin line icons): a clock while sending (0), one check once sent (1), two
/// once delivered (2), two in blue once read (3), a cloud with "!" when it
/// failed (4), and a barred circle when WhatsApp blocked it (5).
class DeliveryTick extends StatelessWidget {
  const DeliveryTick(
    this.status, {
    super.key,
    this.size = 16,
    this.color = muted,
    this.onPhoto = false,
  });
  final int? status;
  final double size;

  /// The ink of a mark that is not read or failed.
  final Color color;

  /// Over a photo: white, with read still blue.
  final bool onPhoto;

  static const muted = Color(0xFF808080);
  static const read = Color(0xFF1B9BD8);
  static const failed = Color(0xFFC02434);

  static String label(int? status) => switch (status) {
    0 => 'Sending',
    1 => 'Sent',
    2 => 'Delivered',
    3 => 'Read',
    4 => 'Not delivered',
    5 => 'Blocked',
    _ => 'Sent',
  };

  @override
  Widget build(BuildContext context) {
    final ink = switch (status) {
      3 => onPhoto ? const Color(0xFF7FD3FF) : read,
      4 || 5 => failed,
      _ => color,
    };
    return Semantics(
      label: label(status),
      child: CustomPaint(
        key: ValueKey('tick-${status ?? 1}'),
        size: Size.square(size),
        painter: _TickPainter(status ?? 1, ink),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.status, this.ink);
  final int status;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // The web's icons are drawn on a 24-unit grid with a 2-unit stroke.
    canvas.scale(size.width / 24);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path();
    switch (status) {
      case 0:
        canvas.drawCircle(const Offset(12, 12), 10, pen);
        p
          ..moveTo(12, 6)
          ..lineTo(12, 12)
          ..lineTo(16, 14);
      case 2 || 3:
        p
          ..moveTo(18, 6)
          ..lineTo(7, 17)
          ..lineTo(2, 12)
          ..moveTo(22, 10)
          ..lineTo(14.5, 17.5)
          ..lineTo(13, 16);
      case 4:
        p
          ..moveTo(12, 12)
          ..lineTo(12, 16)
          ..moveTo(12, 20)
          ..lineTo(12.01, 20)
          ..moveTo(17, 18)
          ..lineTo(17.5, 18)
          ..arcToPoint(
            const Offset(17.5, 9),
            radius: const Radius.circular(4.5),
            clockwise: false,
          )
          ..lineTo(15.71, 9)
          ..arcToPoint(
            const Offset(7, 17.708),
            radius: const Radius.circular(7),
            largeArc: true,
            clockwise: false,
          );
      case 5:
        canvas.drawCircle(const Offset(12, 12), 10, pen);
        p
          ..moveTo(4.9, 4.9)
          ..lineTo(19.1, 19.1);
      default:
        p
          ..moveTo(20, 6)
          ..lineTo(9, 17)
          ..lineTo(4, 12);
    }
    canvas.drawPath(p, pen);
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.status != status || old.ink != ink;
}
