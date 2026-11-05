import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/media_quality.dart';
import 'package:telvox_chat_mobile_app/mobile/send_media.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'fake_media.dart';
import 'support/ui.dart';

/// A photo to preview: a sky over hills, in [hue]'s colours.
File scene(String name, double hue) {
  final picture = img.Image(width: 600, height: 800);
  for (var y = 0; y < 800; y++) {
    final t = y / 800;
    for (var x = 0; x < 600; x++) {
      final hill = 520 + 60 * math.sin(x / 70 + hue * 6);
      final ground = y > hill;
      final r = ground ? 40 + 60 * hue : 120 + 120 * (1 - t);
      final g = ground ? 110 + 40 * t : 160 + 60 * hue;
      final b = ground ? 60 : 230 - 80 * t;
      picture.setPixelRgb(x, y, r.round(), g.round(), b.round());
    }
  }
  img.fillCircle(
    picture,
    x: 430,
    y: 180,
    radius: 60,
    color: img.ColorRgb8(255, 214, 120),
  );
  return File('${Directory.systemTemp.path}/review-$name')
    ..writeAsBytesSync(img.encodeJpg(picture, quality: 90));
}

/// Review images of the send preview, its HD switch and the quality choice.
void main() {
  testWidgets('the send preview renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    mediaCompressor = FakeCompressor(size: (4032, 3024));
    final files = await tester.runAsync(
      () async => [
        for (final (i, hue) in [.2, .6, .9].indexed) scene('IMG_$i.jpg', hue),
      ],
    );
    final items = [
      for (final f in files!)
        Attachment(XFile(f.path), 'image', 3400000, 'image/jpeg'),
    ];
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: SendMediaPage(items, recipient: 'Priya Shah'),
          ),
        ),
      );
      // The photos are decoded on the real event loop.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/send-media.png');

      await tester.tap(find.byKey(const ValueKey('quality-button')));
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/quality-sheet.png');

      await tester.tap(find.text('HD quality'));
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/send-media-hd.png');
    });
  });
}
