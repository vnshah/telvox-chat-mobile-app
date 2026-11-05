import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mobile/conversation_sync.dart';
import 'mobile/crash_reports.dart';
import 'mobile/firebase_settings.dart';
import 'mobile/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Firebase project, from the phone's copy of the server's answer: a
  // small local read, so start-up never waits on the network.
  await FirebaseSettings.load();
  // A touch screen that samples faster than the display refreshes (a 120 Hz
  // Galaxy's does) hands each frame one, two or three touches, so a dragged
  // list moves in uneven steps. Resampling moves it by where the finger was
  // at each frame instead, and scrolling follows the finger smoothly.
  GestureBinding.instance.resamplingEnabled = true;
  // A call rings and a carried message is saved while the app is closed.
  final hadFirebase = FirebaseSettings.current != null;
  if (hadFirebase) FirebaseMessaging.onBackgroundMessage(backgroundPush);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Geist',
      'Geist Mono',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/Roboto-OFL.txt'));
  });
  runApp(const MobileApplication());
  // After the first frame is on its way: crash reports never delay start-up.
  if (hadFirebase) unawaited(startCrashReports());
  // The server's .env is where the project is set: ask it, keep its answer
  // for next time, and start Firebase now if this phone had none yet.
  unawaited(
    FirebaseSettings.refresh().then((_) async {
      if (hadFirebase || FirebaseSettings.current == null) return;
      FirebaseMessaging.onBackgroundMessage(backgroundPush);
      await startCrashReports();
    }),
  );
}
