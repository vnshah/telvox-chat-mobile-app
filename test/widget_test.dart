import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/app/app.dart';
import 'package:telvox_chat_mobile_app/ui/management.dart';
import 'package:telvox_chat_mobile_app/ui/preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final sans = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-400.ttf'));
    final mono = FontLoader('GeistMono')
      ..addFont(rootBundle.load('assets/fonts/GeistMono-400.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await sans.load();
    await mono.load();
    await icons.load();
    final emojiFile = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
    if (emojiFile.existsSync()) {
      await (FontLoader('Noto Color Emoji')..addFont(
            Future.value(ByteData.sublistView(emojiFile.readAsBytesSync())),
          ))
          .load();
    }
  });

  testWidgets('every screen renders at phone width without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final routes = [
      for (final screen in reviewScreens) screen.$3,
      for (final hub in hubs.keys) '/hub/$hub',
      for (final id in modules.keys) ...[
        '/manage/$id',
        '/manage/$id/0',
        '/manage/$id/new',
        '/manage/$id/0/edit',
      ],
      '/preview',
    ];
    for (final path in routes) {
      final router = createRouter(initialLocation: path);
      await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
      expect(find.text('Page not found'), findsNothing, reason: path);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });

  testWidgets('login preview opens workspace and inbox', (tester) async {
    final router = createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Your workspaces'), findsOneWidget);
    await tester.tap(find.text('Studio North').first);
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Ananya Shah'), findsOneWidget);
  });

  testWidgets('reply composer updates only the preview conversation', (
    tester,
  ) async {
    final router = createRouter(initialLocation: '/chat/ananya');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'A thoughtful preview reply',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pumpAndSettle();
    expect(find.text('A thoughtful preview reply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters show closed and empty conversation states', (
    tester,
  ) async {
    final router = createRouter(initialLocation: '/inbox');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'No matching customer');
    await tester.pumpAndSettle();
    expect(find.text('A little breathing room.'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View all chats'));
    await tester.tap(find.text('View all chats'));
    await tester.pumpAndSettle();
    expect(find.text('Ananya Shah'), findsOneWidget);
  });

  testWidgets('key screens handle compact and wide layouts', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(320, 740), const Size(1024, 900)]) {
      tester.view.physicalSize = size;
      for (final path in [
        '/login',
        '/inbox',
        '/chat/ananya',
        '/tickets',
        '/catalogue',
        '/more',
        '/reports',
        '/settings',
        '/call/incoming',
      ]) {
        final router = createRouter(initialLocation: path);
        await tester.pumpWidget(
          ProviderScope(child: TelvoxApp(router: router)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$path at $size');
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
    }
  });

  testWidgets('quick reply sheet saves and closes cleanly', (tester) async {
    final router = createRouter(initialLocation: '/quick-replies');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add quick reply'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '/hours');
    await tester.enterText(fields.at(1), 'We are here from 9 to 6.');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('/hours'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('template recipient selection retains the selected template', (
    tester,
  ) async {
    final router = createRouter(initialLocation: '/template/order');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ananya Shah'));
    await tester.pumpAndSettle();
    expect(find.text('Order confirmation'), findsOneWidget);
    expect(find.text('Add to conversation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('readable layouts with larger text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final path in ['/login', '/inbox', '/tickets', '/more', '/settings']) {
      final router = createRouter(initialLocation: path);
      await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });

  testWidgets('render review images with bundled brand fonts', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory('build/ui-previews');
    directory.createSync(recursive: true);
    for (final (name, path) in [
      ('login', '/login'),
      ('inbox', '/inbox'),
      ('chat', '/chat/ananya'),
      ('contact', '/customer/ananya'),
      ('tickets', '/tickets'),
      ('workspace', '/more'),
      ('catalogue', '/catalogue'),
      ('reports', '/reports'),
      ('call', '/call/incoming'),
    ]) {
      final router = createRouter(initialLocation: path);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: RepaintBoundary(
            key: boundary,
            child: TelvoxApp(router: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${directory.path}/$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull, reason: path);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });
}
