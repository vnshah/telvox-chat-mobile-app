import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the app shows while it signs back in: the launch screen Android drew
/// (android/app/src/main/res/drawable/splash_icon.xml and splash_branding.xml)
/// carried on unchanged, white with the mark in the middle and "from Telvox"
/// at the foot, as WhatsApp's "from Meta". Everything sits where Android put
/// it, so the moment the app takes over is not seen.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  static const green = Color(0xFF176B46);

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen>
    with SingleTickerProviderStateMixin {
  // Signing in is usually done in a second. Past two, a quiet spinner shows
  // the app is still at it rather than stuck.
  late final _wait = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  )..forward();

  @override
  void dispose() {
    _wait.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.white,
    ),
    child: ColoredBox(
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(
            child: CustomPaint(size: Size.square(288), painter: _Mark()),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 200),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _wait,
                  curve: const Interval(.87, 1),
                ),
                child: const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: BootScreen.green,
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Center(
              child: CustomPaint(size: Size(200, 80), painter: _Branding()),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The launcher icon's chat bubble and double tick, in the 288dp square
/// Android gives a launch-screen icon (splash_icon.xml has the same numbers).
class _Mark extends CustomPainter {
  const _Mark();

  @override
  void paint(Canvas canvas, Size size) {
    const scale = .196319;
    canvas
      ..translate(43.583, 47.804)
      ..scale(scale);
    final stroke = Paint()
      ..color = BootScreen.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 52
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final bubble = Path()
      ..moveTo(359, 283)
      ..lineTo(664, 283)
      ..cubicTo(700, 283, 730, 313, 730, 349)
      ..lineTo(730, 543)
      ..cubicTo(730, 580, 700, 610, 664, 610)
      ..lineTo(468, 610)
      ..lineTo(359, 697)
      ..lineTo(359, 610)
      ..cubicTo(323, 610, 293, 580, 293, 543)
      ..lineTo(293, 349)
      ..cubicTo(293, 313, 323, 283, 359, 283)
      ..close();
    final ticks = Path()
      ..moveTo(403, 453)
      ..lineTo(446, 495)
      ..lineTo(515, 419)
      ..moveTo(477, 476)
      ..lineTo(518, 517)
      ..lineTo(596, 432);
    canvas
      ..drawPath(bubble, stroke)
      ..drawPath(ticks, stroke);
  }

  @override
  bool shouldRepaint(_Mark oldDelegate) => false;
}

/// "from" over "Telvox", each centred on its baseline in the 200 x 80 box
/// Android gives a launch screen's branding (splash_branding.xml).
class _Branding extends CustomPainter {
  const _Branding();

  static void _line(
    Canvas canvas,
    Size size,
    String text,
    TextStyle style,
    double baseline,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final top =
        baseline -
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter
      ..paint(canvas, Offset((size.width - painter.width) / 2, top))
      ..dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _line(
      canvas,
      size,
      'from',
      const TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: Color(0xFF8696A0),
      ),
      32,
    );
    _line(
      canvas,
      size,
      'Telvox',
      const TextStyle(
        fontFamily: 'Geist',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: BootScreen.green,
      ),
      56,
    );
  }

  @override
  bool shouldRepaint(_Branding oldDelegate) => false;
}
