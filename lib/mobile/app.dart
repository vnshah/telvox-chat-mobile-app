import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

import '../ui/theme.dart';
import 'api.dart';
import 'calls.dart';
import 'connection.dart';
import 'local_cache.dart';
import 'offline_screen.dart';
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
    with WidgetsBindingObserver {
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
    session.connection.addListener(_connectionChanged);
    unawaited(session.connection.start());
    unawaited(session.restore());
    session.callPush.start();
    shares.pending.addListener(_offerShare);
    session.addListener(_offerShare);
    unawaited(shares.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.connection.removeListener(_connectionChanged);
    if (widget.session == null) session.connection.dispose();
    shares.pending.removeListener(_offerShare);
    session.removeListener(_offerShare);
    shares.dispose();
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  /// Going offline puts the keyboard away: the offline screen covers the
  /// field, whose text stays as it was.
  void _connectionChanged() {
    if (!session.connection.online) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
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

  // While offline, back does nothing: nothing may change unseen beneath the
  // offline screen. These run before the app's navigator hears of it.
  @override
  Future<bool> didPopRoute() async => !session.connection.online;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) =>
      !session.connection.online;

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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final app = '${session.signedIn}:${session.ready}:${session.generation}';
      if (app != _app) {
        _app = app;
        _navigator = GlobalKey<NavigatorState>();
        session.calls.navigator = _navigator;
      }
      return _materialApp(app);
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
      child: ValueListenableBuilder(
        valueListenable: session.connection,
        builder: (context, online, app) => Stack(
          fit: StackFit.expand,
          children: [
            // Kept alive beneath, unseen and untouchable while offline.
            ExcludeSemantics(excluding: !online, child: app),
            if (!online) OfflineScreen(session.connection),
          ],
        ),
        child: OngoingCallBar(session.calls, child: child!),
      ),
    ),
    home: session.restoring || session.awaitingNetwork
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : session.ready
        ? LiveHome(session)
        : session.signedIn
        ? NumberPicker(session)
        : LoginScreen(session),
  );
}
