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
class _BackGesture extends StatefulWidget {
  const _BackGesture({required this.route, required this.child});
  final PageRoute<dynamic> route;
  final Widget child;
  @override
  State<_BackGesture> createState() => _BackGestureState();
}

class _BackGestureState extends State<_BackGesture>
    with WidgetsBindingObserver {
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = widget.route;
    if (backEvent.isButtonEvent || !route.isCurrent) return false;
    if (!route.popGestureEnabled) return false;
    _active = true;
    route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_active) return;
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    if (!_active) return;
    _active = false;
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (!_active) return;
    _active = false;
    widget.route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
