import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/composer.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

class FakeRecorder implements VoiceRecorder {
  bool started = false, cancelled = false;
  String? file;
  @override
  Future<bool> start() async => started = true;
  @override
  Future<String?> stop() async {
    final f = File('${Directory.systemTemp.path}/composer-test.m4a')
      ..writeAsBytesSync(List.filled(64, 1));
    return file = f.path;
  }

  @override
  Future<void> cancel() async => cancelled = true;
  @override
  void dispose() {}
}

Widget host(Widget child) => MaterialApp(
  theme: T.themeFor(TargetPlatform.android),
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

void main() {
  testWidgets('the mic turns into send as you type, and reply sits inside', (
    tester,
  ) async {
    final controller = TextEditingController();
    var sent = 0, cancelled = 0;
    await tester.pumpWidget(
      host(
        ChatComposer(
          controller: controller,
          onSend: () => sent++,
          onAttach: () {},
          onQuickReplies: () {},
          onVoiceNote: (_) {},
          replyAuthor: 'Alex',
          replyText: 'Is my order ready?',
          onCancelReply: () => cancelled++,
          recorder: FakeRecorder(),
        ),
      ),
    );
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Is my order ready?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Yes, shipping today');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.send), findsOneWidget);
    await tester.tap(find.byTooltip('Send message'));
    await tester.tap(find.byTooltip('Cancel reply'));
    expect(sent, 1);
    expect(cancelled, 1);
  });

  testWidgets('holding the mic records and releasing sends a voice note', (
    tester,
  ) async {
    final recorder = FakeRecorder();
    Attachment? note;
    await tester.pumpWidget(
      host(
        ChatComposer(
          controller: TextEditingController(),
          onSend: () {},
          onAttach: () {},
          onQuickReplies: () {},
          onVoiceNote: (a) => note = a,
          recorder: recorder,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    expect(recorder.started, isTrue);
    expect(find.text('Slide to cancel'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:02'), findsOneWidget);
    await gesture.up();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(note?.kind, 'audio');
    expect(recorder.cancelled, isFalse);
  });

  testWidgets('sliding left while recording cancels the voice note', (
    tester,
  ) async {
    final recorder = FakeRecorder();
    Attachment? note;
    await tester.pumpWidget(
      host(
        ChatComposer(
          controller: TextEditingController(),
          onSend: () {},
          onAttach: () {},
          onQuickReplies: () {},
          onVoiceNote: (a) => note = a,
          recorder: recorder,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 2));
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(recorder.cancelled, isTrue);
    expect(note, isNull);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });

  testWidgets('the attach sheet offers WhatsApp-style choices', (tester) async {
    AttachChoice? picked;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await showAttachSheet(context, templates: true),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final label in [
      'Document',
      'Gallery',
      'Audio',
      'Quick replies',
      'Template',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(picked, AttachChoice.gallery);
  });
}
