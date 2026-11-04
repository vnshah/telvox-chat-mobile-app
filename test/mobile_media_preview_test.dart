import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'mobile_attachments_test.dart' show temp, jpeg;
import 'mobile_voice_note_test.dart' show FakePlayers;

/// WhatsApp's media preview: the photo or video grows out of its bubble
/// over a fading black, and goes back into it, the chat where it was.
void main() {
  late ScrollController scroll;

  Future<void> chat(WidgetTester tester, MessageMedia media) async {
    scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              for (var i = 0; i < 12; i++)
                SizedBox(height: 60, child: Text('Message $i')),
              Align(
                alignment: Alignment.centerLeft,
                child: MediaFrame(
                  media,
                  heroTag: 'media-41',
                  title: 'Asha Mehta',
                  subtitle: 'Today, 10:24 AM',
                  caption: 'The new stock',
                ),
              ),
              for (var i = 12; i < 24; i++)
                SizedBox(height: 60, child: Text('Message $i')),
            ],
          ),
        ),
      ),
    );
    scroll.jumpTo(420);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(MediaFrame));
    // The photo's shape is asked for first (at most 300 ms).
    await tester.pump(const Duration(milliseconds: 350));
  }

  double backdrop(WidgetTester tester) => tester
      .widget<ColoredBox>(find.byKey(const ValueKey('media-preview-backdrop')))
      .color
      .a;

  MessageMedia photo() => MessageMedia(
    'image',
    Uri.file(temp('preview.jpg', jpeg).path),
    'preview.jpg',
  );

  testWidgets('a photo grows out over a fading black, and goes back', (
    tester,
  ) async {
    await chat(tester, photo());
    await open(tester);

    // Part way: the chat shows through a black that is still coming in.
    await tester.pump(const Duration(milliseconds: 100));
    final midway = backdrop(tester);
    expect(midway, greaterThan(0));
    expect(midway, lessThan(1));

    await tester.pumpAndSettle();
    expect(backdrop(tester), 1);
    expect(find.text('Asha Mehta'), findsOneWidget);
    expect(find.text('Today, 10:24 AM'), findsOneWidget);
    expect(find.text('The new stock'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('media-preview-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Closing fades the black away again, not at once.
    expect(backdrop(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-preview')), findsNothing);
    // Back where the chat was.
    expect(scroll.offset, 420);
  });

  testWidgets('a tap hides the bars and shows them again', (tester) async {
    await chat(tester, photo());
    await open(tester);
    await tester.pumpAndSettle();
    double bars() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text('Asha Mehta'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(bars(), 1);
    // A single tap waits out the double-tap window, then toggles.
    await tester.tap(find.byKey(const ValueKey('media-preview')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(bars(), 0);
    await tester.tap(find.byKey(const ValueKey('media-preview')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(bars(), 1);
  });

  testWidgets('dragged down it closes; a short drag springs back', (
    tester,
  ) async {
    await chat(tester, photo());
    await open(tester);
    await tester.pumpAndSettle();

    // A little way: the black thins under the finger, then comes back.
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    expect(backdrop(tester), lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-preview')), findsOneWidget);
    expect(backdrop(tester), 1);

    // Far enough: it goes back into its bubble.
    await tester.timedDragFrom(
      const Offset(400, 200),
      const Offset(0, 320),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-preview')), findsNothing);
    expect(scroll.offset, 420);
  });

  testWidgets('a double tap zooms; zoomed in, a drag pans instead', (
    tester,
  ) async {
    await chat(tester, photo());
    await open(tester);
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('media-preview'));
    await tester.tap(preview);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(preview);
    await tester.pumpAndSettle();
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    expect(zoom.value.getMaxScaleOnAxis(), greaterThan(1));

    await tester.timedDragFrom(
      const Offset(400, 200),
      const Offset(0, 320),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-preview')), findsOneWidget);
  });

  group('videos', () {
    late FakePlayers players;
    setUp(() => VideoPlayerPlatform.instance = players = FakePlayers());

    testWidgets('play at once, with pause, seek and speed', (tester) async {
      await chat(
        tester,
        MessageMedia(
          'video',
          Uri.file(temp('clip.mp4', [0, 0, 0, 24]).path),
          'clip.mp4',
        ),
      );
      await tester.tap(find.byType(MediaFrame));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('media-preview-video')), findsOneWidget);
      expect(players.playing, isNotEmpty);
      expect(find.byKey(const ValueKey('media-preview-seek')), findsOneWidget);
      expect(find.text('00:06'), findsOneWidget);

      // Faster while it plays.
      await tester.tap(find.byKey(const ValueKey('media-preview-speed')));
      await tester.pumpAndSettle();
      expect(find.text('1.5x'), findsOneWidget);
      expect(players.speeds.values, contains(1.5));

      await tester.tap(find.byKey(const ValueKey('media-preview-play')));
      await tester.pumpAndSettle();
      expect(players.playing, isEmpty);

      await tester.tap(find.byKey(const ValueKey('media-preview-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('media-preview')), findsNothing);
    });
  });
}
