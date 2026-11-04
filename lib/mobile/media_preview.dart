import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';
import 'media.dart';

/// Opens a photo or video full screen as WhatsApp does: it grows out of its
/// bubble ([heroTag] names it there) while the chat fades to black, and
/// shrinks back into it on close. The chat stays beneath, where it was.
Future<void> openMediaPreview(
  BuildContext context,
  MessageMedia media, {
  required Object heroTag,
  String title = '',
  String subtitle = '',
  String caption = '',
}) async {
  final navigator = Navigator.of(context);
  // The photo's own shape, known before the flight so it lands without a
  // jump. It is drawn in the bubble already, so this is immediate.
  final aspect = media.type == 'video'
      ? null
      : await imageAspect(mediaImage(media.url));
  await navigator.push(
    MediaPreviewRoute<void>(
      MediaPreview(
        media,
        heroTag: heroTag,
        title: title,
        subtitle: subtitle,
        caption: caption,
        aspect: aspect,
      ),
    ),
  );
}

/// Width over height of [image], or null if it cannot be had at once.
Future<double?> imageAspect(ImageProvider image) {
  final done = Completer<double?>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(double? aspect) {
    if (!done.isCompleted) done.complete(aspect);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (info, _) => finish(info.image.width / math.max(1, info.image.height)),
    onError: (_, _) => finish(null),
  );
  stream.addListener(listener);
  return done.future.timeout(
    const Duration(milliseconds: 300),
    onTimeout: () {
      stream.removeListener(listener);
      return null;
    },
  );
}

/// A see-through route: the chat stays drawn beneath while the preview's
/// black fades in over it, and the media flies between the two.
class MediaPreviewRoute<R> extends PageRoute<R> {
  MediaPreviewRoute(this.page);
  final Widget page;

  @override
  bool get opaque => false;
  @override
  bool get barrierDismissible => false;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => page;

