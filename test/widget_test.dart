import 'dart:io';

import 'support/ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/app/app.dart';
import 'package:telvox_chat_mobile_app/ui/conversation.dart';
import 'package:telvox_chat_mobile_app/ui/data.dart';
import 'package:telvox_chat_mobile_app/ui/management.dart';
import 'package:telvox_chat_mobile_app/ui/preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadUiFonts);

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
    expect(
      find.textContaining('A thoughtful preview reply', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-in is for existing accounts without a registration route', (
    tester,
  ) async {
    final router = createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Create account'), findsNothing);
    expect(find.textContaining('Create an account'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(reviewScreens.any((screen) => screen.$3 == '/register'), isFalse);
    router.go('/register');
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('Create your account.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace and business lists use compact rows', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (path, prefix, maxHeight) in [
      ('/workspaces', 'workspace-row-', 80.0),
      ('/inbox', 'conversation-row-', 80.0),
      ('/contacts', 'contact-row-', 76.0),
      ('/tickets', 'ticket-row-', 80.0),
    ]) {
      final router = createRouter(initialLocation: path);
      await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
      await tester.pumpAndSettle();
      final rows = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      );
      expect(rows, findsWidgets, reason: path);
      expect(
        tester.getSize(rows.first).height,
        lessThanOrEqualTo(maxHeight),
        reason: path,
      );
      expect(tester.takeException(), isNull, reason: path);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });

  testWidgets('message actions react, reply, star and delete locally', (
    tester,
  ) async {
    final router = createRouter(initialLocation: '/chat/ananya');
    final container = ProviderContainer();
    addTearDown(router.dispose);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TelvoxApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-composer'))).height,
      lessThanOrEqualTo(64),
    );
    await tester.longPress(find.byType(MessageBubble).first);
    await tester.pumpAndSettle();
    for (final label in [
      'Reply',
      'Copy',
      'Forward',
      'Star',
      'Message info',
      'Delete for me',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(find.text('👍'), findsOneWidget);
    await tester.longPress(find.byType(MessageBubble).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reply-preview')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Your order is on its way.');
    await tester.pump();
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pumpAndSettle();
    final sent = container.read(previewProvider).messages['ananya']!.last;
    expect(sent.reply, 'That sounds perfect, thank you!');
    expect(sent.replyAuthor, 'Ananya Shah');
    expect(sent.text, 'Your order is on its way.');
    expect(find.byKey(const ValueKey('reply-preview')), findsNothing);
    await tester.longPress(find.byType(MessageBubble).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star'));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(MessageBubble).first);
    await tester.pumpAndSettle();
    expect(find.text('Unstar'), findsOneWidget);
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your order is on its way.', findRichText: true),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reactions stay below incoming and outgoing message text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final textScale in [1.0, 1.5]) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      final router = createRouter(initialLocation: '/chat/ananya');
      await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
      await tester.pumpAndSettle();
      for (final (index, emoji) in [(6, '👍'), (7, '😊')]) {
        if (index == 7) {
          await tester.enterText(find.byType(TextField), 'A short reply.');
          await tester.pump();
          await tester.tap(find.byTooltip('Send reply'));
          await tester.pumpAndSettle();
        }
        final entry = find.byKey(ValueKey('message-$index'));
        await tester.longPress(
          find.descendant(of: entry, matching: find.byType(MessageBubble)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(emoji));
        await tester.pumpAndSettle();
        final bubble = find.descendant(
          of: entry,
          matching: find.byType(MessageBubble),
        );
        final badge = find.byKey(ValueKey('message-reaction-$index'));
        expect(
          tester.getTopLeft(badge).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(bubble).dy - 3.1),
        );
        expect(tester.takeException(), isNull, reason: '$index at $textScale');
      }
      expect(
        find.textContaining('A short reply.', findRichText: true),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });

  testWidgets('swiping a bubble starts a quoted reply', (tester) async {
    final router = createRouter(initialLocation: '/chat/ananya');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    final last = find.descendant(
      of: find.byKey(const ValueKey('message-6')),
      matching: find.byType(MessageBubble),
    );
    await tester.drag(last, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reply-preview')), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reply-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sent messages appear in place and finish their brief transition',
    (tester) async {
      final router = createRouter(initialLocation: '/chat/ananya');
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A smooth arrival');
      await tester.pump();
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pump();
      final entry = find.byKey(const ValueKey('message-7'));
      final fade = find
          .descendant(of: entry, matching: find.byType(FadeTransition))
          .first;
      final bubble = find.descendant(
        of: entry,
        matching: find.byType(MessageBubble),
      );
      final arrival = tester.getTopLeft(bubble);
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
      expect(
        find.textContaining('A smooth arrival', findRichText: true),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect((tester.getTopLeft(bubble) - arrival).distance, lessThan(4));
      expect(
        find.textContaining('A smooth arrival', findRichText: true),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Leave during transition');
      await tester.pump();
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      router.go('/inbox');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion shows the sent message immediately', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final router = createRouter(initialLocation: '/chat/ananya');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Reduced motion reply');
    await tester.pump();
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump();
    final fade = find
        .descendant(
          of: find.byKey(const ValueKey('message-7')),
          matching: find.byType(FadeTransition),
        )
        .first;
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Reduced motion reply', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long replies animate and menus remain usable with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = createRouter(initialLocation: '/chat/ananya');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: TelvoxApp(router: router)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Your order is ready.\nWe will send a tracking link shortly.\nThank you for shopping with Studio North!',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final fade = find
        .descendant(
          of: find.byKey(const ValueKey('message-7')),
          matching: find.byType(FadeTransition),
        )
        .first;
    expect(tester.widget<FadeTransition>(fade).opacity.value, greaterThan(.8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final bubble = find.descendant(
      of: find.byKey(const ValueKey('message-7')),
      matching: find.byType(MessageBubble),
    );
    await tester.longPress(bubble);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Message info'));
    await tester.tap(find.text('Message info'));
    await tester.pumpAndSettle();
    expect(find.text('Delivered · sample status'), findsOneWidget);
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
    for (final size in [const Size(320, 740), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      for (final path in [
        '/login',
        '/workspaces',
        '/inbox',
        '/contacts',
        '/tickets',
        '/chat/ananya',
        '/more',
        '/settings',
      ]) {
        final router = createRouter(initialLocation: path);
        await tester.pumpWidget(
          ProviderScope(child: TelvoxApp(router: router)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: path);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
    }
  });

  testWidgets('render review images with bundled brand fonts', (tester) async {
    await renderWithRealShadows(() async {
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
        ('workspace', '/workspaces'),
        ('more', '/more'),
        ('contacts', '/contacts'),
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
        await saveReviewImage(tester, boundary, '${directory.path}/$name.png');
        expect(tester.takeException(), isNull, reason: path);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
      for (final name in [
        'message-actions',
        'chat-reply',
        'chat-reactions',
        'send-animation',
      ]) {
        final router = createRouter(initialLocation: '/chat/ananya');
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
        if (name == 'message-actions') {
          await tester.longPress(find.byType(MessageBubble).first);
          await tester.pumpAndSettle();
        } else if (name == 'chat-reply') {
          final last = find.descendant(
            of: find.byKey(const ValueKey('message-6')),
            matching: find.byType(MessageBubble),
          );
          await tester.drag(last, const Offset(70, 0));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField),
            'You’re welcome, Ananya! 🌿',
          );
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
        } else if (name == 'chat-reactions') {
          await tester.enterText(
            find.byType(TextField),
            'You’re welcome, Ananya!',
          );
          await tester.pump();
          await tester.tap(find.byTooltip('Send reply'));
          await tester.pumpAndSettle();
          await tester.longPress(find.byType(MessageBubble).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('👍'));
          await tester.pumpAndSettle();
        } else {
          await tester.enterText(
            find.byType(TextField),
            'Your order is on its way.\nWe’ll share your tracking link shortly. 🌿',
          );
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Send reply'));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));
        }
        await saveReviewImage(tester, boundary, '${directory.path}/$name.png');
        expect(tester.takeException(), isNull, reason: name);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      }
    });
  });
}
