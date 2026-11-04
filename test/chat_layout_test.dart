import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/ui/conversation.dart';
import 'package:telvox_chat_mobile_app/ui/data.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

Finder _bubble(int index) => find.byKey(ValueKey('bubble-$index'));

/// The chat's bubbles, one under another, as a conversation lays them out.
Future<void> _bubbles(WidgetTester tester, List<Message> messages) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: T.themeFor(TargetPlatform.android),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            for (var i = 0; i < messages.length; i++)
              Align(
                alignment: messages[i].out
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: MessageBubble(
                  key: ValueKey('bubble-$i'),
                  message: messages[i],
                  maxWidth: 260,
                ),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiFonts);

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
        await _bubbles(tester, messages);
        if (scale == 1) {
          expect(tester.getSize(_bubble(0)).width, lessThan(100));
          expect(tester.getSize(_bubble(1)).width, lessThan(120));
          expect(tester.getSize(_bubble(0)).height, lessThan(36));
          expect(tester.getSize(_bubble(1)).height, lessThan(36));
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
    'emoji sizing respects joined sequences and mixed text stays normal',
    (tester) async {
      await _bubbles(tester, const [
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

  testWidgets('swiping a bubble right starts a reply', (tester) async {
    var replies = 0;
    VoidCallback? onReply = () => replies++;
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(
          body: Center(
            child: SwipeReply(
              onReply: onReply,
              child: const MessageBubble(message: Message('Is it ready?')),
            ),
          ),
        ),
      ),
    );
    await show();
    await tester.drag(find.byType(MessageBubble), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(replies, 1);

    // A short nudge is not a reply.
    await tester.drag(find.byType(MessageBubble), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(replies, 1);

    // A message still sending cannot be replied to yet.
    onReply = null;
    await show();
    await tester.drag(find.byType(MessageBubble), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(replies, 1);
  });
}
