import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// A review image of a reply quoting a voice note.
void main() {
  testWidgets('a quoted voice note renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = File('test/fixtures/voice-note.ogg').readAsBytesSync();
    VoiceNoteFile.fetch = (_) async => fixture;
    await tester.runAsync(
      () => VoiceNoteFile.of(
        Uri.parse('https://chat.telvox.dev/storage/1/2/audio/review-note.ogg'),
      ),
    );
    ApiMessage reply(int id, int type, String body) => ApiMessage({
      'id': id,
      'type': type,
      'message_type': 'text',
      'message_body': body,
      'contextual_message': '1290380475521734',
      'contextual_message_type': 'audio',
      'contextual_message_json': jsonEncode({
        'type': 'audio',
        'media_path': 'storage/1/2/audio/review-note.ogg',
      }),
      'created_at': '2026-11-05T08:00:00Z',
    });
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Scaffold(
              backgroundColor: T.chatWallpaper,
              body: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  LiveMessageView(
                    message: reply(1, 1, 'Got it, I will check the stock'),
                    apiBase: 'https://chat.telvox.dev/api/mobile/v1/',
                    first: true,
                    contactName: 'Priya Shah',
                  ),
                  LiveMessageView(
                    message: reply(2, 2, 'Did you hear my note?'),
                    apiBase: 'https://chat.telvox.dev/api/mobile/v1/',
                    first: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/quoted-audio.png');
    });
  });
}
