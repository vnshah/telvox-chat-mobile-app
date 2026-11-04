import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config/app_config.dart';
import 'mobile/conversation_sync.dart';
import 'mobile/crash_reports.dart';
import 'mobile/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A touch screen that samples faster than the display refreshes (a 120 Hz
  // Galaxy's does) hands each frame one, two or three touches, so a dragged
  // list moves in uneven steps. Resampling moves it by where the finger was
  // at each frame instead, and scrolling follows the finger smoothly.
  GestureBinding.instance.resamplingEnabled = true;
  // A call rings and a carried message is saved while the app is closed.
  if (AppConfig.firebaseConfigured) {
    FirebaseMessaging.onBackgroundMessage(backgroundPush);
  }
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
  unawaited(startCrashReports());
}
