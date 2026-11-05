import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the app shows while it signs back in, carrying on the launch screen
/// the phone drew (android/app/src/main/res/drawable/splash_icon.xml, the
/// iOS LaunchScreen): white, with the app icon's bubble 128 wide at the
/// centre of the whole screen. The first frame matches it exactly, so the
/// hand-over is not seen; then the bubble rises a little and the rest of the
/// splash fades in: the telvox | chat wordmark, its line, and the TelVox
/// family at the foot.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  static const green = Color(0xFF176B46);

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with TickerProviderStateMixin {
  // Signing in is usually done in a second. Past two, a quiet spinner shows
  // the app is still at it rather than stuck.
  late final _wait = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  )..forward();

  /// The splash unfolding from the launch screen's bubble.
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    // After the first frame, which is the phone's launch screen exactly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        _reveal.forward();
      } else if (mounted) {
        _reveal.value = 1;
      }
    });
  }

  @override
  void dispose() {
    _wait.dispose();
    _reveal.dispose();
    super.dispose();
  }

  /// How far down the middle of the whole screen is, from the top of this
  /// view. The phone centres its launch icon on the whole screen, while this
  /// view can stop above the navigation buttons: centring on the view would
  /// make the bubble jump by half their height.
  double _screenMiddle(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final display = View.of(context).display;
    final whole = display.size.height / display.devicePixelRatio;
    return (whole >= height && whole < height * 1.25 ? whole : height) / 2;
  }

  static const _launchWidth = 128.0, _settledWidth = 112.0;

  /// The bubble, settled, sits this far above the screen's middle, so it and
  /// the wordmark under it are centred together, as designed.
  static const _rise = 38.0;

  @override
  Widget build(BuildContext context) {
    final middle = _screenMiddle(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      // Material gives the words their text style (without it Flutter marks
      // them with yellow underlines).
      child: Material(
        color: Colors.white,
        child: AnimatedBuilder(
          animation: _reveal,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_reveal.value);
            final width = ui.lerpDouble(_launchWidth, _settledWidth, t)!;
            final centre = middle - _rise * t;
            final text = Curves.easeOut.transform(
              const Interval(.25, 1).transform(_reveal.value),
            );
            // The settled bubble is about .95 of its width tall.
            final below = middle - _rise + _settledWidth * .95 / 2 + 22;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: centre - 72,
                  height: 144,
                  child: Center(
                    child: CustomPaint(
                      size: const Size.square(144),
                      painter: TelvoxMark(width: width),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: below + 8 * (1 - text),
                  child: Opacity(opacity: text, child: const _Wordmark()),
                ),
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: bottom + 40,
                  child: Opacity(opacity: text, child: const _Family()),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: below + 96,
                  child: Center(
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
              ],
            );
          },
        ),
      ),
    );
  }
}

/// telvox | chat, as the TelVox logo sets it in Geist Mono, and its line.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'TelVox Chat',
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'telvox',
                style: TextStyle(
                  fontFamily: 'GeistMono',
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.5,
                  color: Color(0xFF1C1A17),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 2,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFFCFC8BD),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'chat',
                style: TextStyle(
                  fontFamily: 'GeistMono',
                  fontSize: 30,
                  height: 1,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -.5,
                  color: Color(0xFF1F6E47),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Your team's customer inbox",
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 14,
              color: Color(0xFF5F6B73),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The TelVox family at the foot, this app's name marked in green.
class _Family extends StatelessWidget {
  const _Family();

  static const _products = ['Dial', 'Connect', 'Desk', 'Chat', 'Publish'];

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Row(
        children: [
          Expanded(child: Divider(height: 1, color: Color(0xFFDFE5E0))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'THE TELVOX FAMILY',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                color: Color(0xFF5F6B73),
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, color: Color(0xFFDFE5E0))),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          for (final name in _products)
            Expanded(
              child: Column(
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: name == 'Chat'
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: name == 'Chat'
                          ? BootScreen.green
                          : const Color(0xFF4A564F),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 18,
                    height: 3,
                    decoration: BoxDecoration(
                      color: name == 'Chat'
                          ? const Color(0xFF1AA565)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

/// The app icon's glossy green bubble with its three dots, drawn from the
/// icon's own shapes (assets/brand/telvox-chat-mark.svg, a 100-unit square).
/// In the 288dp square Android gives a launch-screen icon it is 128dp wide,
/// with splash_icon.xml's exact numbers, so the hand-over is not seen.
class TelvoxMark extends CustomPainter {
  const TelvoxMark({this.width = 128});

  /// How wide the bubble is, centred in the painted square.
  final double width;

  static Path _bubble() => Path()
    ..moveTo(33, 22)
    ..lineTo(67, 22)
    ..arcToPoint(const Offset(81, 36), radius: const Radius.circular(14))
    ..lineTo(81, 54)
    ..arcToPoint(const Offset(67, 68), radius: const Radius.circular(14))
    ..lineTo(44, 68)
    ..lineTo(29.5, 79.4)
    ..quadraticBezierTo(27, 81.3, 27, 78.2)
    ..lineTo(27, 67.5)
    ..quadraticBezierTo(19, 64.5, 19, 54)
    ..lineTo(19, 36)
    ..arcToPoint(const Offset(33, 22), radius: const Radius.circular(14))
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    // The bubble spans 62 units (x 19 to 81) about its centre (50, 51.3).
    final scale = width / 62;
    canvas
      ..save()
      ..translate(size.width / 2 - 50 * scale, size.height / 2 - 51.3 * scale)
      ..scale(scale);
    final bubble = _bubble();
    canvas.drawPath(
      bubble,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(19, 22),
          const Offset(68.6, 80.6),
          const [Color(0xFF46D892), Color(0xFF1AA565), Color(0xFF0C7046)],
          const [0, .55, 1],
        ),
    );
    // The gloss across its top.
    canvas
      ..save()
      ..clipPath(bubble)
      ..drawOval(
        Rect.fromCenter(center: const Offset(50, 24), width: 76, height: 32),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(50, 8),
            const Offset(50, 40),
            const [Color(0x8CFFFFFF), Color(0x00FFFFFF)],
          ),
      )
      ..restore();
    for (final x in const [36.0, 50.0, 64.0]) {
      canvas
        ..drawCircle(
          Offset(x, 45.9),
          5.6,
          Paint()..color = const Color(0x40064E30),
        )
        ..drawCircle(Offset(x, 45), 5.4, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TelvoxMark oldDelegate) => oldDelegate.width != width;
}
