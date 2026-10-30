import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'screens.dart';

class MobileApplication extends StatefulWidget {
  const MobileApplication({super.key, this.session});
  final MobileSession? session;
  @override
  State<MobileApplication> createState() => _MobileApplicationState();
}

class _MobileApplicationState extends State<MobileApplication> {
  late final session =
      widget.session ?? MobileSession(MobileApi(), SecureSessionStore());
  @override
  void initState() {
    super.initState();
    unawaited(session.restore());
  }

  @override
  void dispose() {
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => MaterialApp(
      key: ValueKey(
        '${session.signedIn}:${session.ready}:${session.generation}',
      ),
      title: 'Telvox Chat',
      debugShowCheckedModeBanner: false,
      theme: T.themeFor(defaultTargetPlatform),
      builder: (_, child) => CupertinoTheme(data: T.cupertino, child: child!),
      home: session.restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : session.ready
          ? LiveHome(session)
          : session.signedIn
          ? NumberPicker(session)
          : LoginScreen(session),
    ),
  );
}
