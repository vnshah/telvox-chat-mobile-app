import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';
import '../ui/data.dart' show Message;
import '../ui/chat_message.dart';
import '../ui/conversation.dart' show SwipeReply;
import 'api.dart';
import 'media.dart';
import 'models.dart';
import 'message_content.dart';
import 'voice_waveform.dart';

/// [contactName] names the quoted author: a customer usually quotes the
/// business, and an agent quotes the customer.
Message messagePresentation(ApiMessage m, {String? contactName}) => Message(
  m.content.text,
  out: m.outgoing,
  time: const MobileClock().time(m.json['created_at']),
  reply: m.json['contextual_message'] == null
      ? null
      : MessageContent({
          'message_type': m.json['contextual_message_type'] ?? 'text',
          'message_body': m.json['contextual_message'],
          'message_body_json': m.json['contextual_message_json'],
        }).summary,
  replyAuthor: m.outgoing ? (contactName ?? 'Customer') : 'You',
  read: m.status == 3,
  deliveryStatus: m.status,
);

class LiveMessageView extends StatelessWidget {
  const LiveMessageView({
    super.key,
    required this.message,
    required this.apiBase,
    required this.first,
    this.onReply,
    this.onActions,
    this.contactName,
  });
  final ApiMessage message;
  final String apiBase;
  final String? contactName;
  final bool first;
  final VoidCallback? onReply;
  final void Function(BuildContext)? onActions;
  @override
  Widget build(BuildContext context) {
    final m = message, c = m.content;
    if (m.log) {
      // Activity rows as a centred translucent pill, like the web inbox.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 28),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                c.summary,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: T.secondary),
              ),
            ),
          ),
        ),
      );
    }
    final sender = m.outgoing && first
        ? readableText(m.json['sender_name'])
        : '';
    final presentation = messagePresentation(m, contactName: contactName);
    final media = c.media.isEmpty ? null : c.media.first;
    final mediaUrl = media == null
        ? null
        : mediaUri(
            media['media_path'] ?? media['link'] ?? media['url'],
            apiBase,
          );
    final file = media == null || mediaUrl == null
        ? null
        : MessageMedia(
            '${media['type']}',
            mediaUrl,
            '${media['filename'] ?? media['media_name'] ?? media['type']}',
          );
    final width = MediaQuery.sizeOf(context).width * .82;
    Message bare(String text) => Message(
      text,
      out: presentation.out,
      time: presentation.time,
      read: presentation.read,
      deliveryStatus: presentation.deliveryStatus,
      reply: presentation.reply,
      replyAuthor: presentation.replyAuthor,
    );
    final location = m.type == 'location'
        ? object(object(decoded(m.json['message_body_json']))['location'])
        : const <String, dynamic>{};
    // WhatsApp frames each kind differently; anything else keeps the generic
    // bubble below with its text, media tiles, fields and buttons.
    final Widget? special = switch (m.type) {
      'image' || 'video' when file != null => MessageBubble(
        message: bare(c.text),
        first: first,
        maxWidth: width,
        tight: true,
        showStamp: c.text.isNotEmpty,
        contentBefore: MediaFrame(
          file,
          stamp: c.text.isEmpty ? presentation : null,
        ),
      ),
      'document' when file != null => MessageBubble(
        message: bare(c.text),
        first: first,
        maxWidth: 250 + 17,
        contentBefore: DocumentCard(
          file,
          outgoing: m.outgoing,
          size: '${media?['media_size'] ?? ''}',
        ),
      ),
      'audio' when file != null => MessageBubble(
        message: bare(''),
        first: first,
        maxWidth: 252 + 17,
        showStamp: false,
        contentBefore: AudioNote(
          file,
          voice:
              media?['voice'] == true ||
              '${media?['media_mime_type'] ?? ''}'.contains('ogg') ||
              '${media?['media_name'] ?? media?['filename'] ?? ''}'.endsWith(
                '.ogg',
              ),
          outgoing: m.outgoing,
          stamp: presentation,
        ),
      ),
      'location' when location['latitude'] != null => MessageBubble(
        message: bare(''),
        first: first,
        maxWidth: width,
        tight: true,
        contentBefore: LocationCard(location),
      ),
      _ => null,
    };
    final stickerUrl = m.type == 'sticker' && c.media.isNotEmpty
        ? mediaUri(
            c.media.first['media_path'] ?? c.media.first['link'],
            apiBase,
          )
        : null;
    final call = c.voiceCall;
    Widget bubble = Builder(
      builder: (anchor) => GestureDetector(
        onLongPress: onActions == null ? null : () => onActions!(anchor),
        // WhatsApp draws a sticker without a bubble, and a call as a bubble
        // holding just the call row and its time.
        child: stickerUrl != null
            ? StickerView(stickerUrl, presentation)
            : special ??
                  (call != null
                      ? MessageBubble(
                          message: Message(
                            '',
                            out: presentation.out,
                            time: presentation.time,
                            read: presentation.read,
                            deliveryStatus: presentation.deliveryStatus,
                          ),
                          first: first,
                          showStamp: false,
                          contentBefore: CallTile(call, stamp: presentation),
                        )
                      : MessageBubble(
                          message: presentation,
                          first: first,
                          maxWidth: MediaQuery.sizeOf(context).width * .82,
                          contentBefore: c.media.isEmpty
                              ? null
                              : SizedBox(
                                  width: 250,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final media in c.media)
                                        if (mediaUri(
                                              media['media_path'] ??
                                                  media['link'] ??
                                                  media['url'],
                                              apiBase,
                                            )
                                            case final Uri url)
                                          Material(
                                            color: Colors.transparent,
                                            child: MediaTile(
                                              MessageMedia(
                                                '${media['type']}',
                                                url,
                                                '${media['filename'] ?? media['media_name'] ?? media['type']}',
                                              ),
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                          contentAfter: !c.structured
                              ? null
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 250,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final f in c.fields.entries)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 5,
                                          ),
                                          child: Text(
                                            '${f.key}: ${f.value}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      for (final b in c.buttons)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 9,
                                            horizontal: 4,
                                          ),
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              top: BorderSide(color: T.edge),
                                            ),
                                          ),
                                          child: Text(
                                            b,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: T.green,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        )),
      ),
    );
    if (onReply != null) bubble = SwipeReply(onReply: onReply!, child: bubble);
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 7 : 1,
        bottom: m.reactions.isEmpty ? 1 : 4,
      ),
      child: Align(
        alignment: m.outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: m.outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Which agent sent it, once per group, as the web inbox shows.
            if (sender.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: Text(
                  sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: T.green,
                  ),
                ),
              ),
            bubble,
            if (m.status == 4 || m.status == 5)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .8,
                  ),
                  child: Text(
                    readableText(m.json['failed_reason']).isEmpty
                        ? 'Message failed to send'
                        : readableText(m.json['failed_reason']),
                    style: const TextStyle(fontSize: 11, color: T.danger),
                  ),
                ),
              ),
            if (m.reactions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: T.edge),
                  boxShadow: [
                    BoxShadow(
                      color: T.ink.withValues(alpha: .1),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  m.reactions.map((r) => r['emoji'] ?? '').join(' '),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A sticker as WhatsApp shows it: no bubble, the time on a small pill.
class StickerView extends StatelessWidget {
  const StickerView(this.url, this.message, {super.key});
  final Uri url;
  final Message message;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 150,
    child: Stack(
      children: [
        Positioned.fill(
          child: Image.network(
            url.toString(),
            fit: BoxFit.contain,
            semanticLabel: 'Sticker',
            errorBuilder: (_, _, _) => const Center(
              child: Icon(Icons.image_not_supported_outlined, color: T.muted),
            ),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.time,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white),
                  ),
                  if (message.out) ...[
                    const SizedBox(width: 3),
                    Icon(
                      switch (message.deliveryStatus ?? 0) {
                        0 => Icons.schedule,
                        1 => Icons.check,
                        4 || 5 => Icons.error_outline,
                        _ => Icons.done_all,
                      },
                      size: 13,
                      color: message.deliveryStatus == 3
                          ? const Color(0xFF7FD3FF)
                          : Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A call row as WhatsApp shows it: round icon with the call's direction,
/// "Voice call" or "Missed voice call", and the duration or outcome.
class CallTile extends StatelessWidget {
  const CallTile(this.call, {super.key, this.stamp});
  final VoiceCall call;

  /// The time and ticks, on the call row's last line as WhatsApp places it.
  final Message? stamp;
  @override
  Widget build(BuildContext context) {
    final colour = call.missed ? T.danger : T.green;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 240),
      child: Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 2),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colour.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                call.missed
                    ? Icons.call_missed
                    : call.incoming
                    ? Icons.call_received
                    : Icons.call_made,
                size: 20,
                color: colour,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    call.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  if (call.subtitle != null)
                    Text(
                      call.subtitle!,
                      style: const TextStyle(fontSize: 12.5, color: T.muted),
                    ),
                ],
              ),
            ),
            if (stamp != null) ...[
              const SizedBox(width: 10),
              // Level with the bottom of the call icon.
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: MessageStamp(stamp!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Time and ticks drawn over a photo, on a soft shadow, as WhatsApp does.
class OverlayStamp extends StatelessWidget {
  const OverlayStamp(this.message, {super.key});
  final Message message;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        message.time,
        style: const TextStyle(
          fontSize: 10.5,
          color: Colors.white,
          shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
        ),
      ),
      if (message.out) ...[
        const SizedBox(width: 3),
        Icon(
          switch (message.deliveryStatus ?? 0) {
            0 => Icons.schedule,
            1 => Icons.check,
            4 || 5 => Icons.error_outline,
            _ => Icons.done_all,
          },
          size: 14,
          color: message.deliveryStatus == 3
              ? const Color(0xFF7FD3FF)
              : Colors.white,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
        ),
      ],
    ],
  );
}

/// A photo or video filling its bubble; tap to open full screen.
class MediaFrame extends StatelessWidget {
  const MediaFrame(this.media, {super.key, this.stamp});
  final MessageMedia media;

  /// Drawn over the bottom of the media when there is no caption.
  final Message? stamp;
  @override
  Widget build(BuildContext context) {
    final video = media.type == 'video';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MediaViewer(media)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6.5),
        child: SizedBox(
          width: 254,
          height: video ? 170 : 254,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video)
                const ColoredBox(color: Color(0xFF1F2C34))
              else
                Image.network(
                  media.url.toString(),
                  fit: BoxFit.cover,
                  semanticLabel: 'Photo',
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const ColoredBox(
                          color: T.wash,
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: T.wash,
                    child: Icon(Icons.broken_image_outlined, color: T.muted),
                  ),
                ),
              if (video)
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              if (stamp != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.fromLTRB(0, 0, 7, 5),
                    alignment: Alignment.bottomRight,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black38],
                      ),
                    ),
                    child: OverlayStamp(stamp!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// WhatsApp's document card: a coloured file badge, the name, type and size.
class DocumentCard extends StatelessWidget {
  const DocumentCard(
    this.media, {
    super.key,
    required this.outgoing,
    this.size = '',
  });
  final MessageMedia media;
  final bool outgoing;
  final String size;
  @override
  Widget build(BuildContext context) {
    final extension = media.name.contains('.')
        ? media.name.split('.').last.toUpperCase()
        : 'FILE';
    final colour = switch (extension) {
      'PDF' => const Color(0xFFE5483D),
      'DOC' || 'DOCX' => const Color(0xFF2B79D6),
      'XLS' || 'XLSX' || 'CSV' => const Color(0xFF1E9E5A),
      'PPT' || 'PPTX' => const Color(0xFFE8792C),
      _ => const Color(0xFF8696A0),
    };
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MediaViewer(media)),
      ),
      child: Container(
        width: 250,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: outgoing
              ? Colors.black.withValues(alpha: .05)
              : const Color(0xFFF2F4F3),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 38,
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                extension.length > 4 ? extension.substring(0, 4) : extension,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [extension, if (size.isNotEmpty) size].join(' • '),
                    style: const TextStyle(fontSize: 11.5, color: T.muted),
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

/// A voice note's file, fetched once: its waveform, length, and a local copy
/// to play from. The file is public media, so no API credentials go with it.
class VoiceNoteFile {
  const VoiceNoteFile(this.file, this.waveform);
  final File file;
  final VoiceWaveform? waveform;

  static final _loaded = <String, Future<VoiceNoteFile>>{};

  /// Replaced in tests, which have no network.
  @visibleForTesting
  static Future<Uint8List> Function(Uri url) fetch = (url) async {
    final response = await Dio().getUri<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const []);
  };

  static Future<VoiceNoteFile> of(Uri url) =>
      _loaded[url.toString()] ??= _load(url).catchError((Object e) {
        _loaded.remove(url.toString());
        throw e;
      });

  static Future<VoiceNoteFile> _load(Uri url) async {
    final bytes = await fetch(url);
    final file = File(
      '${Directory.systemTemp.path}/voice-${url.toString().hashCode.toUnsigned(32)}.ogg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return VoiceNoteFile(file, VoiceWaveform.read(bytes));
  }
}

/// A voice note or audio file that plays inside its bubble, laid out as
/// WhatsApp does: the voice note's waveform, its length and the time on one
/// line beneath it. An audio file shows a plain track instead of a waveform.
class AudioNote extends StatefulWidget {
  const AudioNote(
    this.media, {
    super.key,
    required this.voice,
    required this.outgoing,
    required this.stamp,
  });
  final MessageMedia media;
  final bool voice, outgoing;
  final Message stamp;
  @override
  State<AudioNote> createState() => _AudioNoteState();
}

class _AudioNoteState extends State<AudioNote> {
  VideoPlayerController? player;
  VoiceNoteFile? note;
  bool loading = false, failed = false;

  @override
  void initState() {
    super.initState();
    // A voice note is a few kilobytes: fetched up front for its waveform.
    if (widget.voice) {
      VoiceNoteFile.of(widget.media.url).then((loaded) {
        if (mounted) setState(() => note = loaded);
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  /// Loaded on first play, so a long chat does not open a player per note.
  Future<void> toggle() async {
    final current = player;
    if (current != null && current.value.isInitialized) {
      current.value.isPlaying ? await current.pause() : await current.play();
      return;
    }
    setState(() {
      loading = true;
      failed = false;
    });
    VoiceNoteFile? local = note;
    if (widget.voice && local == null) {
      try {
        local = await VoiceNoteFile.of(widget.media.url);
      } catch (_) {
        // Fall back to streaming it.
      }
    }
    final controller = local != null
        ? VideoPlayerController.file(local.file)
        : VideoPlayerController.networkUrl(widget.media.url);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(() {
        final v = controller.value;
        if (v.isInitialized &&
            !v.isPlaying &&
            v.duration > Duration.zero &&
            v.position >= v.duration) {
          controller
            ..pause()
            ..seekTo(Duration.zero);
        }
      });
      setState(() {
        note = local ?? note;
        player = controller;
        loading = false;
      });
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  void seek(double fraction, Duration total) {
    final current = player;
    if (current == null || !current.value.isInitialized) return;
    current.seekTo(total * fraction.clamp(0.0, 1.0));
  }

  static String clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final current = player;
    return current == null
        ? body(null)
        : ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: current,
            builder: (_, value, _) => body(value),
          );
  }

  Widget body(VideoPlayerValue? v) {
    final playing = v?.isPlaying ?? false;
    final known = note?.waveform?.duration ?? Duration.zero;
    final total = (v?.duration ?? Duration.zero) > Duration.zero
        ? v!.duration
        : known;
    final position = v?.position ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final avatar = Stack(
      key: const ValueKey('audio-avatar'),
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: widget.voice ? T.selected : const Color(0xFFFF7F21),
          child: Icon(
            widget.voice ? Icons.person : Icons.headphones,
            color: widget.voice ? T.forest : Colors.white,
          ),
        ),
        if (widget.voice)
          Positioned(
            right: widget.outgoing ? null : -4,
            left: widget.outgoing ? -4 : null,
            bottom: -3,
            child: const Icon(Icons.mic, size: 18, color: T.green),
          ),
      ],
    );
    final button = SizedBox(
      width: 40,
      height: 40,
      child: AppIconButton(
        tooltip: playing ? 'Pause' : 'Play',
        onPressed: loading ? null : toggle,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                failed
                    ? Icons.error_outline
                    : playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 34,
                color: failed ? T.danger : T.secondary,
              ),
      ),
    );
    final bars = note?.waveform?.bars;
    final track = LayoutBuilder(
      builder: (context, box) {
        void at(Offset local) => seek(local.dx / box.maxWidth, total);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => at(d.localPosition),
          onHorizontalDragUpdate: (d) => at(d.localPosition),
          child: SizedBox(
            height: 26,
            width: box.maxWidth,
            child: CustomPaint(
              key: ValueKey(widget.voice ? 'voice-waveform' : 'audio-track'),
              painter: _TrackPainter(
                // A voice note still loading shows a flat waveform.
                bars: widget.voice ? (bars ?? List.filled(32, .14)) : null,
                progress: progress,
                played: widget.outgoing ? T.green : T.blue,
                rest: T.muted.withValues(alpha: .45),
              ),
            ),
          ),
        );
      },
    );
    final label = failed
        ? 'Could not play'
        : playing || position > Duration.zero
        ? clock(position)
        : total > Duration.zero
        ? clock(total)
        : widget.voice
        ? ''
        : 'Audio';
    return SizedBox(
      width: 252,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!widget.outgoing) ...[avatar, const SizedBox(width: 6)],
          button,
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                track,
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: failed ? T.danger : T.muted,
                      ),
                    ),
                    const Spacer(),
                    MessageStamp(widget.stamp),
                  ],
                ),
              ],
            ),
          ),
          if (widget.outgoing) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }
}

