import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/connection.dart';
import 'package:telvox_chat_mobile_app/mobile/offline_screen.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// Review images of the offline screen, on Android and iPhone.
void main() {
  testWidgets('offline screen renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final monitor = ConnectionMonitor(probe: () async => false);
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(platform),
            home: OfflineScreen(monitor),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('You’re offline'), findsOneWidget);
      await saveReviewImage(
        tester,
        boundary,
        'build/review/offline-${platform.name}.png',
      );
    }
    monitor.dispose();
  });
}
