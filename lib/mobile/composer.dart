import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../ui/file_type.dart';
import '../ui/theme.dart';
import 'media.dart';
import 'voice_recording.dart';

/// Records a voice note to a temporary file. A seam so tests need no microphone.
abstract class VoiceRecorder {
  /// False when the microphone permission is refused.
  Future<bool> start();

  /// The recorded file's path, or null if nothing was captured.
  Future<String?> stop();
  Future<void> cancel();

  /// Hold and continue a locked recording into the same file.
  Future<void> pause();
  Future<void> resume();

  /// The microphone's level, 0 (silence) to 1, several times a second.
  Stream<double> levels();
  void dispose();
}

class DeviceVoiceRecorder implements VoiceRecorder {
  /// Created on the first recording, so an open chat holds no audio session.
  AudioRecorder? _instance;
  AudioRecorder get _recorder => _instance ??= AudioRecorder();
  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final path =
        '${Directory.systemTemp.path}/voice-note-${DateTime.now().millisecondsSinceEpoch}.m4a';
    // Mono AAC: small, and the server re-encodes it to WhatsApp's Ogg/Opus.
    await _recorder.start(
      const RecordConfig(numChannels: 1, sampleRate: 16000, bitRate: 32000),
      path: path,
    );
    return true;
  }

  @override
  Future<String?> stop() async => _instance?.stop();
  @override
  Future<void> cancel() async => _instance?.cancel();
  @override
  Future<void> pause() async => _instance?.pause();
  @override
  Future<void> resume() async => _instance?.resume();

  /// dBFS from about -50 (room noise) to 0 (loud), as 0–1.
  @override
  Stream<double> levels() => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((a) => ((a.current + 50) / 50).clamp(0.0, 1.0));
  @override
  void dispose() => _instance?.dispose();
}

/// What the attach sheet offers, as WhatsApp lays it out.
enum AttachChoice {
  document,
  gallery,
  camera,
  location,
  audio,
  quickReplies,
  templates,
}

/// One choice of the attach sheet: a rounded tile in a soft colour.
typedef _AttachItem = ({
  AttachChoice choice,
  IconData icon,
  String label,
  Color tint,
  Color ink,
});