/// A voice note's waveform, or an audio file's plain track, filled up to the
/// play position, with the position's dot.
class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.rest,
  });
  final List<double>? bars;
  final double progress;
  final Color played, rest;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final split = size.width * progress;
    final values = bars;
    if (values == null) {
      final line = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(Offset(0, mid), Offset(size.width, mid), line..color = rest)
        ..drawLine(Offset(0, mid), Offset(split, mid), line..color = played);
    } else {
      final step = size.width / values.length;
      final bar = Paint()
        ..strokeWidth = math.min(3, step * .6)
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < values.length; i++) {
        final x = step * (i + .5);
        final half = math.max(1.5, values[i] * (size.height / 2 - 1));
        bar.color = x <= split ? played : rest;
        canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), bar);
      }
    }
    canvas.drawCircle(
      Offset(split.clamp(6, size.width - 6), mid),
      6,
      Paint()..color = played,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) =>
      old.progress != progress ||
      old.bars != bars ||
      old.played != played ||
      old.rest != rest;
}

/// A shared location: a map-styled tile with the place, opening Maps on tap.
class LocationCard extends StatelessWidget {
  const LocationCard(this.location, {super.key});
  final Json location;
  @override
  Widget build(BuildContext context) {
    final name = readableText(location['name']);
    final address = readableText(location['address']);
    final query = '${location['latitude']},${location['longitude']}';
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.https('maps.google.com', '/', {'q': query}),
        mode: LaunchMode.externalApplication,
      ),
      child: SizedBox(
        width: 254,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6.5),
              child: Container(
                height: 130,
                color: const Color(0xFFE3EDE4),
                child: const Center(
                  child: Icon(Icons.location_on, size: 42, color: T.danger),
                ),
              ),
            ),
            if (name.isNotEmpty || address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: T.ink,
                        ),
                      ),
                    if (address.isNotEmpty)
                      Text(
                        address,
                        style: const TextStyle(fontSize: 12, color: T.muted),
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
