import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/composer.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// Review images of the attach sheet, on Android and iPhone.
void main() {
  testWidgets('attach sheet renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final boundary = GlobalKey();
      await renderWithRealShadows(() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: T.themeFor(platform),
              home: Builder(
                builder: (context) => Scaffold(
                  backgroundColor: const Color(0xFFEFE7DE),
                  body: Center(
                    child: TextButton(
                      onPressed: () =>
                          showAttachSheet(context, templates: true),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await saveReviewImage(
          tester,
          boundary,
          'build/review/attach-${platform.name}.png',
        );
      });
      await tester.pumpWidget(const SizedBox());
    }
  });
}
