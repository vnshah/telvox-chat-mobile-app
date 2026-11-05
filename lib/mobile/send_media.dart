import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';
import 'camera.dart' show VideoReview;
import 'media.dart';
import 'media_quality.dart';
import 'message_view.dart' show VideoFirstFrame;

/// Photos and videos picked together, each with its caption, and the one
/// quality they all go at.
class MediaBatch {
  const MediaBatch(this.items, this.quality);
  final List<(Attachment, String)> items;
  final MediaQuality quality;
}

/// WhatsApp's HD switch: "HD" in a rounded box, outlined at Standard and
/// filled at HD. Tapping it asks which quality (see [showQualitySheet]).
class QualityButton extends StatelessWidget {
  const QualityButton({
    super.key,
    required this.quality,
    required this.onPressed,
    this.colour = Colors.white,
  });
  final MediaQuality quality;
  final VoidCallback? onPressed;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final hd = quality == MediaQuality.hd;
    return IconButton(
      key: const ValueKey('quality-button'),
      tooltip: hd ? 'Media quality: HD' : 'Media quality: Standard',
      onPressed: onPressed,
      icon: Container(
        width: 30,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hd ? colour : Colors.transparent,
          border: Border.all(color: colour, width: 1.8),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          'HD',
          style: TextStyle(
            color: hd ? Colors.black : colour,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// The choice between Standard and HD, as WhatsApp asks it, with about how
/// large the photos and videos will be at each when that is known.
Future<MediaQuality?> showQualitySheet(
  BuildContext context,
  MediaQuality current, {
  Map<MediaQuality, int>? sizes,
}) => showModalBottomSheet<MediaQuality>(
  context: context,
  showDragHandle: true,
  builder: (sheet) {
    String about(MediaQuality q) {
      final size = sizes?[q];
      return size == null ? '' : ' · about ${fileSize(size)}';
    }

    return SafeArea(
      child: RadioGroup<MediaQuality>(
        groupValue: current,
        onChanged: (q) => Navigator.pop(sheet, q),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Media quality',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            RadioListTile<MediaQuality>(
              key: const ValueKey('quality-standard'),
              value: MediaQuality.standard,
              title: const Text('Standard quality'),
              subtitle: Text(
                'Faster to send, smaller files${about(MediaQuality.standard)}',
              ),
            ),
            RadioListTile<MediaQuality>(
              key: const ValueKey('quality-hd'),
              value: MediaQuality.hd,
              title: const Text('HD quality'),
              subtitle: Text(
                'Sharper, slower to send${about(MediaQuality.hd)}',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  },
);

/// Photos and videos before they go, as WhatsApp shows them: each full
/// screen to swipe through, its own caption, a strip of all of them to jump
/// between or remove, and the HD switch for the whole batch. Back cancels.
class SendMediaPage extends StatefulWidget {
  const SendMediaPage(this.items, {super.key, this.recipient});
  final List<Attachment> items;

  /// Who they go to, shown by Send.
  final String? recipient;

  @override
  State<SendMediaPage> createState() => _SendMediaPageState();
}

class _Picked {
  _Picked(this.attachment);
  final Attachment attachment;
  final caption = TextEditingController();
  MediaEstimate? estimate;
}

class _SendMediaPageState extends State<SendMediaPage> {
  late final items = [for (final a in widget.items) _Picked(a)];
  final pages = PageController();
  var quality = MediaQuality.standard;
  var index = 0;

  @override
  void initState() {
    super.initState();
    for (final item in items) {
      estimateMedia(item.attachment).then((e) {
        if (mounted) setState(() => item.estimate = e);
      });
    }
  }

  @override
  void dispose() {
    for (final item in items) {
      item.caption.dispose();
    }
    pages.dispose();
    super.dispose();
  }

  _Picked get current => items[index];

  bool get anyTooLong => items.any((i) => i.estimate?.tooLong ?? false);

  Map<MediaQuality, int>? get sizes => items.any((i) => i.estimate == null)
      ? null
      : MediaEstimate.total(items.map((i) => i.estimate!));

  void remove() {
    if (items.length == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      items.removeAt(index).caption.dispose();
      if (index >= items.length) index = items.length - 1;
    });
    pages.jumpToPage(index);
  }

  void show(int i) {
    setState(() => index = i);
    pages.jumpToPage(i);
  }

  Future<void> chooseQuality() async {
    final chosen = await showQualitySheet(context, quality, sizes: sizes);
    if (chosen != null && mounted) setState(() => quality = chosen);
  }

  void send() => Navigator.pop(
    context,
    MediaBatch([
      for (final item in items) (item.attachment, item.caption.text.trim()),
    ], quality),
  );

  @override
  Widget build(BuildContext context) {
    final tooLong = current.estimate?.tooLong ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                const Spacer(),
                QualityButton(quality: quality, onPressed: chooseQuality),
                IconButton(
                  key: const ValueKey('remove-media'),
                  tooltip: 'Remove',
                  onPressed: remove,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Expanded(
              child: PageView.builder(
                controller: pages,
                itemCount: items.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (_, i) {
                  final a = items[i].attachment;
                  return Center(
                    key: ValueKey('media-page-${a.file.path}'),
                    child: a.kind == 'video'
                        ? _VideoPage(a.file.path)
                        : InteractiveViewer(
                            child: Image.file(
                              File(a.file.path),
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.image_outlined,
                                color: Colors.white54,
                                size: 56,
                              ),
                            ),
                          ),
                  );
                },
              ),
            ),
            if (tooLong)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  '${tooLongMessage()} Remove it to send the rest.',
                  key: const ValueKey('too-long'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFB4A9),
                    fontSize: 13,
                  ),
                ),
              ),
            if (items.length > 1) _strip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: _CaptionField(
                key: ValueKey('caption-$index'),
                controller: current.caption,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.recipient ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Badge(
                    isLabelVisible: items.length > 1,
                    label: Text('${items.length}'),
                    backgroundColor: Colors.white,
                    textColor: Colors.black,
                    child: FloatingActionButton(
                      key: const ValueKey('send-media'),
                      tooltip: 'Send',
                      backgroundColor: T.green,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      onPressed: anyTooLong ? null : send,
                      child: const Icon(Icons.send),
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

  /// Every picked item small, the one shown outlined; tap to show it.
  Widget _strip() => SizedBox(
    height: 64,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final a = items[i].attachment;
        return GestureDetector(
          key: ValueKey('thumb-$i'),
          onTap: () => show(i),
          child: Container(
            width: 52,
            decoration: BoxDecoration(
              border: Border.all(
                color: i == index ? T.unread : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (a.kind == 'video')
                    VideoFirstFrame(Uri.file(a.file.path))
                  else
                    Image.file(
                      File(a.file.path),
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Colors.white12),
                    ),
                  if (a.kind == 'video')
                    const Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _CaptionField extends StatelessWidget {
  const _CaptionField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final round = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
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
        border: round,
        enabledBorder: round,
        focusedBorder: round,
      ),
    );
  }
}

/// A picked video, played when tapped.
class _VideoPage extends StatefulWidget {
  const _VideoPage(this.path);
  final String path;
  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final player = VideoPlayerController.file(File(widget.path));

  @override
  void initState() {
    super.initState();
    player.initialize().then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => player.value.isInitialized
      ? VideoReview(player)
      : const CircularProgressIndicator(color: Colors.white);
}