  // The preview fades its own black and bars with [animation].
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// The bubble's picture and the preview's, drawn alike while flying: the
/// image filling the moving frame, its corners going from the bubble's
/// rounding to square.
Widget mediaFlight(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
  MessageMedia media,
) => AnimatedBuilder(
  animation: animation,
  builder: (context, _) => ClipRRect(
    borderRadius: BorderRadius.circular(lerpDouble(6.5, 0, animation.value)!),
    child: media.type == 'video'
        ? const ColoredBox(color: Colors.black)
        : Image(
            image: mediaImage(media.url),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
  ),
);

class MediaPreview extends StatefulWidget {
  const MediaPreview(
    this.media, {
    super.key,
    required this.heroTag,
    this.title = '',
    this.subtitle = '',
    this.caption = '',
    this.aspect,
  });
  final MessageMedia media;
  final Object heroTag;
  final String title, subtitle, caption;

  /// The photo's width over height, when known.
  final double? aspect;

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool get video => widget.media.type == 'video';

  /// The bars, shown until a tap hides them.
  bool chrome = true;

  /// How far the media has been dragged down to close.
  Offset drag = Offset.zero;
  bool dragging = false;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Offset>? _back;

  final _zoom = TransformationController();
  bool get zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  VideoPlayerController? player;
  String? error;
  double speed = 1;
  late double? aspect = widget.aspect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settle.addListener(() {
      final back = _back;
      if (back != null) setState(() => drag = back.value);
    });
    _zoom.addListener(() => setState(() {}));
    if (video) {
      unawaited(_startVideo());
    } else if (aspect == null) {
      unawaited(
        imageAspect(mediaImage(widget.media.url)).then((a) {
          if (mounted && a != null) setState(() => aspect = a);
        }),
      );
    }
  }

  Future<void> _startVideo() async {
    final controller = mediaPlayer(widget.media.url);
    player = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      // Played as soon as the preview has opened, as WhatsApp does.
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => error = 'This video could not be played.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settle.dispose();
    _zoom.dispose();
    player?.dispose();
    super.dispose();
  }

  /// 0 at rest, 1 when dragged a third of the screen down.
  double _dragShare(Size screen) =>
      (drag.dy.abs() / (screen.height / 3)).clamp(0.0, 1.0);

  void _dragStart(DragStartDetails _) {
    _settle.stop();
    setState(() => dragging = true);
  }

  void _dragUpdate(DragUpdateDetails d) =>
      setState(() => drag += Offset(d.delta.dx * .6, d.delta.dy));

  void _dragEnd(DragEndDetails d, Size screen) {
    final fast = d.velocity.pixelsPerSecond.dy.abs() > 700;
    if (fast || _dragShare(screen) > .35) {
      // Flies back into its bubble from where the finger left it.
      setState(() => dragging = false);
      Navigator.of(context).maybePop();
      return;
    }
    _back = Tween(
      begin: drag,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
    setState(() => dragging = false);
    _settle.forward(from: 0);
  }

  void _toggleZoom(TapDownDetails at) {
    if (video) return;
    _zoom.value = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(
              -at.localPosition.dx,
              -at.localPosition.dy,
              0,
              1,
            )
            ..scaleByDouble(2.5, 2.5, 1, 1));
  }

  Widget _media(Size screen) {
    final hero = Hero(
      tag: widget.heroTag,
      flightShuttleBuilder: (f, a, d, from, to) =>
          mediaFlight(f, a, d, from, to, widget.media),
      child: video ? _video() : _photo(),
    );
    final framed = video
        ? Positioned.fill(child: hero)
        : Center(
            child: aspect == null
                ? hero
                : AspectRatio(aspectRatio: aspect!, child: hero),
          );
    return video ? framed : Positioned.fill(child: framed);
  }

  Widget _photo() => InteractiveViewer(
    transformationController: _zoom,
    maxScale: 4,
    panEnabled: zoomed,
    child: Image(
      key: const ValueKey('media-preview-photo'),
      image: mediaImage(widget.media.url),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: 'Photo',
      errorBuilder: (_, _, _) => const Center(
        child: Text(
          'This photo could not be loaded.',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    ),
  );

  Widget _video() {
    final p = player;
    if (error != null) {
      return Center(
        child: Text(error!, style: const TextStyle(color: Colors.white70)),
      );
    }
    if (p == null || !p.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: p.value.aspectRatio,
          child: VideoPlayer(p, key: const ValueKey('media-preview-video')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)!;
    final screen = MediaQuery.sizeOf(context);
    final share = _dragShare(screen);
    final canDrag = !zoomed;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // The bars' buttons and seek bar draw on it; the chat shows through.
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: route.animation!,
          builder: (context, child) {
            final open = Curves.easeOut.transform(route.animation!.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                // The chat fades to black beneath, and back while dragging.
                IgnorePointer(
                  child: ColoredBox(
                    key: const ValueKey('media-preview-backdrop'),
                    color: Colors.black.withValues(alpha: open * (1 - share)),
                  ),
                ),
                child!,
                // Bars fade in after the media, and away while dragging.
                _bars(open * (1 - share * 3).clamp(0.0, 1.0)),
              ],
            );
          },
          child: GestureDetector(
            key: const ValueKey('media-preview'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => chrome = !chrome),
            onDoubleTapDown: _toggleZoom,
            onDoubleTap: () {},
            onVerticalDragStart: canDrag ? _dragStart : null,
            onVerticalDragUpdate: canDrag ? _dragUpdate : null,
            onVerticalDragEnd: canDrag ? (d) => _dragEnd(d, screen) : null,
            child: Transform.translate(
              offset: drag,
              child: Transform.scale(
                scale: 1 - .25 * share,
                child: Stack(fit: StackFit.expand, children: [_media(screen)]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bars(double opacity) {
    final shown = chrome ? opacity : 0.0;
    return IgnorePointer(
      ignoring: shown < .5,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: shown,
        child: Stack(
          children: [
            Positioned(left: 0, right: 0, top: 0, child: _topBar()),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar()),
            if (video && player?.value.isInitialized == true)
              Center(child: _playButton()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x99000000), Color(0x00000000)],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('media-preview-close'),
              tooltip: 'Back',
              color: Colors.white,
              icon: const BackButtonIcon(),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title.isEmpty ? widget.media.name : widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.subtitle.isNotEmpty)
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _bottomBar() {
    final caption = widget.caption.trim();
    final p = player;
    final controls = video && p != null && p.value.isInitialized;
    if (!controls && caption.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0x99000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              if (controls) _timeline(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeline(
    VideoPlayerController p,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: p,
    builder: (context, value, _) {
      final total = value.duration.inMilliseconds;
      final at = value.position.inMilliseconds.clamp(0, math.max(0, total));
      return Row(
        children: [
          Text(
            _clock(value.position),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: T.green,
                inactiveTrackColor: Colors.white38,
                thumbColor: T.green,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                key: const ValueKey('media-preview-seek'),
                value: total == 0 ? 0 : at / total,
                onChanged: total == 0
                    ? null
                    : (v) =>
                          p.seekTo(Duration(milliseconds: (v * total).round())),
              ),
            ),
          ),
          Text(
            _clock(value.duration),
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
          const SizedBox(width: 6),
          TextButton(
            key: const ValueKey('media-preview-speed'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 32),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: () {
              final next = switch (speed) {
                1 => 1.5,
                1.5 => 2.0,
                _ => 1.0,
              };
              setState(() => speed = next);
              p.setPlaybackSpeed(next);
            },
            child: Text('${speed}x'),
          ),
        ],
      );
    },
  );

  Widget _playButton() => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: player!,
    builder: (context, value, _) {
      final ended =
          value.duration > Duration.zero &&
          value.position >= value.duration &&
          !value.isPlaying;
      return Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: IconButton(
          key: const ValueKey('media-preview-play'),
          iconSize: 40,
          color: Colors.white,
          tooltip: value.isPlaying ? 'Pause' : 'Play',
          icon: Icon(
            value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          onPressed: () async {
            if (value.isPlaying) {
              await player!.pause();
            } else {
              if (ended) await player!.seekTo(Duration.zero);
              await player!.play();
            }
          },
        ),
      );
    },
  );

  static String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
