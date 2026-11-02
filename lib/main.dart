import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'mobile/call_push.dart';
import 'mobile/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // A customer's call wakes a closed app by push; see backgroundCallPush.
  if (AppConfig.firebaseConfigured && !AppConfig.preview) {
    FirebaseMessaging.onBackgroundMessage(backgroundCallPush);
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
  runApp(
    const ProviderScope(
      child: AppConfig.preview ? TelvoxApp() : MobileApplication(),
    ),
  );
}
