import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/mobile/voice_waveform.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// About six seconds of speech: a sentence, a 1.5 s pause, another sentence.
final fixture = File('test/fixtures/voice-note.ogg').readAsBytesSync();

const api = 'https://chat.telvox.dev/api/mobile';

Map<String, dynamic> row(
  int id,
  int type,
  String kind,
  Object body, {
  String text = '',
}) => {
  'id': id,
  'type': type,
  'message_type': kind,
  'message_body': text,
  'message_body_json': body,
  'message_status': 3,
  'created_at': '2026-10-31T09:0$id:00Z',
};

double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

void main() {
  test(
    'the waveform follows the voice note and its length is read from the file',
    () {
      final wave = VoiceWaveform.read(fixture, count: 40)!;
      expect(wave.bars, hasLength(40));
      expect(wave.duration.inMilliseconds, closeTo(6200, 150));
      expect(wave.bars.every((b) => b >= 0 && b <= 1), true);
      // The pause between the sentences is a dip between two raised stretches.
      final first = mean(wave.bars.sublist(1, 14)),
          pause = mean(wave.bars.sublist(19, 24)),
          second = mean(wave.bars.sublist(28, 37));
      expect(pause, lessThan(.2));
      expect(first, greaterThan(.6));
      expect(second, greaterThan(.6));
      expect(VoiceWaveform.read(Uint8List.fromList([1, 2, 3])), isNull);
    },
  );

  test('a sent voice note plays from the public disk', () {
    expect(
      mediaUri(
        'https://chat.telvox.dev/media/voice-notes/9426555485/919099801380/voice-1-XyZ.ogg',
        api,
      ).toString(),
      'https://chat.telvox.dev/storage/9426555485/919099801380/audio/voice-1-XyZ.ogg',
    );
    // Another host's link is left alone.
    expect(
      mediaUri(
        'https://cdn.example.com/media/voice-notes/1/2/a.ogg',
        api,
      ).toString(),
      'https://cdn.example.com/media/voice-notes/1/2/a.ogg',
    );
  });

  testWidgets(
    'voice notes, audio files and calls keep the time on their last line',
    (tester) async {
      await loadUiFonts();
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VoiceNoteFile.fetch = (_) async => fixture;
      final voices = [
        'https://chat.telvox.dev/storage/1/2/audio/1',
        'https://chat.telvox.dev/storage/1/2/audio/voice-note-1-a.ogg',
      ];
      await tester.runAsync(() async {
        for (final url in voices) {
          await VoiceNoteFile.of(Uri.parse(url));
        }
      });
      final rows = [
        row(1, 2, 'audio', {
          'type': 'audio',
          'media_path': 'storage/1/2/audio/1',
          'media_mime_type': 'audio/ogg; codecs=opus',
        }),
        row(2, 1, 'audio', {
          'type': 'audio',
          'audio': {
            'link': 'https://chat.telvox.dev/media/voice-notes/1/2/voice-note-1-a.ogg',
            'voice': true,
          },
        }),
        row(3, 1, 'audio', {
          'type': 'audio',
          'audio': {
            'link': 'https://chat.telvox.dev/storage/1/2/audio/song.mp3',
            'filename': 'song.mp3',
          },
        }),
        row(4, 2, 'voice_call', 'Start calling...'),
        row(5, 2, 'document', {
          'type': 'document',
          'media_path': 'storage/1/2/document/invoice.pdf',
          'media_name': 'invoice.pdf',
          'media_size': '1 MB',
        }),
      ];
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Scaffold(
              backgroundColor: const Color(0xFFEFE7DE),
              body: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final r in rows)
                    LiveMessageView(
                      message: ApiMessage(r),
                      apiBase: api,
                      first: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      // The voice notes were fetched on the real event loop; let it deliver them.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Both voice notes draw a waveform and know their length before playing.
      expect(find.byKey(const ValueKey('voice-waveform')), findsNWidgets(2));
      expect(find.text('0:06'), findsNWidgets(2));
      // An audio file is a plain track.
      expect(find.byKey(const ValueKey('audio-track')), findsOneWidget);
      // Each audio row's time shares the line with its length, and the call's
      // time sits on the call row: no bubble adds a line just for the time.
      for (final view in find.byType(LiveMessageView).evaluate().take(4)) {
        final bubble = find.byWidget(view.widget);
        final stamp = find.descendant(
          of: bubble,
          matching: find.byKey(const ValueKey('message-receipt')),
        );
        expect(stamp, findsOneWidget);
        final bottom = tester.getRect(bubble).bottom;
        expect(bottom - tester.getRect(stamp).bottom, lessThan(16));
      }
      // An outgoing voice note puts the sender's avatar after the waveform.
      final outgoing = find.byWidget(
        find.byType(LiveMessageView).evaluate().elementAt(1).widget,
      );
      expect(
        tester
            .getCenter(
              find.descendant(
                of: outgoing,
                matching: find.byKey(const ValueKey('audio-avatar')),
              ),
            )
            .dx,
        greaterThan(
          tester
              .getCenter(
                find.descendant(
                  of: outgoing,
                  matching: find.byKey(const ValueKey('voice-waveform')),
                ),
              )
              .dx,
        ),
      );
      Directory('build/review').createSync(recursive: true);
      await saveReviewImage(
        tester,
        boundary,
        'build/review/live-audio-call.png',
      );
    },
  );
}
