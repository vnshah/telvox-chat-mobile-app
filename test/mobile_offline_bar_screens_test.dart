import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/connection.dart';
import 'package:telvox_chat_mobile_app/mobile/offline_bar.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// Review images of the offline bar over the inbox, and back online.
void main() {
  testWidgets('offline bar renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 520);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    var reachable = false;
    final monitor = ConnectionMonitor(probe: () async => reachable);
    await tester.runAsync(monitor.start);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: T.themeFor(TargetPlatform.android),
          builder: (_, child) => OfflineBar(monitor, child: child!),
          home: Scaffold(
            appBar: AppBar(title: const Text('Inbox')),
            body: ListView(
              children: [
                for (final (name, text) in [
                  ('Asha Mehta', 'Thanks, see you tomorrow'),
                  ('Ravi Patel', 'Is the order ready?'),
                  ('Meera Shah', 'Photo'),
                  ('Arjun Rao', 'Voice message'),
                ])
                  ListTile(
                    leading: CircleAvatar(child: Text(name[0])),
                    title: Text(name),
                    subtitle: Text(text),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsOneWidget);
    await saveReviewImage(tester, boundary, 'build/review/offline-bar.png');

    reachable = true;
    await tester.runAsync(monitor.check);
    await tester.pumpAndSettle();
    expect(find.text('Back online'), findsOneWidget);
    await saveReviewImage(tester, boundary, 'build/review/offline-back.png');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    monitor.dispose();
  });
}
