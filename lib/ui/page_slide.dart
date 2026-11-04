import 'package:flutter/gestures.dart' show HorizontalDragGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

/// WhatsApp's page change on Android: the new page slides in from the right
/// edge while the one below shifts a little left, and back reverses it.
/// Android's back gesture drags the page off to the right under the finger,
/// showing the page below, as the predictive back gesture does.
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Under a finger the page moves with it, not along a curve.
    final dragging = route.popGestureInProgress;
    Animation<double> eased(Animation<double> parent) => dragging
        ? parent
        : CurvedAnimation(
            parent: parent,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
    return _BackGesture(
      route: route,
      child: SlideTransition(
        position: Tween(
          begin: Offset.zero,
          end: const Offset(-.25, 0),
        ).animate(eased(secondaryAnimation)),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(eased(animation)),
          // A soft edge where the new page overlaps the old one.
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 12,
                  offset: Offset(-2, 0),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Hands Android's back gesture to the route, so dragging plays the slide
/// backwards under the finger and letting go finishes or cancels it. A
/// button press, the first page, or a page that cannot be left (an unsaved
/// note asks first) is left to the normal back handling.
///
/// The same goes for a swipe from the left edge inside the app, as Telegram
/// and iOS do: on phones with the 3-button bar, and on older Androids whose
/// own back gesture does not animate. Only a swipe that starts at the edge
/// counts, so swiping a message to reply, horizontal lists and dismissing a
/// chat row work as before.
class _BackGesture extends StatefulWidget {
  const _BackGesture({required this.route, required this.child});
  final PageRoute<dynamic> route;
  final Widget child;
  @override
  State<_BackGesture> createState() => _BackGestureState();
}

/// How far in from the edge a swipe back may start, beyond the strip
/// Android keeps for its own back gesture.
const double edgeSwipeWidth = 28;

/// A swipe this fast (screen widths a second) decides on its own; slower,
/// the page goes back when dragged past half way.
const double _flingVelocity = 1;

enum _Driver { none, system, edge }

class _BackGestureState extends State<_BackGesture>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  _Driver _driver = _Driver.none;
  late final HorizontalDragGestureRecognizer _drag;

  /// Finishes an edge swipe the finger let go of: on to the page below, or
  /// back to this one, from wherever the finger left it.
  late final AnimationController _settle = AnimationController(vsync: this)
    ..addListener(() {
      if (widget.route.isCurrent) {
        widget.route.handleUpdateBackGestureProgress(progress: _settle.value);
      }
    });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drag = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _edgeStart
      ..onUpdate = _edgeUpdate
      ..onEnd = _edgeEnd
      ..onCancel = _edgeCancel;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drag.dispose();
    _settle.dispose();
    super.dispose();
  }

  bool get _canGoBack =>
      _driver == _Driver.none &&
      !_settle.isAnimating &&
      widget.route.isCurrent &&
      widget.route.popGestureEnabled;

  // Android's own back gesture.

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !_canGoBack) return false;
    _driver = _Driver.system;
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_driver != _Driver.system) return;
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    if (_driver != _Driver.system) return;
    _driver = _Driver.none;
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (_driver != _Driver.system) return;
    _driver = _Driver.none;
    widget.route.handleCommitBackGesture();
  }

  // A swipe from the edge inside the app.

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  /// The finger's move as a share of the page, positive towards going back.
  double _share(double dx) {
    final width = context.size?.width ?? 1;
    return (_rtl ? -dx : dx) / width;
  }

  void _edgeDown(PointerDownEvent event) {
    if (_canGoBack) _drag.addPointer(event);
  }

  void _edgeStart(DragStartDetails _) {
    // The page may have changed between the touch and the drag.
    if (!_canGoBack) return;
    _driver = _Driver.edge;
    widget.route.handleStartBackGesture(progress: 1);
  }

  void _edgeUpdate(DragUpdateDetails d) {
    if (_driver != _Driver.edge || !widget.route.isCurrent) return;
    final progress = widget.route.animation!.value - _share(d.delta.dx);
    widget.route.handleUpdateBackGestureProgress(
      progress: progress.clamp(0.0, 1.0),
    );
  }

  void _edgeEnd(DragEndDetails d) {
    if (_driver != _Driver.edge) return;
    final speed = _share(d.velocity.pixelsPerSecond.dx);
    final at = widget.route.animation!.value;
    final back = speed.abs() >= _flingVelocity ? speed > 0 : at < .5;
    _finish(back, from: at);
  }

  void _edgeCancel() {
    if (_driver != _Driver.edge) return;
    _finish(false, from: widget.route.animation!.value);
  }

  Future<void> _finish(bool back, {required double from}) async {
    final route = widget.route;
    final to = back ? 0.0 : 1.0;
    final left = (to - from).abs();
    _settle.value = from;
    if (left > 0 && route.isCurrent) {
      await _settle
          .animateTo(
            to,
            duration: Duration(milliseconds: (300 * left).round() + 50),
            curve: Curves.easeOutCubic,
          )
          .orCancel
          .catchError((_) {});
    }
    _driver = _Driver.none;
    if (!route.isCurrent) return;
    back ? route.handleCommitBackGesture() : route.handleCancelBackGesture();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.systemGestureInsetsOf(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: (_rtl ? insets.right : insets.left) + edgeSwipeWidth,
          // Lets touches through: a tap on the back button or a message at
          // the edge still lands; only a sideways drag is taken.
          child: Listener(
            onPointerDown: _edgeDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
