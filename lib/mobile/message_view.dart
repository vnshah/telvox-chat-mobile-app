import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';
import '../ui/data.dart' show Message;
import '../ui/chat_message.dart';
import '../ui/conversation.dart' show SwipeReply;
import 'api.dart';
import 'maps.dart';
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

/// The icon WhatsApp puts beside a request's own button.
IconData? buttonIcon(String label) => switch (label) {
  'Send location' => Icons.location_on_outlined,
  'Provide address' => Icons.home_outlined,
  _ => null,
};

class LiveMessageView extends StatelessWidget {
  const LiveMessageView({
    super.key,
    required this.message,
    required this.apiBase,
    required this.first,
    this.onReply,
    this.onActions,
    this.onCallBack,
    this.contactName,
    this.businessName = '',
    this.onQuoteTap,
  });
  final ApiMessage message;
  final String apiBase;
  final String? contactName;

  /// This WhatsApp number's name, as a call permission request names it.
  final String businessName;

  /// Shows the message this one replies to.
  final VoidCallback? onQuoteTap;
  final bool first;
  final VoidCallback? onReply;
  final void Function(BuildContext)? onActions;

  /// "Tap to call back" on a missed call; null when the contact cannot be
  /// called now.
  final VoidCallback? onCallBack;
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
              color: T.incoming,
              borderRadius: BorderRadius.circular(8),
              boxShadow: T.bubbleShadow,
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
    // A file this phone sent draws from its own copy, before and after the
    // server confirms it, so the picture never reloads.
    final local = m.outgoing ? sentMedia(m.tempId, m.type) : null;
    final file =
        local ??
        (media == null || mediaUrl == null
            ? null
            : MessageMedia(
                '${media['type']}',
                mediaUrl,
                '${media['filename'] ?? media['media_name'] ?? media['type']}',
              ));
    // Only a send still on its way carries this (see the chat's pending row).
    final progress = (m.json['upload_progress'] as num?)?.toDouble();
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
    final place = locationOf(location);
    final barePin =
        place != null && place.name.isEmpty && place.address.isEmpty;
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
          progress: progress,
        ),
      ),
      'document' when file != null => MessageBubble(
        message: bare(c.text),
        first: first,
        maxWidth: 250 + 17,
        contentBefore: DocumentCard(
          file,
          outgoing: m.outgoing,
          size: switch (sentFiles[m.tempId]) {
            final Attachment sent when local != null => fileSize(sent.size),
            _ => '${media?['media_size'] ?? ''}',
          },
          progress: progress,
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
      'location' when barePin =>
        // A bare pin: the map alone, the time over it.
        MessageBubble(
          message: bare(''),
          first: first,
          maxWidth: 254 + 17,
          tight: true,
          showStamp: false,
          contentBefore: LocationCard(location, stamp: presentation),
        ),
      'location' when place != null => MessageBubble(
        message: bare(''),
        first: first,
        // The bubble hugs the card, as for a document.
        maxWidth: 254 + 17,
        tight: true,
        contentBefore: LocationCard(location),
      ),
      _ when c.request == 'call' => MessageBubble(
        message: presentation,
        first: first,
        maxWidth: width,
        contentAfter: CallPermissionCard(businessName),
        footer: const BubbleButtons([
          (Icons.expand_more, 'Choose preference'),
        ], iconAfter: true),
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
                          contentBefore: CallTile(
                            call,
                            onTap: call.missed ? onCallBack : null,
                            // WhatsApp shows a call's time without ticks.
                            stamp: Message('', time: presentation.time),
                          ),
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
                          // WhatsApp hangs a message's buttons under its time.
                          footer: c.buttons.isEmpty
                              ? null
                              : BubbleButtons([
                                  for (final b in c.buttons) (buttonIcon(b), b),
                                ]),
                          contentAfter: c.fields.isEmpty
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
                                    ],
                                  ),
                                ),
                        )),
      ),
    );
    bubble = SwipeReply(onReply: onReply, child: bubble);
    bubble = ReplyTap(onTap: onQuoteTap, child: bubble);
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

