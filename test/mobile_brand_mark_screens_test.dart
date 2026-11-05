import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/boot_screen.dart';

import 'support/ui.dart';

/// The app icon's bubble as image files, from the same painter the boot
/// screen uses: the iOS launch image (128pt wide, at 1x, 2x and 3x) and the
/// brand mark, all on transparent ground, plus a review image of the boot
/// screen. Copied into ios/ and assets/ by hand when the mark changes.
void main() {
  Future<void> render(
    WidgetTester tester,
    double box,
    double width,
    double ratio,
    String path,
  ) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: boundary,
          child: CustomPaint(
            size: Size.square(box),
            painter: TelvoxMark(width: width),
          ),
        ),
      ),
    );
    final object =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await object.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('the brand mark renders to its image files', (tester) async {
    await loadUiFonts();
    Directory('build/review/brand').createSync(recursive: true);
    for (final (ratio, name) in [
      (1.0, 'LaunchImage.png'),
      (2.0, 'LaunchImage@2x.png'),
      (3.0, 'LaunchImage@3x.png'),
    ]) {
      await render(tester, 136, 128, ratio, 'build/review/brand/$name');
    }
    await render(tester, 512, 480, 1, 'build/review/brand/mark.png');

    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: BootScreen(),
        ),
      ),
    );
    // The first frame, as the phone's launch screen, then settled.
    await saveReviewImage(tester, boundary, 'build/review/boot-first.png');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await saveReviewImage(tester, boundary, 'build/review/boot-screen.png');
  });
}
