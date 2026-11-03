import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/composer.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_composer_test.dart' show FakeRecorder;
import 'support/ui.dart';

/// Review images of recording a voice note, as in WhatsApp: held with the
/// lock above the mic, locked hands-free, and cancelled into the bin.
void main() {
  testWidgets('voice recording renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recorder = FakeRecorder();
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Scaffold(
              backgroundColor: const Color(0xFFEFE7DE),
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  controller: TextEditingController(),
                  onSend: () {},
                  onAttach: () {},
                  onQuickReplies: () {},
                  onVoiceNote: (_) {},
                  onCamera: () {},
                  recorder: recorder,
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic)),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      await saveReviewImage(tester, boundary, 'build/review/voice-holding.png');

      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      for (final level in [
        .1,
        .3,
        .6,
        .4,
        .8,
        .5,
        .2,
        .7,
        .9,
        .6,
        .3,
        .5,
        .8,
        .4,
        .6,
        .2,
        .5,
        .7,
        .3,
        .6,
        .9,
        .5,
        .4,
        .7,
        .3,
        .2,
        .6,
        .8,
        .5,
        .3,
        .7,
        .4,
        .6,
        .9,
        .5,
        .3,
        .2,
        .4,
      ]) {
        recorder.level.add(level);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await saveReviewImage(tester, boundary, 'build/review/voice-locked.png');
      await tester.tap(find.byTooltip('Delete recording'));
      await tester.pumpAndSettle();

      // Again, and slid away: the mic on its way into the bin.
      final again = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic)),
      );
      await tester.pump(const Duration(seconds: 1));
      await again.moveBy(const Offset(-140, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 520));
      await saveReviewImage(tester, boundary, 'build/review/voice-bin.png');
      await again.up();
      await tester.pumpAndSettle();
    });
    expect(tester.takeException(), isNull);
  });
}
