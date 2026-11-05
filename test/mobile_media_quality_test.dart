import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/media_quality.dart';
import 'package:telvox_chat_mobile_app/mobile/send_media.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_media.dart';
import 'mobile_attachments_test.dart' show temp, jpeg;
import 'mobile_voice_note_test.dart' show FakePlayers;

const mb = 1024 * 1024;

/// A phone's video: [seconds] long, [width] × [height] upright.
VideoInfo clip(
  int seconds, {
  int width = 1080,
  int height = 1920,
  int? bitrate = 4000000,
}) => VideoInfo(
  duration: Duration(seconds: seconds),
  width: width,
  height: height,
  bytes: (bitrate ?? 4000000) * seconds ~/ 8,
  bitrate: bitrate,
);

Attachment photo([String name = 'IMG_1.jpg']) =>
    Attachment(temp(name, jpeg), 'image', jpeg.length, 'image/jpeg');

Attachment video([String name = 'VID_1.mp4', int size = 30 * mb]) =>
    Attachment(temp(name, jpeg), 'video', size, 'video/mp4');

void main() {
  group('videos are planned as WhatsApp sends them', () {
    test('a 30 MB minute goes at 480p for Standard, 720p for HD', () {
      final minute = clip(60);
      final standard = planVideo(minute, MediaQuality.standard)!;
      expect(standard.quality, MediaQuality.standard);
      expect(standard.shortSide, 480);
      expect(standard.videoBitrate, VideoSpec.standard.bitrate);
      expect(standard.estimate, lessThan(10 * mb));

      final hd = planVideo(minute, MediaQuality.hd)!;
      expect(hd.quality, MediaQuality.hd);
      expect(hd.shortSide, 720);
      // HD spends only what a minute can within 16 MB, and still fits.
      expect(hd.videoBitrate, lessThan(VideoSpec.hd.bitrate));
      expect(hd.videoBitrate, greaterThan(VideoSpec.hd.floor));
      expect(hd.estimate, lessThanOrEqualTo(maxVideoBytes));
    });

    test('a short clip keeps the full HD bitrate', () {
      final hd = planVideo(clip(10), MediaQuality.hd)!;
      expect(hd.videoBitrate, VideoSpec.hd.bitrate);
    });

    test('a small video is never made larger or given more bits', () {
      final small = planVideo(
        clip(20, width: 640, height: 360, bitrate: 600000),
        MediaQuality.hd,
      )!;
      expect(small.shortSide, 360);
      expect(small.videoBitrate, VideoSpec.hd.floor);
      final standard = planVideo(
        clip(20, width: 640, height: 360, bitrate: 600000),
        MediaQuality.standard,
      )!;
      expect(standard.videoBitrate, 600000);
    });

    test('HD that would break up falls back to Standard', () {
      final plan = planVideo(clip(150), MediaQuality.hd)!;
      expect(plan.quality, MediaQuality.standard);
      expect(plan.shortSide, 480);
      expect(plan.estimate, lessThanOrEqualTo(maxVideoBytes));
    });

    test('too long for 16 MB at any quality cannot be sent', () {
      expect(planVideo(clip(5 * 60), MediaQuality.standard), isNull);
      expect(planVideo(clip(5 * 60), MediaQuality.hd), isNull);
      final longest = longestVideo(MediaQuality.standard);
      expect(longest.inSeconds, inInclusiveRange(200, 240));
      expect(
        planVideo(clip(longest.inSeconds), MediaQuality.standard),
        isNotNull,
      );
    });
  });

  group('media is made to fit before it is sent', () {
    test('a photo is tried smaller until it is within 5 MB', () async {
      final codec = FakeCompressor(photoBytes: [6 * mb, 3 * mb]);
      final sent = await prepareMedia(
        photo('IMG_0042.heic'),
        MediaQuality.standard,
        compressor: codec,
      );
      expect(codec.calls, ['photo 2048 80', 'photo 2048 70']);
      expect(sent.mime, 'image/jpeg');
      expect(sent.name, 'attach-test-IMG_0042.jpg');
      expect(sent.size, 3 * mb);
    });

    test('HD keeps a photo near its own size', () async {
      final codec = FakeCompressor(photoBytes: [2 * mb]);
      await prepareMedia(photo(), MediaQuality.hd, compressor: codec);
      expect(codec.calls, ['photo 4096 90']);
    });

    test('a photo that will not fit says so', () async {
      final codec = FakeCompressor(photoBytes: [6 * mb]);
      await expectLater(
        prepareMedia(photo(), MediaQuality.hd, compressor: codec),
        throwsA(isA<ApiFailure>()),
      );
      expect(codec.calls, hasLength(photoSteps[MediaQuality.hd]!.length));
    });

    test('a video is encoded at the chosen quality, with progress', () async {
      final codec = FakeCompressor(info: clip(60));
      final done = <double>[];
      final sent = await prepareMedia(
        video('clip.mov'),
        MediaQuality.hd,
        compressor: codec,
        progress: done.add,
      );
      expect(codec.calls, ['video hd 720']);
      expect(done, [.5, 1]);
      expect((sent.name, sent.mime), ('attach-test-clip.mp4', 'video/mp4'));
    });

    test('a video too long to fit is refused with how long fits', () async {
      await expectLater(
        prepareMedia(
          video(),
          MediaQuality.standard,
          compressor: FakeCompressor(info: clip(10 * 60)),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('min'),
          ),
        ),
      );
    });

    test('without an encoder, only a video within 16 MB goes', () async {
      final none = FakeCompressor();
      final small = video('small.mp4', 5 * mb);
      expect(
        await prepareMedia(small, MediaQuality.standard, compressor: none),
        same(small),
      );
      await expectLater(
        prepareMedia(video(), MediaQuality.standard, compressor: none),
        throwsA(isA<ApiFailure>()),
      );
    });

    test('documents and audio go as they are', () async {
      final pdf = Attachment(
        temp('quote.pdf', [1, 2]),
        'document',
        2,
        'application/pdf',
      );
      expect(
        await prepareMedia(pdf, MediaQuality.hd, compressor: FakeCompressor()),
        same(pdf),
      );
    });

    test('estimates add up, and a too-long video is told apart', () async {
      final codec = FakeCompressor(info: clip(60));
      final e = await estimateMedia(video(), compressor: codec);
      expect(e.tooLong, isFalse);
      expect(
        e.sizes![MediaQuality.hd]!,
        greaterThan(e.sizes![MediaQuality.standard]!),
      );
      final long = await estimateMedia(
        video(),
        compressor: FakeCompressor(info: clip(10 * 60)),
      );
      expect(long.tooLong, isTrue);
      expect(
        MediaEstimate.total([e, e])![MediaQuality.standard],
        e.sizes![MediaQuality.standard]! * 2,
      );
    });
  });

  group('the send preview', () {
    MediaBatch? result;
    var closed = false;

    Future<void> open(WidgetTester tester, List<Attachment> items) async {
      result = null;
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<MediaBatch>(
                  MaterialPageRoute(
                    builder: (_) => SendMediaPage(items, recipient: 'Priya'),
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    setUp(() {
      mediaCompressor = FakeCompressor(info: clip(60));
      VideoPlayerPlatform.instance = FakePlayers();
    });

    testWidgets('sends every item with its caption at the one quality', (
      tester,
    ) async {
      await open(tester, [photo('a.jpg'), photo('b.jpg'), video('c.mp4')]);
      expect(find.text('Priya'), findsOneWidget);
      // The count by Send, as WhatsApp shows it.
      expect(find.text('3'), findsOneWidget);
      expect(find.byTooltip('Media quality: Standard'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'First one');
      await tester.tap(find.byKey(const ValueKey('thumb-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Second one');

      // HD for all of them, with about how large each choice is.
      await tester.tap(find.byKey(const ValueKey('quality-button')));
      await tester.pumpAndSettle();
      expect(find.text('Media quality'), findsOneWidget);
      expect(find.textContaining('about'), findsNWidgets(2));
      await tester.tap(find.text('HD quality'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Media quality: HD'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('send-media')));
      await tester.pumpAndSettle();
      expect(result!.quality, MediaQuality.hd);
      expect(result!.items.map((i) => (i.$1.name, i.$2)), [
        ('attach-test-a.jpg', 'First one'),
        ('attach-test-b.jpg', 'Second one'),
        ('attach-test-c.mp4', ''),
      ]);
    });

    testWidgets('an item can be removed; removing the last cancels', (
      tester,
    ) async {
      await open(tester, [photo('a.jpg'), photo('b.jpg')]);
      await tester.tap(find.byKey(const ValueKey('remove-media')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thumb-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('remove-media')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('a video too long to send holds Send until it is removed', (
      tester,
    ) async {
      mediaCompressor = FakeCompressor(info: clip(10 * 60));
      await open(tester, [video('long.mp4'), photo('a.jpg')]);
      expect(find.byKey(const ValueKey('too-long')), findsOneWidget);
      final send = tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('send-media')),
      );
      expect(send.onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('remove-media')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('too-long')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('send-media')));
      await tester.pumpAndSettle();
      expect(result!.items.single.$1.name, 'attach-test-a.jpg');
    });
  });
}