/// The attach sheet: a sheet with a handle and the choices as a grid of
/// rounded tiles, each in its own soft colour (location in the app's
/// green), what people send most first. Template shows only where a template may be sent.
Future<AttachChoice?> showAttachSheet(
  BuildContext context, {
  required bool templates,
}) {
  final items = <_AttachItem>[
    (
      choice: AttachChoice.camera,
      icon: Icons.photo_camera_outlined,
      label: 'Camera',
      tint: Color(0xFFFCE4EA),
      ink: Color(0xFFD13E63),
    ),
    (
      choice: AttachChoice.gallery,
      icon: Icons.photo_library_outlined,
      label: 'Gallery',
      tint: Color(0xFFEEE6FB),
      ink: Color(0xFF7B52D6),
    ),
    (
      choice: AttachChoice.document,
      icon: Icons.description_outlined,
      label: 'Document',
      tint: Color(0xFFE3EEFB),
      ink: Color(0xFF2F72C7),
    ),
    (
      choice: AttachChoice.location,
      icon: Icons.location_on_outlined,
      label: 'Location',
      tint: T.greenWash,
      ink: T.green,
    ),
    (
      choice: AttachChoice.audio,
      icon: Icons.headphones_outlined,
      label: 'Audio',
      tint: Color(0xFFFDEFD9),
      ink: Color(0xFFD9822B),
    ),
    (
      choice: AttachChoice.quickReplies,
      icon: Icons.bolt_outlined,
      label: 'Quick replies',
      tint: Color(0xFFDDF3F0),
      ink: Color(0xFF16958A),
    ),
    if (templates)
      (
        choice: AttachChoice.templates,
        icon: Icons.article_outlined,
        label: 'Template',
        tint: Color(0xFFE6E8FA),
        ink: Color(0xFF4B55C2),
      ),
  ];
  return showModalBottomSheet<AttachChoice>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    useSafeArea: true,
    // Sized to its tiles, not to a share of the screen; scrolls only if
    // very large text makes it taller than the screen.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Text(
                'Share',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
            ),
            // Four to a row on a phone; tiles keep their size on wider
            // screens rather than stretching.
            LayoutBuilder(
              builder: (context, box) {
                final width = (box.maxWidth / 4).clamp(72.0, 96.0);
                return Wrap(
                  runSpacing: 6,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: width,
                        child: _AttachTile(
                          item,
                          onTap: () => Navigator.pop(context, item.choice),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _AttachTile extends StatelessWidget {
  const _AttachTile(this.item, {required this.onTap});
  final _AttachItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: item.label,
    excludeSemantics: true,
    child: InkWell(
      key: ValueKey('attach-${item.choice.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Ink(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: item.tint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(item.icon, color: item.ink, size: 27),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: T.ink),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}

/// The WhatsApp composer: a white pill holding the reply or attachment being
/// prepared, the text field and the attach clip, beside a round button that
/// is a microphone until there is something to send.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onQuickReplies,
    required this.onVoiceNote,
    this.onCamera,
    this.onTyping,
    this.enabled = true,
    this.busy = false,
    this.replyAuthor,
    this.replyText,
    this.onCancelReply,
    this.attachment,
    this.onCancelAttachment,
    this.recorder,
  });
  final TextEditingController controller;
  final bool enabled, busy;
  final String? replyAuthor, replyText;
  final VoidCallback? onCancelReply, onCancelAttachment;
  final Attachment? attachment;
  final VoidCallback onSend, onAttach, onQuickReplies;

  /// The camera beside the clip, as on WhatsApp; hidden while typing.
  final VoidCallback? onCamera;
  final ValueChanged<Attachment> onVoiceNote;

  /// Called on each edit with text, so the customer can be shown "typing…".
  final VoidCallback? onTyping;
  final VoiceRecorder? recorder;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

/// Where a voice note is: not recording; recording while the mic is held
/// (release sends, slide left cancels, slide up locks); or locked, recording
/// hands-free until Delete or Send.
enum VoiceStage { idle, holding, locked }

class _ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final VoiceRecorder recorder = widget.recorder ?? DeviceVoiceRecorder();
  var voice = VoiceStage.idle;
  bool paused = false;

  /// The finger's travel from where it pressed the mic.
  Offset drag = Offset.zero;
  Offset? _origin;

  /// The finger is still on the mic (it may lift before recording starts).
  bool _pressing = false;
  Duration elapsed = Duration.zero;
  Timer? ticker, _hintTimer;
  bool lockHint = false;
  final levels = <double>[];

  /// Levels received this recording, so the waveform knows a new one came.
  int samples = 0;
  StreamSubscription<double>? _levels;
  static const cancelDistance = 110.0, lockDistance = 80.0;
  static const _tick = Duration(milliseconds: 100);

  /// The cancelled recording's microphone dropping into the bin.
  late final binDrop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get recording => voice != VoiceStage.idle;

  bool get canSend =>
      widget.controller.text.trim().isNotEmpty || widget.attachment != null;

  /// The emoji panel replaces the keyboard, and the keyboard the panel.
  final focus = FocusNode();
  bool emoji = false;

  void _toggleEmoji() {
    if (emoji) {
      setState(() => emoji = false);
      focus.requestFocus();
    } else {
      focus.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      setState(() => emoji = true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    // The bin gives the emoji button its place back once the drop ends.
    binDrop.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  /// Leaving the app mid-recording: a held note is dropped (the finger is
  /// gone), a locked one pauses, kept for Resume, Delete or Send on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.inactive) {
      return;
    }
    if (voice == VoiceStage.holding) {
      _pressing = false;
      _discard();
    } else if (voice == VoiceStage.locked && !paused) {
      _togglePause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    focus.dispose();
    widget.controller.removeListener(_changed);
    _stopClock();
    if (recording) recorder.cancel();
    recorder.dispose();
    binDrop.dispose();
    super.dispose();
  }

  void _stopClock() {
    ticker?.cancel();
    _hintTimer?.cancel();
    _levels?.cancel();
    _levels = null;
  }

  /// Recording starts the moment the mic is pressed, as on WhatsApp.
  Future<void> _press(Offset at) async {
    if (!widget.enabled || recording) return;
    _pressing = true;
    _origin = at;
    HapticFeedback.mediumImpact();
    try {
      if (!await recorder.start()) {
        if (mounted) _notice('Allow microphone access to record voice notes.');
        return;
      }
    } catch (_) {
      if (mounted) _notice('Recording could not start.');
      return;
    }
    if (!mounted) {
      await recorder.cancel();
      return;
    }
    setState(() {
      voice = VoiceStage.holding;
      paused = false;
      drag = Offset.zero;
      elapsed = Duration.zero;
      lockHint = false;
      levels.clear();
      samples = 0;
    });
    ticker = Timer.periodic(_tick, (_) {
      if (mounted && !paused) setState(() => elapsed += _tick);
    });
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && voice == VoiceStage.holding) {
        setState(() => lockHint = true);
      }
    });
    try {
      _levels = recorder.levels().listen((level) {
        if (!mounted || paused) return;
        setState(() {
          levels.add(level);
          samples++;
          if (levels.length > 120) levels.removeAt(0);
        });
      }, onError: (_) {});
    } catch (_) {
      // No levels on this device: the waveform stays flat.
    }
    // Lifted before the microphone was ready: a tap, not a hold.
    if (!_pressing) _release();
  }

  void _move(Offset at) {
    if (voice != VoiceStage.holding || _origin == null) return;
    final d = at - _origin!;
    if (d.dy <= -lockDistance) {
      _lock();
    } else if (d.dx <= -cancelDistance) {
      _discard(animate: true);
    } else {
      setState(
        () => drag = Offset(
          d.dx.clamp(-cancelDistance, 0),
          d.dy.clamp(-lockDistance, 0),
        ),
      );
    }
  }

  /// Letting go of a held recording sends it; a locked one keeps going.
  void _release() {
    _pressing = false;
    _origin = null;
    if (voice == VoiceStage.holding) _send();
  }

  void _lock() {
    HapticFeedback.mediumImpact();
    setState(() {
      voice = VoiceStage.locked;
      drag = Offset.zero;
      lockHint = false;
    });
  }

  /// Pause or resume. The new state is set first: leaving the app sends
  /// inactive then paused in quick succession, and the second must see the
  /// first's pause, not undo it.
  Future<void> _togglePause() async {
    final pausing = !paused;
    setState(() => paused = pausing);
    try {
      pausing ? await recorder.pause() : await recorder.resume();
    } catch (e) {
      if (mounted) {
        setState(() => paused = !pausing);
        _notice('$e');
      }
    }
  }

  /// Drops the recording; sliding away shows it falling into the bin.
  Future<void> _discard({bool animate = false}) async {
    if (!recording) return;
    _stopClock();
    setState(() {
      voice = VoiceStage.idle;
      drag = Offset.zero;
      lockHint = false;
    });
    HapticFeedback.lightImpact();
    if (animate) binDrop.forward(from: 0);
    await recorder.cancel();
  }

  /// Sends what was recorded; under a second is a tap, and says how.
  Future<void> _send() async {
    if (!recording) return;
    final duration = elapsed;
    _stopClock();
    setState(() {
      voice = VoiceStage.idle;
      drag = Offset.zero;
      lockHint = false;
    });
    if (duration < const Duration(seconds: 1)) {
      await recorder.cancel();
      if (mounted) _notice('Hold to record, release to send.');
      return;
    }
    try {
      final path = await recorder.stop();
      if (path == null) return;
      final note = await Attachment.fromFile(XFile(path), kinds: ['audio']);
      widget.onVoiceNote(note);
    } catch (e) {
      if (mounted) _notice('$e');
    }
  }

  void _notice(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );

  Widget _preview() {
    if (widget.attachment case final Attachment a) {
      return _PreviewStrip(
        accent: T.brass,
        title: switch (a.kind) {
          'image' => 'Photo',
          'video' => 'Video',
          'audio' => 'Audio',
          _ => 'Document',
        },
        text: a.name,
        icon: switch (a.kind) {
          'image' => Icons.photo,
          'video' => Icons.videocam,
          'audio' => Icons.headphones,
          // A document shows its page instead (below).
          _ => null,
        },
        thumbnail: a.kind == 'image' && a.file.path.isNotEmpty
            ? Image.file(
                File(a.file.path),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              )
            // A document shows its page, in its kind's colour.
            : a.kind == 'document'
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(child: FileTypeIcon(a.name, size: 38)),
              )
            : null,
        onClose: widget.onCancelAttachment,
        closeLabel: 'Remove attachment',
      );
    }
    if (widget.replyText != null) {
      return _PreviewStrip(
        accent: T.green,
        title: widget.replyAuthor ?? 'Reply',
        text: widget.replyText!,
        onClose: widget.onCancelReply,
        closeLabel: 'Cancel reply',
      );
    }
    return const SizedBox(width: double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final pill = Container(
      decoration: BoxDecoration(
        color: T.incoming,
        borderRadius: BorderRadius.circular(24),
        boxShadow: T.bubbleShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The reply or attachment slides in above the text, inside the pill.
          AnimatedSize(
            duration: motion,
            curve: Curves.easeOut,
            alignment: Alignment.bottomCenter,
            child: _preview(),
          ),
          if (voice == VoiceStage.holding)
            _RecordingBar(elapsed: elapsed, drag: drag.dx)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Where a cancelled recording drops, in the emoji's place.
                if (binDrop.isAnimating)
                  BinDrop(binDrop)
                else
                  AppIconButton(
                    tooltip: emoji ? 'Keyboard' : 'Emoji',
                    onPressed: _toggleEmoji,
                    icon: AppIcon(
                      emoji
                          ? Icons.keyboard_outlined
                          : Icons.emoji_emotions_outlined,
                      color: T.brass,
                    ),
                  ),
                Expanded(
                  child: AppTextField(
                    controller: widget.controller,
                    focusNode: focus,
                    minLines: 1,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    // "/" opens quick replies, as in the web ticket inbox.
                    onChanged: (v) {
                      if (v == '/') {
                        widget.controller.clear();
                        widget.onQuickReplies();
                      } else if (v.trim().isNotEmpty) {
                        widget.onTyping?.call();
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                AppIconButton(
                  tooltip: 'Attach',
                  onPressed: widget.onAttach,
                  icon: Transform.rotate(
                    angle: -.6,
                    child: const AppIcon(Icons.attach_file, color: T.brass),
                  ),
                ),
                if (widget.onCamera != null && !canSend)
                  AppIconButton(
                    tooltip: 'Camera',
                    onPressed: widget.onCamera,
                    icon: const AppIcon(
                      Icons.photo_camera_outlined,
                      color: T.brass,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
    final sendMode = canSend && !recording;
    // A long press is how a voice note is recorded, so the mic carries no
    // tooltip: one would open over the lock while recording.
    Widget button = Semantics(
      button: true,
      label: sendMode ? 'Send message' : 'Record voice note',
      // Raw pointer events: recording starts on touch, not after a
      // long-press delay, and the finger's path locks or cancels it.
      child: Listener(
        onPointerDown: sendMode ? null : (e) => _press(e.position),
        onPointerMove: sendMode ? null : (e) => _move(e.position),
        onPointerUp: sendMode ? null : (_) => _release(),
        onPointerCancel: sendMode
            ? null
            : (_) {
                _pressing = false;
                if (voice == VoiceStage.holding) _discard();
              },
        child: AnimatedScale(
          scale: voice == VoiceStage.holding ? 1.45 : 1,
          duration: motion,
          child: Material(
            color: T.green,
            shape: const CircleBorder(),
            elevation: 1,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.busy || !sendMode ? null : widget.onSend,
              child: SizedBox(
                width: 48,
                height: 48,
                // The microphone turns into the send arrow as you type.
                child: AnimatedSwitcher(
                  duration: motion,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: AppIcon(
                    sendMode ? Icons.send : Icons.mic,
                    key: ValueKey(sendMode),
                    color: Colors.white,
                    size: sendMode ? 21 : 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (sendMode) button = Tooltip(message: 'Send message', child: button);

    final composer = IgnorePointer(
      ignoring: !widget.enabled,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1 : .45,
        duration: motion,
        // No bar of its own: the white pill floats on the chat's beige, as
        // WhatsApp's does, so its rounded ends show.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: voice == VoiceStage.locked
              ? LockedRecordingPanel(
                  elapsed: elapsed,
                  levels: levels,
                  samples: samples,
                  paused: paused,
                  onDelete: _discard,
                  onPause: _togglePause,
                  onSend: _send,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: pill),
                    const SizedBox(width: 6),
                    // While held, the mic follows the finger, with the lock
                    // waiting above it.
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomRight,
                      children: [
                        if (voice == VoiceStage.holding)
                          Positioned(
                            right: 4,
                            bottom: 66 + (-drag.dy) * .3,
                            child: LockTab(
                              progress: -drag.dy / lockDistance,
                              hint: lockHint,
                            ),
                          ),
                        Transform.translate(offset: drag, child: button),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
    return PopScope(
      // Back closes the emoji panel before it leaves the chat.
      canPop: !emoji,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => emoji = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          composer,
          if (emoji && widget.enabled)
            EmojiPicker(
              key: const ValueKey('emoji-panel'),
              textEditingController: widget.controller,
              onEmojiSelected: (_, _) => widget.onTyping?.call(),
              config: Config(
                height: 280,
                emojiViewConfig: EmojiViewConfig(
                  columns: 8,
                  emojiSizeMax: 30,
                  backgroundColor: Colors.white,
                ),
                categoryViewConfig: const CategoryViewConfig(
                  backgroundColor: Colors.white,
                  indicatorColor: T.green,
                  iconColorSelected: T.green,
                  iconColor: T.muted,
                  backspaceColor: T.secondary,
                ),
                bottomActionBarConfig: const BottomActionBarConfig(
                  backgroundColor: Colors.white,
                  buttonColor: Colors.white,
                  buttonIconColor: T.secondary,
                ),
                searchViewConfig: const SearchViewConfig(
                  backgroundColor: Colors.white,
                  buttonIconColor: T.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({
    required this.accent,
    required this.title,
    required this.text,
    required this.closeLabel,
    this.onClose,
    this.icon,
    this.thumbnail,
  });
  final Color accent;
  final String title, text, closeLabel;
  final VoidCallback? onClose;
  final IconData? icon;
  final Widget? thumbnail;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
    decoration: BoxDecoration(
      color: T.wash,
      borderRadius: BorderRadius.circular(10),
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 4, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 15, color: T.muted),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: T.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (thumbnail != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: thumbnail,
              ),
            ),
          Align(
            alignment: Alignment.topCenter,
            child: AppIconButton(
              tooltip: closeLabel,
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18, color: T.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecordingBar extends StatefulWidget {
  const _RecordingBar({required this.elapsed, required this.drag});
  final Duration elapsed;
  final double drag;
  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar>
    with SingleTickerProviderStateMixin {
  late final blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.elapsed.inSeconds;
    final clock =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final progress = (-widget.drag / _ChatComposerState.cancelDistance).clamp(
      0.0,
      1.0,
    );
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 14),
          FadeTransition(
            opacity: blink,
            child: const Icon(Icons.mic, color: T.danger, size: 22),
          ),
          const SizedBox(width: 8),
          Text(
            clock,
            style: const TextStyle(fontSize: 15, color: T.ink),
            semanticsLabel: 'Recording $clock',
          ),
          Expanded(
            child: Transform.translate(
              offset: Offset(widget.drag / 2, 0),
              child: Opacity(
                opacity: 1 - progress * .8,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chevron_left, color: T.muted, size: 20),
                    Text(
                      'Slide to cancel',
                      style: TextStyle(fontSize: 14, color: T.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
