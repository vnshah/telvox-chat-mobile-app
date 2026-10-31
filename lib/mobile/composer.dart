import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../ui/theme.dart';
import 'media.dart';

/// Records a voice note to a temporary file. A seam so tests need no microphone.
abstract class VoiceRecorder {
  /// False when the microphone permission is refused.
  Future<bool> start();

  /// The recorded file's path, or null if nothing was captured.
  Future<String?> stop();
  Future<void> cancel();
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
  void dispose() => _instance?.dispose();
}

/// What the attach sheet offers, as WhatsApp lays it out.
enum AttachChoice { document, gallery, audio, quickReplies, templates }

Future<AttachChoice?> showAttachSheet(
  BuildContext context, {
  required bool templates,
}) => showModalBottomSheet<AttachChoice>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (context) {
    Widget item(AttachChoice choice, IconData icon, String label, Color c) =>
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(context, choice),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12.5, color: T.secondary),
                ),
              ],
            ),
          ),
        );
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.1,
          children: [
            item(
              AttachChoice.document,
              Icons.insert_drive_file,
              'Document',
              const Color(0xFF7F66FF),
            ),
            item(
              AttachChoice.gallery,
              Icons.photo,
              'Gallery',
              const Color(0xFFC861FA),
            ),
            item(
              AttachChoice.audio,
              Icons.headphones,
              'Audio',
              const Color(0xFFFF7F21),
            ),
            item(
              AttachChoice.quickReplies,
              Icons.bolt,
              'Quick replies',
              const Color(0xFF02A698),
            ),
            if (templates)
              item(
                AttachChoice.templates,
                Icons.article,
                'Template',
                const Color(0xFF009DE2),
              ),
          ],
        ),
      ),
    );
  },
);

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
  final ValueChanged<Attachment> onVoiceNote;

  /// Called on each edit with text, so the customer can be shown "typing…".
  final VoidCallback? onTyping;
  final VoiceRecorder? recorder;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final VoiceRecorder recorder = widget.recorder ?? DeviceVoiceRecorder();
  bool recording = false, cancelled = false;
  double drag = 0;
  Duration elapsed = Duration.zero;
  Timer? ticker;
  static const cancelDistance = 110.0;

  bool get canSend =>
      widget.controller.text.trim().isNotEmpty || widget.attachment != null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
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

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    ticker?.cancel();
    if (recording) recorder.cancel();
    recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!widget.enabled || recording) return;
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
      recording = true;
      cancelled = false;
      drag = 0;
      elapsed = Duration.zero;
    });
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => elapsed += const Duration(seconds: 1));
    });
  }

  void _dragged(double dx) {
    if (!recording || cancelled) return;
    setState(() => drag = dx.clamp(-cancelDistance, 0));
    if (dx <= -cancelDistance) _finish(send: false);
  }

  /// Release sends; sliding left past the threshold cancels, as on WhatsApp.
  Future<void> _finish({required bool send}) async {
    if (!recording) return;
    ticker?.cancel();
    final duration = elapsed;
    setState(() {
      recording = false;
      cancelled = !send;
      drag = 0;
    });
    if (!send || duration < const Duration(seconds: 1)) {
      await recorder.cancel();
      if (send && mounted) _notice('Hold to record, release to send.');
      if (!send) HapticFeedback.lightImpact();
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
          _ => Icons.insert_drive_file,
        },
        thumbnail: a.kind == 'image' && a.file.path.isNotEmpty
            ? Image.file(
                File(a.file.path),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: T.ink.withValues(alpha: .12),
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ],
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
          if (recording)
            _RecordingBar(elapsed: elapsed, drag: drag)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AppIconButton(
                  tooltip: 'Quick replies',
                  onPressed: widget.onQuickReplies,
                  icon: const AppIcon(Icons.bolt, color: T.brass),
                ),
                Expanded(
                  child: AppTextField(
                    controller: widget.controller,
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
              ],
            ),
        ],
      ),
    );
    final sendMode = canSend && !recording;
    final button = Tooltip(
      message: sendMode ? 'Send message' : 'Hold to record a voice note',
      child: Semantics(
        button: true,
        label: sendMode ? 'Send message' : 'Record voice note',
        child: GestureDetector(
          onLongPressStart: sendMode ? null : (_) => _startRecording(),
          onLongPressMoveUpdate: sendMode
              ? null
              : (d) => _dragged(d.offsetFromOrigin.dx),
          onLongPressEnd: sendMode ? null : (_) => _finish(send: !cancelled),
          child: AnimatedScale(
            scale: recording ? 1.28 : 1,
            duration: motion,
            child: Material(
              color: T.green,
              shape: const CircleBorder(),
              elevation: 1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.busy
                    ? null
                    : sendMode
                    ? widget.onSend
                    : () => _notice('Hold to record, release to send.'),
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
      ),
    );
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1 : .45,
        duration: motion,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: pill),
              const SizedBox(width: 6),
              button,
            ],
          ),
        ),
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
