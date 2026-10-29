import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/app/app.dart';
import 'package:telvox_chat_mobile_app/ui/conversation.dart';
import 'package:telvox_chat_mobile_app/ui/data.dart';

import 'support/ui.dart';

class _ChatPreview extends PreviewController {
  _ChatPreview(this.messages);
  final List<Message> messages;
  @override
  UiState build() => super.build().copy(messages: {'ananya': messages});
}

Finder _bubble(int index) => find.descendant(
  of: find.byKey(ValueKey('message-$index')),
  matching: find.byType(MessageBubble),
);

Future<void> _chat(
  WidgetTester tester,
  List<Message> messages, {
  TargetPlatform platform = TargetPlatform.android,
  GlobalKey? boundary,
}) async {
  final router = createRouter(initialLocation: '/chat/ananya');
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [previewProvider.overrideWith(() => _ChatPreview(messages))],
      child: RepaintBoundary(
        key: boundary,
        child: TelvoxApp(router: router, platform: platform),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiFonts);
  setUp(() {
    final tester = TestWidgetsFlutterBinding.instance;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  });

  testWidgets(
    'short bubbles fit their text and receipts never cover characters',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const messages = [
        Message('Hi'),
        Message('Hi', out: true),
        Message(
          'A longer message that wraps across several lines and finishes here.',
          out: true,
        ),
        Message('Line one\nA final line with more words'),
      ];
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _chat(tester, messages);
        if (scale == 1) {
          expect(tester.getSize(_bubble(0)).width, lessThan(100));
          expect(tester.getSize(_bubble(1)).width, lessThan(120));
          expect(tester.getSize(_bubble(0)).height, lessThan(36));
          expect(tester.getSize(_bubble(1)).height, lessThan(36));
          expect(find.byTooltip('Message options'), findsNothing);
        }
        for (var i = 0; i < messages.length; i++) {
          final body = find.descendant(
            of: _bubble(i),
            matching: find.byKey(const ValueKey('message-body-text')),
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: body, matching: find.byType(RichText)),
          );
          final stamp = tester.getRect(
            find.descendant(
              of: _bubble(i),
              matching: find.byKey(const ValueKey('message-receipt')),
            ),
          );
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: messages[i].text.length),
          )) {
            final characters = box.toRect().shift(
              paragraph.localToGlobal(Offset.zero),
            );
            expect(
              characters.overlaps(stamp),
              isFalse,
              reason: 'Message $i receipt covers text at scale $scale',
            );
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'consecutive messages group tightly and time gaps start a new group',
    (tester) async {
      await _chat(tester, const [
        Message('Hello', time: '10:24'),
        Message('Can you help?', time: '10:24'),
        Message('Of course', out: true, time: '10:25'),
        Message('One moment', out: true, time: '10:25'),
        Message('Here is the update', out: true, time: '10:40'),
      ]);
      double gap(int before, int after) =>
          tester.getTopLeft(_bubble(after)).dy -
          tester.getBottomLeft(_bubble(before)).dy;
      expect(gap(0, 1), closeTo(2, .1));
      expect(gap(1, 2), closeTo(8, .1));
      expect(gap(2, 3), closeTo(2, .1));
      expect(gap(3, 4), closeTo(8, .1));
      expect(tester.widget<MessageBubble>(_bubble(1)).first, isFalse);
      expect(tester.widget<MessageBubble>(_bubble(4)).first, isTrue);
    },
  );

  testWidgets(
    'emoji sizing respects joined sequences and mixed text stays normal',
    (tester) async {
      await _chat(tester, const [
        Message('Hi'),
        Message('👍🏽'),
        Message('👨‍👩‍👧‍👦'),
        Message('Hi 👍🏽'),
        Message('123'),
      ]);
      expect(
        tester.getSize(_bubble(1)).height,
        greaterThan(tester.getSize(_bubble(0)).height + 20),
      );
      expect(
        tester.getSize(_bubble(2)).height,
        greaterThan(tester.getSize(_bubble(0)).height + 20),
      );
      expect(tester.getSize(_bubble(3)).height, lessThan(40));
      expect(tester.getSize(_bubble(4)).height, lessThan(40));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reactions attach below content, can be changed and removed', (
    tester,
  ) async {
    await _chat(tester, const [Message('Thanks!', out: true)]);
    await tester.longPress(_bubble(0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 80));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-action-menu')), findsNothing);
    await tester.longPress(_bubble(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('React with 👍'));
    await tester.pumpAndSettle();
    final badge = find.byKey(const ValueKey('message-reaction-0'));
    final receipt = find.descendant(
      of: _bubble(0),
      matching: find.byKey(const ValueKey('message-receipt')),
    );
    final body = find.descendant(
      of: _bubble(0),
      matching: find.byKey(const ValueKey('message-body-text')),
    );
    expect(
      tester.getTopLeft(badge).dy,
      greaterThan(tester.getBottomLeft(body).dy),
    );
    expect(
      tester.getTopLeft(badge).dy,
      greaterThan(tester.getBottomLeft(receipt).dy),
    );
    expect(
      tester.getTopLeft(badge).dy,
      lessThan(tester.getBottomLeft(_bubble(0)).dy),
    );
    await tester.longPress(_bubble(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('React with 👍'));
    await tester.pumpAndSettle();
    expect(badge, findsNothing);
    await tester.longPress(_bubble(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More reactions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('React with 🔥'));
    await tester.pumpAndSettle();
    expect(find.text('🔥'), findsOneWidget);
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(find.text('Reactions'), findsOneWidget);
    await tester.tap(find.text('Tap to remove'));
    await tester.pumpAndSettle();
    expect(badge, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'message menus keep the selection readable above a keyboard on both platforms',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        await _chat(tester, [
          Message('A long message for a small screen. ' * 12, out: true),
        ], platform: platform);
        final rect = tester.getRect(_bubble(0));
        await tester.longPressAt(Offset(rect.right - 30, rect.bottom - 20));
        await tester.pumpAndSettle();
        final reaction = tester.getRect(
          find.byKey(const ValueKey('message-reaction-picker')),
        );
        final preview = tester.getRect(
          find.byKey(const ValueKey('selected-message-preview')),
        );
        final menu = tester.getRect(
          find.byKey(const ValueKey('message-action-menu')),
        );
        expect(reaction.top, greaterThanOrEqualTo(0));
        expect(preview.top, greaterThan(reaction.bottom));
        expect(menu.top, greaterThan(preview.bottom));
        expect(menu.bottom, lessThanOrEqualTo(480));
        expect(menu.right, lessThanOrEqualTo(320));
        final selected = find.descendant(
          of: find.byKey(const ValueKey('selected-message-preview')),
          matching: find.byType(MessageBubble),
        );
        expect(
          DefaultTextStyle.of(tester.element(selected)).style.fontFamily,
          isNot('Ahem'),
        );
        await tester.ensureVisible(find.text('Message info'));
        await tester.tap(find.text('Message info'));
        await tester.pumpAndSettle();
        expect(find.text('Message info'), findsOneWidget);
        expect(find.byKey(const ValueKey('message-action-menu')), findsNothing);
        expect(tester.takeException(), isNull, reason: '$platform');
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('render compact chat and selected-message previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory('build/ui-previews/chat-behavior')
      ..createSync(recursive: true);
    const messages = [
      Message('Hi 👋', time: '10:24'),
      Message('Hi Ananya!', out: true, time: '10:24'),
      Message('Is the everyday tote available in natural?', time: '10:25'),
      Message('Yes, it is 😊', out: true, time: '10:25'),
      Message('Would you like us to keep one aside?', out: true, time: '10:25'),
      Message('That would be lovely', time: '10:26'),
      Message('Can I collect it this afternoon?', time: '10:26'),
      Message('Of course. We are here until 6.', out: true, time: '10:27'),
      Message('Perfect!', time: '10:27', reaction: '🤍'),
      Message('I’ll be there around 4.', time: '10:27'),
      Message(
        'See you then',
        out: true,
        time: '10:28',
        reply: 'I’ll be there around 4.',
        replyAuthor: 'Ananya',
      ),
      Message('👍🏽', time: '10:28'),
    ];
    await renderWithRealShadows(() async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final boundary = GlobalKey();
        await _chat(tester, messages, platform: platform, boundary: boundary);
        await saveReviewImage(
          tester,
          boundary,
          '${directory.path}/${platform.name}-chat.png',
        );
        await tester.longPress(_bubble(10));
        await tester.pumpAndSettle();
        await saveReviewImage(
          tester,
          boundary,
          '${directory.path}/${platform.name}-actions.png',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
