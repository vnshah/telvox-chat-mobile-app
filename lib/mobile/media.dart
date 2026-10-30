import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';
import 'api.dart';

class Attachment {
  const Attachment(this.file, this.kind, this.size, this.mime);
  final XFile file;
  final String kind, mime;
  final int size;
  String get name => file.name;
  static const formats = <String, (String, String)>{
    'jpg': ('image', 'image/jpeg'),
    'jpeg': ('image', 'image/jpeg'),
    'png': ('image', 'image/png'),
    'mp4': ('video', 'video/mp4'),
    '3gp': ('video', 'video/3gpp'),
    'pdf': ('document', 'application/pdf'),
    'txt': ('document', 'text/plain'),
    'doc': ('document', 'application/msword'),
    'docx': (
      'document',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ),
    'xls': ('document', 'application/vnd.ms-excel'),
    'xlsx': (
      'document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
    'ppt': ('document', 'application/vnd.ms-powerpoint'),
    'pptx': (
      'document',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ),
  };
  static Future<Attachment> fromFile(XFile file, {String? requiredKind}) async {
    final format = formats[file.name.split('.').last.toLowerCase()];
    if (format == null || (requiredKind != null && format.$1 != requiredKind)) {
      throw const ApiFailure('Choose a supported image, video, or document.');
    }
    final size = await file.length();
    final maxMb = switch (format.$1) {
      'image' => 5,
      'video' => 16,
      _ => 100,
    };
    if (size <= 0 || size > maxMb * 1024 * 1024) {
      throw ApiFailure(
        'The ${format.$1} must be between 1 byte and $maxMb MB.',
      );
    }
    return Attachment(file, format.$1, size, format.$2);
  }

  /// Create a new stream for every attempt: multipart bodies cannot be reused.
  MultipartFile multipart() => MultipartFile.fromStream(
    file.openRead,
    size,
    filename: name,
    contentType: DioMediaType.parse(mime),
  );
}

Future<Attachment?> chooseAttachment({String? kind}) async {
  final extensions = Attachment.formats.entries
      .where((e) => kind == null || e.value.$1 == kind)
      .map((e) => e.key)
      .toList();
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: kind ?? 'Attachments',
        extensions: extensions,
        uniformTypeIdentifiers: const ['public.data'],
      ),
    ],
  );
  return file == null ? null : Attachment.fromFile(file, requiredKind: kind);
}

Future<Json> uploadAttachment(
  MobileApi api,
  Attachment attachment, {
  ProgressCallback? progress,
}) async => object(
  object(
    await api.request(
      'inbox/media/upload',
      method: 'POST',
      data: FormData.fromMap({
        'type': attachment.kind,
        'file': attachment.multipart(),
      }),
      onSendProgress: progress,
    ),
  )['data'],
);

/// Only network media is opened; never forward the API bearer to arbitrary URLs.
Uri? mediaUri(Object? value, String apiBase) {
  if (value is! String || value.trim().isEmpty) return null;
  final base = Uri.parse(apiBase);
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  final resolved = uri.hasScheme
      ? uri
      : base.resolve(value.startsWith('/') ? value : '/storage/$value');
  if (resolved.scheme != 'https' ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty) {
    return null;
  }
  return resolved;
}

class MessageMedia {
  const MessageMedia(this.type, this.url, this.name);
  final String type, name;
  final Uri url;
  static MessageMedia? fromMessage(Json message, String apiBase) {
    final type = '${message['message_type']}';
    if (!['image', 'video', 'audio', 'document', 'sticker'].contains(type)) {
      return null;
    }
    final payload = object(decoded(message['message_body_json']));
    final media = object(payload[type]);
    final uri = mediaUri(
      media['media_path'] ??
          media['link'] ??
          media['url'] ??
          payload['media_link'],
      apiBase,
    );
    return uri == null
        ? null
        : MessageMedia(
            type,
            uri,
            '${media['filename'] ?? media['media_name'] ?? type}',
          );
  }
}

class MediaTile extends StatelessWidget {
  const MediaTile(this.media, {super.key});
  final MessageMedia media;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MediaViewer(media)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (media.type == 'image' || media.type == 'sticker')
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              media.url.toString(),
              width: 250,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 90,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          )
        else
          ListTile(
            leading: Icon(
              media.type == 'audio'
                  ? Icons.play_circle_outline
                  : media.type == 'video'
                  ? Icons.video_library_outlined
                  : Icons.description_outlined,
            ),
            title: Text(
              media.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text('Tap to open'),
          ),
      ],
    ),
  );
}

class MediaViewer extends StatefulWidget {
  const MediaViewer(this.media, {super.key});
  final MessageMedia media;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> with WidgetsBindingObserver {
  VideoPlayerController? player;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  Future<void> initialize() async {
    if (!['audio', 'video'].contains(widget.media.type)) return;
    final controller = VideoPlayerController.networkUrl(widget.media.url);
    player = controller;
    try {
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => error = 'This media could not be loaded.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.media.name)),
    body: Center(
      child: ['image', 'sticker'].contains(widget.media.type)
          ? InteractiveViewer(
              child: Image.network(
                widget.media.url.toString(),
                errorBuilder: (_, _, _) =>
                    const Text('Image could not be loaded.'),
              ),
            )
          : player != null
          ? error != null
                ? Text(error!)
                : !player!.value.isInitialized
                ? const CircularProgressIndicator()
                : ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: player!,
                    builder: (context, value, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.media.type == 'video')
                          AspectRatio(
                            aspectRatio: value.aspectRatio,
                            child: VideoPlayer(player!),
                          )
                        else
                          const Icon(Icons.audiotrack, size: 72),
                        VideoProgressIndicator(player!, allowScrubbing: true),
                        AppIconButton(
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          onPressed: () => value.isPlaying
                              ? player!.pause()
                              : player!.play(),
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_circle
                                : Icons.play_circle,
                          ),
                        ),
                        if (value.hasError)
                          const Text(
                            'Playback failed. Reopen the media to retry.',
                          ),
                      ],
                    ),
                  )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description_outlined, size: 64),
                  Text(widget.media.name),
                  AppButton.filled(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        if (!await launchUrl(
                          widget.media.url,
                          mode: LaunchMode.externalApplication,
                        )) {
                          throw const ApiFailure(
                            'No app could open this document.',
                          );
                        }
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text('$e')));
                      }
                    },
                    child: const Text('Open document'),
                  ),
                ],
              ),
            ),
    ),
  );
}
