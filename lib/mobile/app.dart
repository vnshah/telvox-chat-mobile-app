import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'boot_screen.dart';
import 'calls.dart';
import 'connection.dart';
import 'local_cache.dart';
import 'media_cache.dart';
import 'offline_bar.dart';
import 'screens.dart';
import 'share_intake.dart';
import 'share_sheet.dart';

class MobileApplication extends StatefulWidget {
  const MobileApplication({super.key, this.session});
  final MobileSession? session;
  @override
  State<MobileApplication> createState() => _MobileApplicationState();
}

class _MobileApplicationState extends State<MobileApplication>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final session =
      widget.session ??
      (() {
        final store = SecureSessionStore();
        final api = MobileApi();
        return MobileSession(
          api,
          store,
          cache: SqlLocalCache(store),
          connection: ConnectionMonitor.platform(
            Uri.parse(api.dio.options.baseUrl),
          ),
        );
      })();

  /// Files shared from another app, held until there is a number to send
  /// them from (signed in, a number picked), then offered as WhatsApp does.
  late final shares = ShareIntake();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(session.connection.start());
    // Media already on the phone opens from it at once.
    unawaited(MediaCache.instance.load().catchError((_) {}));
    unawaited(session.restore());
    session.callPush.start();
    shares.pending.addListener(_offerShare);
    session.addListener(_offerShare);
    unawaited(shares.start());
  }

  @override
  void dispose() {
    _fade.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) session.connection.dispose();
    shares.pending.removeListener(_offerShare);
    session.removeListener(_offerShare);
    shares.dispose();
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        session.connection.resume();
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        session.connection.pause();
      default:
        break;
    }
  }

  void _offerShare() {
    if (shares.pending.value == null || !session.ready) return;
    // After this frame: the navigator for the current app may be new.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigator?.currentState;
      if (!mounted || navigator == null || !session.ready) return;
      final files = shares.take();
      if (files != null) unawaited(openShare(navigator, session, files));
    });
  }

  /// A fresh navigator key for each app instance the key below rebuilds, so a
  /// rebuilt app never takes over the previous one's routes.
  String? _app;
  GlobalKey<NavigatorState>? _navigator;

  /// Whether the boot screen was showing, so leaving it fades into the app
  /// rather than cutting to it: the app is built at once beneath, and the
  /// boot screen, kept on top as it was, fades away over it.
  bool _booting = false;
  Widget? _shown, _leaving;
  late final _fade =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _leaving = null);
        }
      });

  bool get _boot =>
      session.restoring || (session.awaitingNetwork && !session.signedIn);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final boot = _boot;
      final app =
          '$boot:${session.signedIn}:${session.ready}:${session.generation}';
      if (app != _app) {
        _app = app;
        _navigator = GlobalKey<NavigatorState>();
        session.calls.navigator = _navigator;
        if (_booting && !boot && !MediaQuery.disableAnimationsOf(context)) {
          _leaving = _shown;
          _fade.forward(from: 0);
        }
        _booting = boot;
      }
      final shown = _shown = _materialApp(app);
      final leaving = _leaving;
      return Stack(
        textDirection: TextDirection.ltr,
        fit: StackFit.expand,
        children: [
          shown,
          if (leaving != null)
            IgnorePointer(
              child: FadeTransition(
                opacity: ReverseAnimation(_fade),
                child: leaving,
              ),
            ),
        ],
      );
    },
  );

  Widget _materialApp(String app) => MaterialApp(
    key: ValueKey(app),
    navigatorKey: _navigator,
    title: 'Telvox Chat',
    debugShowCheckedModeBanner: false,
    theme: T.themeFor(defaultTargetPlatform),
    builder: (_, child) => CupertinoTheme(
      data: T.cupertino,
      // Offline, a bar across the top; the app stays usable beneath it.
      child: OfflineBar(
        session.connection,
        child: OngoingCallBar(session.calls, child: child!),
      ),
    ),
    // Opened offline with no account kept yet: it loads once back online.
    home: _boot
        ? const BootScreen()
        : session.ready
        ? LiveHome(session)
        : session.signedIn
        ? NumberPicker(session)
        : LoginScreen(session),
  );
}