/// A call row as WhatsApp shows it: a round icon with the phone and the
/// call's direction (red when nobody answered), "Voice call" or "Missed call",
/// and beneath it the length or outcome with the time at its end.
class CallTile extends StatelessWidget {
  const CallTile(this.call, {super.key, this.stamp, this.onTap});
  final VoiceCall call;
  final VoidCallback? onTap;

  /// The time, on the outcome's line as WhatsApp places it. A call has no ticks.
  final Message? stamp;
  @override
  Widget build(BuildContext context) {
    final colour = call.missed || call.unanswered ? T.danger : T.secondary;
    final tile = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 250),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 5, 2, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('call-icon'),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .06),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Icon(Icons.phone, size: 21, color: colour),
                      ),
                      Positioned(
                        right: -2,
                        top: -1,
                        child: Icon(
                          call.incoming ? Icons.south_west : Icons.north_east,
                          size: 13,
                          color: colour,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    call.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (call.subtitle != null)
                        Flexible(
                          child: Text(
                            call.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: T.muted,
                            ),
                          ),
                        ),
                      if (stamp != null) ...[
                        const SizedBox(width: 16),
                        MessageStamp(stamp!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return onTap == null
        ? tile
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: tile,
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

/// A photo or video filling its bubble; tap to open full screen. While it
/// uploads, WhatsApp's ring shows how much has gone over it.
class MediaFrame extends StatelessWidget {
  const MediaFrame(this.media, {super.key, this.stamp, this.progress});
  final MessageMedia media;

  /// Drawn over the bottom of the media when there is no caption.
  final Message? stamp;

  /// Upload progress, 0–1, while sending; null once sent.
  final double? progress;
  @override
  Widget build(BuildContext context) {
    final video = media.type == 'video';
    return GestureDetector(
      onTap: progress != null
          ? null
          : () => Navigator.push(
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
                media.url.scheme == 'file'
                    ? VideoFirstFrame(media.url)
                    : const ColoredBox(color: Color(0xFF1F2C34))
              else
                Image(
                  image: mediaImage(media.url),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  semanticLabel: 'Photo',
                  loadingBuilder: (context, child, loading) => loading == null
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
              if (progress != null)
                Center(child: UploadRing(progress!))
              else if (video)
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

/// WhatsApp's upload ring: the share sent so far around an arrow.
class UploadRing extends StatelessWidget {
  const UploadRing(this.progress, {super.key, this.size = 52});
  final double progress;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sending, ${(progress * 100).round()} percent',
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .08),
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            // Indeterminate until the first bytes go, then the real share.
            value: progress > 0 ? progress : null,
            strokeWidth: 2.5,
            color: Colors.white,
          ),
          Icon(
            Icons.arrow_upward_rounded,
            color: Colors.white,
            size: size * .42,
          ),
        ],
      ),
    ),
  );
}

/// A video this phone is sending, drawn by its first frame.
class VideoFirstFrame extends StatefulWidget {
  const VideoFirstFrame(this.url, {super.key});
  final Uri url;
  @override
  State<VideoFirstFrame> createState() => _VideoFirstFrameState();
}

class _VideoFirstFrameState extends State<VideoFirstFrame> {
  VideoPlayerController? player;

  @override
  void initState() {
    super.initState();
    final controller = mediaPlayer(widget.url);
    controller.initialize().then(
      (_) {
        if (mounted) {
          setState(() => player = controller);
        } else {
          controller.dispose();
        }
      },
      onError: (_) {
        // No preview: the dark frame and play button stay.
        controller.dispose();
      },
    );
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = player;
    return ColoredBox(
      color: const Color(0xFF1F2C34),
      child: p == null
          ? null
          : FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: p.value.size.width,
                height: p.value.size.height,
                child: VideoPlayer(p),
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
    this.progress,
  });
  final MessageMedia media;
  final bool outgoing;
  final String size;

  /// Upload progress, 0–1, while sending; null once sent.
  final double? progress;
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
      onTap: progress != null
          ? null
          : () => Navigator.push(
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
              : Colors.white.withValues(alpha: .7),
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
            if (progress != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(
                    value: progress! > 0 ? progress : null,
                    strokeWidth: 2.5,
                    color: T.green,
                    semanticsLabel: 'Sending',
                  ),
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
    if (url.scheme == 'file') {
      // One this phone recorded: already here.
      final file = File(url.toFilePath());
      return VoiceNoteFile(file, VoiceWaveform.read(await file.readAsBytes()));
    }
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

  /// WhatsApp's playback speeds, cycled by the pill that stands in for the
  /// avatar while a voice note plays.
  double speed = 1;

  /// The one note playing: starting another pauses it, as on WhatsApp.
  static _AudioNoteState? _playing;

  void _claim() {
    final other = _playing;
    if (other != null && other != this && other.mounted) {
      other.player?.pause();
    }
    _playing = this;
  }

  Future<void> cycleSpeed() async {
    final next = switch (speed) {
      1 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };
    setState(() => speed = next);
    await player?.setPlaybackSpeed(next);
  }

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
    if (_playing == this) _playing = null;
    player?.dispose();
    super.dispose();
  }

  /// Loaded on first play, so a long chat does not open a player per note.
  Future<void> toggle() async {
    final current = player;
    if (current != null && current.value.isInitialized) {
      if (current.value.isPlaying) {
        await current.pause();
      } else {
        _claim();
        await current.play();
      }
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
        : mediaPlayer(widget.media.url);
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
      _claim();
      await controller.setPlaybackSpeed(speed);
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

  static String _speedLabel(double s) =>
      s == s.roundToDouble() ? '${s.round()}×' : '$s×';

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
    // Playing (or part-played), a voice note swaps its avatar for the speed.
    final Widget lead = widget.voice && (playing || position > Duration.zero)
        ? Semantics(
            button: true,
            label: 'Playback speed ${_speedLabel(speed)}',
            child: GestureDetector(
              key: const ValueKey('voice-speed'),
              onTap: cycleSpeed,
              child: Container(
                width: 44,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.secondary.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _speedLabel(speed),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          )
        : avatar;
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
          if (!widget.outgoing) ...[lead, const SizedBox(width: 6)],
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
          if (widget.outgoing) ...[const SizedBox(width: 8), lead],
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
/// A shared location as WhatsApp frames one: the map fills the bubble; a
/// named place puts its name and address under it, a bare pin carries the
/// time over the map. Tapping it opens Google Maps.
class LocationCard extends StatelessWidget {
  const LocationCard(this.location, {super.key, this.stamp});
  final Json location;

  /// Drawn over the map when the pin has no name or address to sit under.
  final Message? stamp;
  @override
  Widget build(BuildContext context) {
    final place = locationOf(location);
    if (place == null) return const SizedBox.shrink();
    final named = place.name.isNotEmpty || place.address.isNotEmpty;
    final label = place.name.isNotEmpty
        ? place.name
        : place.address.isNotEmpty
        ? place.address
        : 'Location';
    return Semantics(
      button: true,
      label: 'Open $label in Google Maps',
      child: GestureDetector(
        onTap: () => openInMaps(place.latitude, place.longitude),
        child: SizedBox(
          width: 254,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6.5),
                child: Stack(
                  children: [
                    LocationPreview(
                      place.latitude,
                      place.longitude,
                      height: 150,
                    ),
                    if (stamp != null && !named)
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
              if (named)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 7, 6, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (place.name.isNotEmpty)
                        Text(
                          place.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: T.ink,
                          ),
                        ),
                      if (place.address.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            place.address,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              color: T.muted,
                            ),
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
  }
}

/// A request for permission to call, as the customer sees it: "Can {the
/// business} call you?" with WhatsApp's preference button.
class CallPermissionCard extends StatelessWidget {
  const CallPermissionCard(this.business, {super.key});
  final String business;
  @override
  Widget build(BuildContext context) => Container(
    width: 250,
    margin: const EdgeInsets.only(top: 6, bottom: 2),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: T.surfaceHigh,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.call_outlined, size: 19, color: T.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                business.isEmpty
                    ? 'Can we call you?'
                    : 'Can $business call you?',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: T.ink,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'You can update your preference anytime in the business '
                'profile.',
                style: TextStyle(fontSize: 12, color: T.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
