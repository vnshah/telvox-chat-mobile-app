import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadUiFonts() async {
  final sans = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-400.ttf'));
  final mono = FontLoader('GeistMono')
    ..addFont(rootBundle.load('assets/fonts/GeistMono-400.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto.ttf'));
  final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  await sans.load();
  await mono.load();
  await icons.load();
  await roboto.load();
  await cupertino.load();
  final emojiFile = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emojiFile.existsSync()) {
    await (FontLoader('Noto Color Emoji')..addFont(
          Future.value(ByteData.sublistView(emojiFile.readAsBytesSync())),
        ))
        .load();
  }
}

Future<void> saveReviewImage(
  WidgetTester tester,
  GlobalKey boundary,
  String path,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

/// Golden previews paint real shadows; restore the test flag before invariants run.
Future<void> renderWithRealShadows(Future<void> Function() render) async {
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  try {
    await render();
  } finally {
    debugDisableShadows = previous;
  }
}
