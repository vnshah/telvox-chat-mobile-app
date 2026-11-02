import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';

/// A photo or video taken in the app's camera, and the caption typed for it.
class CapturedMedia {
  const CapturedMedia(this.file, {required this.video, this.caption = ''});
  final XFile file;
  final bool video;
  final String caption;
}

/// WhatsApp's video limit through the Business API is 16 MB. Recording Full HD
/// at about 1 Mbps fits roughly two minutes, so that is where recording stops.
const maxRecording = Duration(minutes: 1, seconds: 50);
const _videoBitrate = 1000000, _audioBitrate = 64000;

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
  Duration elapsed = Duration.zero;
  Timer? ticker;
  String? error;

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
        setState(() => error = 'No camera on this phone.');
        return;
      }
      await open(cameras[lens]);
    } on CameraException catch (e) {
      if (mounted) setState(() => error = _explain(e));
    }
  }

  Future<void> open(CameraDescription camera) async {
    final previous = controller;
    controller = null;
    if (mounted) setState(() {});
    await previous?.dispose();
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
      await next.setFlashMode(flash);
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        controller = next;
        error = null;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    // Another app may take the camera while this one is away.
    if (state == AppLifecycleState.inactive) {
      if (recording) stopRecording();
      c.dispose();
      controller = null;
    } else if (state == AppLifecycleState.resumed && cameras.isNotEmpty) {
      open(cameras[lens]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ticker?.cancel();
    controller?.dispose();
    super.dispose();
  }

  Future<void> flip() async {
    if (cameras.length < 2 || recording) return;
    lens = (lens + 1) % cameras.length;
    await open(cameras[lens]);
  }

  Future<void> cycleFlash() async {
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    setState(() => flash = next);
    await controller?.setFlashMode(next);
  }

  Future<void> photo() async {
    final c = controller;
    if (c == null || busy || recording) return;
    setState(() => busy = true);
    try {
      final shot = await c.takePicture();
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
    try {
      await c.startVideoRecording();
      HapticFeedback.mediumImpact();
      setState(() {
        recording = true;
        elapsed = Duration.zero;
      });
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => elapsed += const Duration(seconds: 1));
        if (elapsed >= maxRecording) stopRecording();
      });
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

  /// Full-screen check before sending: send closes the camera with it,
  /// retake comes back here.
  Future<void> review(XFile file, {required bool video}) async {
    final result = await Navigator.of(context).push<CapturedMedia>(
      MaterialPageRoute(builder: (_) => MediaPreviewPage(file, video: video)),
    );
    if (result != null && mounted) Navigator.pop(context, result);
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
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize?.height ?? 1,
                  height: c.value.previewSize?.width ?? 1,
                  child: CameraPreview(c),
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
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${clock(elapsed)} / ${clock(maxRecording)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
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
                        onTap: cycleFlash,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CircleIcon(
                        Icons.photo_library_outlined,
                        tooltip: 'Gallery',
                        onTap: widget.onGallery == null ? null : gallery,
                        size: 48,
                      ),
                      GestureDetector(
                        key: const ValueKey('shutter'),
                        onTap: busy
                            ? null
                            : videoMode
                            ? (recording ? stopRecording : startRecording)
                            : photo,
                        // Hold for video, as on WhatsApp.
                        onLongPressStart: videoMode || busy
                            ? null
                            : (_) => startRecording(),
                        onLongPressEnd: videoMode
                            ? null
                            : (_) => stopRecording(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: recording ? 86 : 74,
                          height: recording ? 86 : 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            color: recording
                                ? const Color(0xFFE53935)
                                : videoMode
                                ? const Color(0x55E53935)
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
                              : null,
                        ),
                      ),
                      _CircleIcon(
                        Icons.flip_camera_android_outlined,
                        tooltip: 'Switch camera',
                        onTap: cameras.length > 1 && !recording ? flip : null,
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
                if (!videoMode && !recording)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Tap for photo, hold for video',
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
                          ? GestureDetector(
                              onTap: () => setState(
                                () => p.value.isPlaying ? p.pause() : p.play(),
                              ),
                              child: AspectRatio(
                                aspectRatio: p.value.aspectRatio,
                                child: VideoPlayer(p),
                              ),
                            )
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
                        onTap: () => Navigator.pop(
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
