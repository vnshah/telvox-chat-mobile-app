import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/composer.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

class FakeRecorder implements VoiceRecorder {
  bool started = false, cancelled = false, paused = false;
  final level = StreamController<double>.broadcast();
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
  Future<void> pause() async => paused = true;
  @override
  Future<void> resume() async => paused = false;
  @override
  Stream<double> levels() => level.stream;
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
      'Camera',
      'Location',
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

  group('voice notes as WhatsApp records them', () {
    late FakeRecorder recorder;
    Attachment? note;

    Future<TestGesture> hold(WidgetTester tester) async {
      recorder = FakeRecorder();
      note = null;
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
      await tester.pump();
      return gesture;
    }

    testWidgets('recording starts on touch, with the lock above the mic', (
      tester,
    ) async {
      final gesture = await hold(tester);
      // No long-press wait: the press itself starts it.
      expect(recorder.started, isTrue);
      expect(find.text('Slide to cancel'), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-lock')), findsOneWidget);
      // Held a moment, the hint says what the lock is for.
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Slide up to lock recording'), findsOneWidget);
      await gesture.up();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(note, isNotNull);
    });

    testWidgets('sliding up locks it: Pause, Resume and Send, hands free', (
      tester,
    ) async {
      final gesture = await hold(tester);
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      // Locked: letting go keeps recording.
      await gesture.up();
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.byTooltip('Delete recording'), findsOneWidget);
      expect(find.byTooltip('Send voice note'), findsOneWidget);
      expect(find.text('Slide to cancel'), findsNothing);
      expect(note, isNull);

      // The waveform follows the microphone.
      recorder.level
        ..add(.2)
        ..add(.9);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:03'), findsOneWidget);

      // Paused, the clock stops; resumed, it goes on.
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(recorder.paused, isTrue);
      expect(find.text('Resume'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0:03'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.paused, isFalse);
      expect(find.text('0:04'), findsOneWidget);

      await tester.tap(find.byTooltip('Send voice note'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(note?.kind, 'audio');
      expect(find.text('Pause'), findsNothing);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('a locked recording deleted is never sent', (tester) async {
      final gesture = await hold(tester);
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byTooltip('Delete recording'));
      await tester.pumpAndSettle();
      expect(recorder.cancelled, isTrue);
      expect(note, isNull);
      expect(find.text('Pause'), findsNothing);
    });

    testWidgets('sliding left drops the mic into the bin', (tester) async {
      final gesture = await hold(tester);
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      // Half way, it is still recording; the mic has followed the finger.
      expect(recorder.cancelled, isFalse);
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 450));
      expect(recorder.cancelled, isTrue);
      expect(find.byKey(const ValueKey('voice-bin')), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      // The bin goes, the message box is back, nothing was sent.
      expect(find.byKey(const ValueKey('voice-bin')), findsNothing);
      expect(find.byTooltip('Emoji'), findsOneWidget);
      expect(note, isNull);
    });

    testWidgets('a tap says how to record, and sends nothing', (tester) async {
      final gesture = await hold(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Hold to record, release to send.'), findsOneWidget);
      expect(recorder.cancelled, isTrue);
      expect(note, isNull);
    });

    testWidgets('leaving the app pauses a locked note, kept for later', (
      tester,
    ) async {
      final gesture = await hold(tester);
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // Kept, paused, for Resume, Delete or Send on return.
      expect(recorder.paused, isTrue);
      expect(find.text('Resume'), findsOneWidget);
      expect(recorder.cancelled, isFalse);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.byTooltip('Delete recording'));
      await tester.pumpAndSettle();
    });

    testWidgets('leaving the app while holding drops the note', (tester) async {
      final gesture = await hold(tester);
      await tester.pump(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(recorder.cancelled, isTrue);
      expect(note, isNull);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(note, isNull);
    });
  });
}
