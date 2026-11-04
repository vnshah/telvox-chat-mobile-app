import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';

/// The Firebase project the app's pushes and crash reports go to.
FirebaseOptions get firebaseOptions => FirebaseOptions(
  apiKey: AppConfig.firebasePlatformApiKey,
  appId: AppConfig.firebasePlatformAppId,
  messagingSenderId: AppConfig.firebaseSenderId,
  projectId: AppConfig.firebaseProjectId,
);

/// Starts Firebase once, for whichever part of the app needs it first.
Future<void> startFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: firebaseOptions);
  }
}

/// Sends crashes from release builds to Firebase Crashlytics, so they can be
/// found and fixed: every uncaught Flutter and Dart error, with its stack.
/// Reports carry no account, chat or message: only what crashed and where.
/// Debug builds and builds without Firebase report nothing.
Future<void> startCrashReports() async {
  if (!AppConfig.firebaseConfigured) return;
  try {
    await startFirebase();
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(crashlytics.recordError(error, stack, fatal: true));
      return true;
    };
  } catch (_) {
    // Without crash reports the app still works.
  }
}
