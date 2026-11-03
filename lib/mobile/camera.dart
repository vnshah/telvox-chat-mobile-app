import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';

/// A photo or video taken in the app's camera, and the caption typed for it.
class CapturedMedia {
  const CapturedMedia(this.file, {required this.video, this.caption = ''});
  final XFile file;
  final bool video;
  final String caption;
}

/// WhatsApp's video limit through the Business API is 16 MB. Full HD needs
/// about 2 Mbps to stay clean: at 1 Mbps dark and moving areas break into
/// black, wave-like blocks. 2 Mbps with 64 kbps sound fills 16 MB in about a
/// minute, so that is where recording stops.
const maxRecording = Duration(seconds: 60);
const _videoBitrate = 2000000, _audioBitrate = 64000;

/// A front-camera photo turned the way the preview showed it (WhatsApp keeps
/// selfies as the mirror image you saw) and with its rotation applied, so it
/// looks the same everywhere. Runs off the UI thread.
Future<Uint8List> _selfie(Uint8List jpeg) => compute(_mirror, jpeg);

Uint8List _mirror(Uint8List jpeg) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) return jpeg;
  final upright = img.bakeOrientation(decoded);
  return img.encodeJpg(img.flipHorizontal(upright), quality: 90);
}

/// The camera as WhatsApp lays it out: the picture full screen, tap the shutter
/// for a photo, hold it (or use the Video tab) to record, flash and flip at
/// hand, and the gallery a tap away. What is taken is shown full screen with a
/// caption field before it is sent.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.onGallery});

  /// Picks from the gallery instead; it is reviewed and captioned the same way.
  final Future<XFile?> Function()? onGallery;
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> cameras = const [];
  CameraController? controller;
  int lens = 0;
  FlashMode flash = FlashMode.off;
  bool videoMode = false, recording = false, busy = false;

  /// Held to record and slid up to the lock: letting go keeps recording.
  bool locked = false;

  /// The shutter was let go before recording had started; stop once it has.
  bool _released = false;
  Duration elapsed = Duration.zero;
  Timer? ticker;
  String? error;

  /// Zoom, pinched or chosen, within what this camera can do.
  double zoom = 1, minZoom = 1, maxZoom = 1, _pinchFrom = 1;

  /// Where the last tap focused, shown as a ring for a moment.
  Offset? focusAt;
  Timer? _focusTimer;

  /// Opening and closing run one after another: two at once leave the
  /// camera taken by a controller nobody shows, and the preview black.
  Future<void> _queue = Future.value();
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    start();
  }

  Future<void> start() async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => error = 'No camera on this phone.');
        return;
      }
      // The back camera first, as WhatsApp opens.
      final back = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      lens = back < 0 ? 0 : back;
      await open(cameras[lens]);
    } on CameraException catch (e) {
      if (mounted) setState(() => error = _explain(e));
    }
  }

  Future<void> open(CameraDescription camera) =>
      _queue = _queue.then((_) => _open(camera));

  Future<void> close() => _queue = _queue.then((_) => _close());

  Future<void> _close() async {
    final previous = controller;
    controller = null;
    if (mounted) setState(() {});
    await previous?.dispose();
  }

  Future<void> _open(CameraDescription camera) async {
    await _close();
    if (!mounted) return;
    final next = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
      videoBitrate: _videoBitrate,
      audioBitrate: _audioBitrate,
    );
    try {
      await next.initialize();
      // A front camera has no flash; asking for one must not cost the preview.
      if (camera.lensDirection == CameraLensDirection.back) {
        await next.setFlashMode(flash).catchError((_) {});
      }
      await next.setFocusMode(FocusMode.auto).catchError((_) {});
      final low = await next.getMinZoomLevel().catchError((_) => 1.0);
      final high = await next.getMaxZoomLevel().catchError((_) => 1.0);
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        controller = next;
        error = null;
        minZoom = low;
        maxZoom = math.min(high, 10);
        zoom = minZoom.clamp(1.0, maxZoom);
      });
    } on CameraException catch (e) {
      await next.dispose();
      if (mounted) setState(() => error = _explain(e));
    }
  }

  String _explain(CameraException e) => switch (e.code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' => 'Allow camera access for Telvox Chat in the phone’s Settings to take photos and videos.',
    'AudioAccessDenied' ||
    'AudioAccessDeniedWithoutPrompt' ||
    'AudioAccessRestricted' =>
      'Allow microphone access to record videos with sound.',
    _ => 'The camera could not start. ${e.description ?? ''}'.trim(),
  };

  /// Away (another app, the notification shade, a call) the camera is let
  /// go, for whoever needs it; back, it is opened again. The old check gave
  /// up when there was no camera to resume, which is exactly the case after
  /// letting go, so the preview stayed black until the screen was reopened.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (cameras.isEmpty) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (recording) stopRecording();
      if (controller != null && !recording) close();
    } else if (state == AppLifecycleState.resumed &&
        controller == null &&
        !_reviewing) {
      open(cameras[lens]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ticker?.cancel();
    _focusTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  bool get front =>
      cameras.isNotEmpty &&
      cameras[lens].lensDirection == CameraLensDirection.front;

  /// Front to back and back again, as WhatsApp's switch does.
  Future<void> flip() async {
    if (cameras.length < 2 || recording || busy) return;
    final want = front ? CameraLensDirection.back : CameraLensDirection.front;
    final other = cameras.indexWhere((c) => c.lensDirection == want);
    lens = other < 0 ? (lens + 1) % cameras.length : other;
    HapticFeedback.selectionClick();
    await open(cameras[lens]);
  }

  Future<void> cycleFlash() async {
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    setState(() => flash = next);
    if (!front) await controller?.setFlashMode(next).catchError((_) {});
  }

  Future<void> setZoom(double level) async {
    final c = controller;
    if (c == null) return;
    final next = level.clamp(minZoom, maxZoom);
    setState(() => zoom = next);
    await c.setZoomLevel(next).catchError((_) {});
  }

  /// Focuses (and meters) where the preview was tapped.
  Future<void> focusOn(Offset tap, Size screen) async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    final preview = c.value.previewSize;
    if (preview == null) return;
    // The preview is scaled to cover the screen, so a tap is mapped through
    // that scale and crop onto the camera's picture (portrait).
    final pw = preview.height, ph = preview.width;
    final scale = math.max(screen.width / pw, screen.height / ph);
    final dx = (pw * scale - screen.width) / 2;
    final dy = (ph * scale - screen.height) / 2;
    final point = Offset(
      ((tap.dx + dx) / (pw * scale)).clamp(0.0, 1.0),
      ((tap.dy + dy) / (ph * scale)).clamp(0.0, 1.0),
    );
    _focusTimer?.cancel();
    setState(() => focusAt = tap);
    _focusTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => focusAt = null);
    });
    if (c.value.focusPointSupported) {
      await c.setFocusPoint(point).catchError((_) {});
    }
    if (c.value.exposurePointSupported) {
      await c.setExposurePoint(point).catchError((_) {});
    }
  }

  Future<void> photo() async {
    final c = controller;
    if (c == null || busy) return;
    if (recording) {
      await stopRecording();
      return;
    }
    setState(() => busy = true);
    try {
      var shot = await c.takePicture();
      if (front) {
        final turned = await _selfie(await shot.readAsBytes());
        final file = File(
          '${Directory.systemTemp.path}/selfie-${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await file.writeAsBytes(turned, flush: true);
        shot = XFile(file.path, mimeType: 'image/jpeg');
      }
      if (mounted) await review(shot, video: false);
    } on CameraException catch (e) {
      if (mounted) setState(() => error = _explain(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startRecording() async {
    final c = controller;
    if (c == null || recording || busy) return;
    _released = false;
    try {
      await c.startVideoRecording();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        recording = true;
        locked = videoMode;
        elapsed = Duration.zero;
      });
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => elapsed += const Duration(seconds: 1));
        if (elapsed >= maxRecording) stopRecording();
      });
      // Let go while it was starting: a short clip, stopped now.
      if (_released && !locked) await stopRecording();
    } on CameraException catch (e) {
      if (mounted) setState(() => error = _explain(e));
    }
  }

  Future<void> stopRecording() async {
    final c = controller;
    if (c == null || !recording) return;
    ticker?.cancel();
    setState(() {
      recording = false;
      locked = false;
      busy = true;
    });
    try {
      final clip = await c.stopVideoRecording();
      if (mounted) await review(clip, video: true);
    } on CameraException catch (e) {
      if (mounted) setState(() => error = _explain(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Holding the shutter records; letting go stops, unless it was slid up
  /// to the lock first — then it keeps recording until the stop button.
  void holdStart() {
    if (videoMode || busy) return;
    startRecording();
  }

  void holdMove(LongPressMoveUpdateDetails d) {
    if (recording && !locked && d.offsetFromOrigin.dy < -70) {
      HapticFeedback.mediumImpact();
      setState(() => locked = true);
    }
  }

  void holdEnd() {
    _released = true;
    if (recording && !locked) stopRecording();
  }

  /// Full-screen check before sending: send closes the camera with it,
  /// retake comes back here.
  Future<void> review(XFile file, {required bool video}) async {
    _reviewing = true;
    final result = await Navigator.of(context).push<CapturedMedia>(
      MaterialPageRoute(builder: (_) => MediaPreviewPage(file, video: video)),
    );
    _reviewing = false;
    if (result != null && mounted) {
      Navigator.pop(context, result);
    } else if (mounted && controller == null && cameras.isNotEmpty) {
      // Back to retake after the app was away meanwhile.
      await open(cameras[lens]);
    }
  }

  Future<void> gallery() async {
    final pick = widget.onGallery;
    if (pick == null || recording) return;
    final chosen = await pick();
    if (chosen == null || !mounted) return;
    final ext = chosen.name.split('.').last.toLowerCase();
    await review(
      chosen,
      video: const {'mp4', '3gp', 'mov', 'webm', 'mkv'}.contains(ext),
    );
  }

  static String clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            // Tap to focus there; pinch to zoom.
            LayoutBuilder(
              builder: (context, box) => GestureDetector(
                key: const ValueKey('camera-preview'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => focusOn(d.localPosition, box.biggest),
                onScaleStart: (_) => _pinchFrom = zoom,
                onScaleUpdate: (d) {
                  if (d.pointerCount > 1) setZoom(_pinchFrom * d.scale);
                },
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: c.value.previewSize?.height ?? 1,
                      height: c.value.previewSize?.width ?? 1,
                      child: CameraPreview(c),
                    ),
                  ),
                ),
              ),
            )
          else if (error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (focusAt != null)
            Positioned(
              left: focusAt!.dx - 34,
              top: focusAt!.dy - 34,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(focusAt),
                  tween: Tween(begin: 1.3, end: 1),
                  duration: const Duration(milliseconds: 220),
                  builder: (_, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    key: const ValueKey('focus-ring'),
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.6),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      _CircleIcon(
                        Icons.close,
                        tooltip: 'Close camera',
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      if (recording)
                        Container(
                          key: const ValueKey('recording-timer'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 10,
                                color: Color(0xFFE53935),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                clock(elapsed),
                                semanticsLabel: 'Recording ${clock(elapsed)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                ' / ${clock(maxRecording)}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      _CircleIcon(
                        switch (flash) {
                          FlashMode.auto => Icons.flash_auto,
                          FlashMode.always => Icons.flash_on,
                          _ => Icons.flash_off,
                        },
                        tooltip: 'Flash',
                        // The front camera has no flash.
                        onTap: front ? null : cycleFlash,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Zoom as WhatsApp shows it: the level, and a tap for 1x/2x.
                if (c != null && maxZoom > 1.05)
                  Padding(
                    key: const ValueKey('zoom-row'),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: GestureDetector(
                      key: const ValueKey('zoom'),
                      onTap: () => setZoom(zoom < 1.95 ? 2 : 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        child: Text(
                          '${zoom.toStringAsFixed(zoom < 10 ? 1 : 0)}x',
                          semanticsLabel:
                              'Zoom ${zoom.toStringAsFixed(1)} times',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (recording && !locked)
                  const Padding(
                    key: ValueKey('lock-hint'),
                    padding: EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.white, size: 20),
                        Icon(
                          Icons.keyboard_arrow_up,
                          color: Colors.white70,
                          size: 20,
                        ),
                        Text(
                          'Slide up to keep recording',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                // Keyed, so hints appearing above it while the shutter is
                // held never rebuild it mid-press (it would miss the release).
                Padding(
                  key: const ValueKey('shutter-row'),
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CircleIcon(
                        Icons.photo_library_outlined,
                        tooltip: 'Gallery',
                        onTap: widget.onGallery == null || recording
                            ? null
                            : gallery,
                        size: 48,
                      ),
                      Semantics(
                        button: true,
                        label: recording
                            ? 'Stop recording'
                            : videoMode
                            ? 'Start recording'
                            : 'Take photo',
                        child: GestureDetector(
                          key: const ValueKey('shutter'),
                          // A tap takes a photo, starts a video in Video, and
                          // always stops a recording.
                          onTap: busy
                              ? null
                              : recording
                              ? stopRecording
                              : videoMode
                              ? startRecording
                              : photo,
                          // Hold for video, as on WhatsApp; slide up to lock.
                          onLongPressStart: videoMode || busy
                              ? null
                              : (_) => holdStart(),
                          onLongPressMoveUpdate: videoMode ? null : holdMove,
                          onLongPressEnd: videoMode ? null : (_) => holdEnd(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: recording ? 86 : 74,
                            height: recording ? 86 : 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: recording
                                  ? Colors.transparent
                                  : videoMode
                                  ? const Color(0xFFE53935)
                                  : Colors.white24,
                            ),
                            child: busy
                                ? const Padding(
                                    padding: EdgeInsets.all(22),
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : recording
                                // A clear Stop: WhatsApp's red square.
                                ? Center(
                                    child: Container(
                                      key: const ValueKey('stop'),
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE53935),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      _CircleIcon(
                        Icons.flip_camera_android_outlined,
                        tooltip: 'Switch camera',
                        onTap: cameras.length > 1 && !recording && !busy
                            ? flip
                            : null,
                        size: 48,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (label, video) in [
                        ('Video', true),
                        ('Photo', false),
                      ])
                        GestureDetector(
                          onTap: recording
                              ? null
                              : () => setState(() => videoMode = video),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: videoMode == video
                                  ? Colors.white24
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: videoMode == video
                                    ? Colors.white
                                    : Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!recording)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      videoMode
                          ? 'Tap to start, tap again to stop'
                          : 'Tap for photo, hold for video',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon(
    this.icon, {
    required this.tooltip,
    required this.onTap,
    this.size = 44,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: onTap == null ? Colors.white38 : Colors.white,
            size: size * .5,
          ),
        ),
      ),
    ),
  );
}

/// A recorded clip under review, as WhatsApp plays one: tap to pause or
/// play, a play button while paused, and a bar to scrub with its times.
class _VideoReview extends StatelessWidget {
  const _VideoReview(this.player);
  final VideoPlayerController player;

  static String _time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: player,
        builder: (context, value, _) => GestureDetector(
          key: const ValueKey('video-review'),
          onTap: () => value.isPlaying ? player.pause() : player.play(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(player),
              ),
              if (!value.isPlaying)
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 42,
                    semanticLabel: 'Play',
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: Row(
                  children: [
                    Text(
                      _time(value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: VideoProgressIndicator(
                        player,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _time(value.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// What was taken, full screen, with a caption field and Send, as WhatsApp
/// shows it. Back retakes.
class MediaPreviewPage extends StatefulWidget {
  const MediaPreviewPage(this.file, {super.key, required this.video});
  final XFile file;
  final bool video;
  @override
  State<MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<MediaPreviewPage> {
  final caption = TextEditingController();
  VideoPlayerController? player;

  @override
  void initState() {
    super.initState();
    if (widget.video) {
      final p = player = VideoPlayerController.file(File(widget.file.path));
      p
          .initialize()
          .then((_) {
            if (!mounted) return;
            p
              ..setLooping(true)
              ..play();
            setState(() {});
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    caption.dispose();
    player?.dispose();
    super.dispose();
  }

  /// WhatsApp refuses videos over 16 MB; better to say so before sending.
  late final int bytes = File(widget.file.path).existsSync()
      ? File(widget.file.path).lengthSync()
      : 0;
  bool get tooLarge => widget.video && bytes > 16 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('retake'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  label: const Text(
                    'Retake',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: widget.video
                    ? p != null && p.value.isInitialized
                          ? _VideoReview(p)
                          : const CircularProgressIndicator(color: Colors.white)
                    : InteractiveViewer(
                        child: Image.file(
                          File(widget.file.path),
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      ),
              ),
            ),
            if (tooLarge)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'This video is ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB. '
                  'WhatsApp takes up to 16 MB: record a shorter one.',
                  key: const ValueKey('too-large'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFB4A9),
                    fontSize: 13,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('caption'),
                      controller: caption,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a caption…',
                        hintStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: Colors.white12,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Send',
                    child: Material(
                      color: T.green,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: const ValueKey('send-captured'),
                        customBorder: const CircleBorder(),
                        onTap: tooLarge
                            ? null
                            : () => Navigator.pop(
                                context,
                                CapturedMedia(
                                  widget.file,
                                  video: widget.video,
                                  caption: caption.text.trim(),
                                ),
                              ),
                        child: const SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(Icons.send, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
