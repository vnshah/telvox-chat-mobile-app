import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/app/app.dart';
import 'package:telvox_chat_mobile_app/ui/data.dart';
import 'package:telvox_chat_mobile_app/ui/conversation.dart';
import 'package:telvox_chat_mobile_app/ui/management.dart';
import 'package:telvox_chat_mobile_app/ui/preview.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiFonts);

  testWidgets('every Cupertino screen renders without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final paths = [
      for (final screen in reviewScreens) screen.$3,
      for (final hub in hubs.keys) '/hub/$hub',
      for (final module in modules.keys) ...[
        '/manage/$module',
        '/manage/$module/0',
        '/manage/$module/new',
        '/manage/$module/0/edit',
      ],
      '/preview',
    ];
    for (final path in paths) {
      final router = createRouter(initialLocation: path);
      await tester.pumpWidget(
        ProviderScope(
          child: TelvoxApp(router: router, platform: TargetPlatform.iOS),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
      expect(find.text('Page not found'), findsNothing, reason: path);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });

  testWidgets('Cupertino sign-in validation, tabs, search and chat work', (
    tester,
  ) async {
    final router = createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: TelvoxApp(router: router, platform: TargetPlatform.iOS),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTextField), findsNWidgets(2));
    expect(find.textContaining('Create account'), findsNothing);
    await tester.enterText(find.byType(CupertinoTextField).first, 'invalid');
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    await tester.enterText(
      find.byType(CupertinoTextField).first,
      'renav@studionorth.co',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Studio North').first);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.byType(CupertinoSlidingSegmentedControl<String>),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('More filters'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoActionSheet),
        matching: find.text('Closed'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dev Malhotra'), findsOneWidget);
    expect(find.text('Ananya Shah'), findsNothing);
    await tester.tap(find.byTooltip('More filters'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoActionSheet),
        matching: find.text('All'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSearchTextField), findsOneWidget);
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoSearchTextField), 'Rohan');
    await tester.pumpAndSettle();
    expect(find.text('Ananya Shah'), findsNothing);
    await tester.tap(find.text('Rohan Mehta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'Thanks, Rohan.');
    await tester.pump();
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Thanks, Rohan.', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cupertino customer and date pickers retain the selected values',
    (tester) async {
      final router = createRouter(initialLocation: '/tickets');
      final container = ProviderContainer();
      addTearDown(router.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TelvoxApp(router: router, platform: TargetPlatform.iOS),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Create ticket'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(CupertinoTextField).first,
        'Delivery instructions',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ananya Shah'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      await tester.tap(find.text('Rohan Mehta'));
      await tester.pumpAndSettle();
      expect(find.text('Rohan Mehta'), findsOneWidget);
      final context = tester.element(find.byType(AppDropdownField<String>));
      final date = showAppDatePicker(
        context: context,
        initialDate: DateTime(2026, 11, 2),
        firstDate: DateTime(2026),
        lastDate: DateTime(2028),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(await date, DateTime(2026, 11, 2));
      await tester.tap(find.widgetWithText(AppButton, 'Create ticket'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(previewProvider)
            .tickets
            .any(
              (t) =>
                  t.title == 'Delivery instructions' && t.personId == 'rohan',
            ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cupertino editor sheets and destructive confirmations close safely',
    (tester) async {
      final router = createRouter(initialLocation: '/quick-replies');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: TelvoxApp(router: router, platform: TargetPlatform.iOS),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add quick reply'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPopupSurface), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField).at(0), '/hours');
      await tester.enterText(
        find.byType(CupertinoTextField).at(1),
        'We are here from 9 to 6.',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('/hours'), findsOneWidget);
      router.go('/chat/ananya');
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(MessageBubble).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'That sounds perfect, thank you!',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'screen library changes appearance across routes and restores device style',
    (tester) async {
      final router = createRouter(initialLocation: '/preview');
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Inbox');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('iOS'));
      await tester.tap(find.text('iOS'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(
        tester
            .widget<CupertinoSearchTextField>(
              find.byType(CupertinoSearchTextField),
            )
            .controller!
            .text,
        'Inbox',
      );
      await tester.ensureVisible(find.widgetWithText(MenuRow, 'Inbox'));
      await tester.tap(find.widgetWithText(MenuRow, 'Inbox'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoTabBar), findsOneWidget);
      router.go('/preview');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Device'));
      await tester.tap(find.text('Device'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(MenuRow, 'Inbox'));
      await tester.tap(find.widgetWithText(MenuRow, 'Inbox'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(CupertinoTabBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cupertino layouts support small phones, tablets and larger text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [const Size(320, 740), const Size(1024, 900)]) {
        tester.view.physicalSize = size;
        for (final scale in [1.0, 1.5]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          for (final path in [
            '/login',
            '/workspaces',
            '/inbox',
            '/contacts',
            '/tickets',
            '/chat/ananya',
            '/more',
            '/settings',
            '/preview',
          ]) {
            final router = createRouter(initialLocation: path);
            await tester.pumpWidget(
              ProviderScope(
                child: TelvoxApp(router: router, platform: TargetPlatform.iOS),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$path at $size, text $scale',
            );
            await tester.pumpWidget(const SizedBox());
            router.dispose();
          }
        }
      }
    },
  );

  testWidgets('render Cupertino review screenshots', (tester) async {
    await renderWithRealShadows(() async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory('build/ui-previews/ios')
        ..createSync(recursive: true);
      for (final (name, path) in [
        ('login', '/login'),
        ('inbox', '/inbox'),
        ('chat', '/chat/ananya'),
        ('contacts', '/contacts'),
        ('contact', '/customer/ananya'),
        ('tickets', '/tickets'),
        ('ticket-form', '/ticket/new'),
        ('workspace', '/workspaces'),
        ('more', '/more'),
        ('settings', '/settings'),
        ('preferences', '/settings/notifications'),
        ('catalogue', '/catalogue'),
        ('reports', '/reports'),
        ('screen-library', '/preview'),
      ]) {
        final router = createRouter(initialLocation: path);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: RepaintBoundary(
              key: boundary,
              child: TelvoxApp(router: router, platform: TargetPlatform.iOS),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await saveReviewImage(tester, boundary, '${directory.path}/$name.png');
        expect(tester.takeException(), isNull, reason: path);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
    });
  });
}
