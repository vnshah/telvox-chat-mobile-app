import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../ui/theme.dart';
import 'api.dart';
import 'media_cache.dart';
import 'media_save.dart' show DownloadButton;
import 'media_preview.dart';

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
    // Sent as JPEG: a photo is re-encoded before it goes (media_quality.dart).
    'heic': ('image', 'image/heic'),
    'heif': ('image', 'image/heif'),
    'webp': ('image', 'image/webp'),
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
    // Audio is re-encoded by the server to the Ogg/Opus voice note WhatsApp plays.
    'm4a': ('audio', 'audio/mp4'),
    'aac': ('audio', 'audio/aac'),
    'mp3': ('audio', 'audio/mpeg'),
    'ogg': ('audio', 'audio/ogg'),
    'opus': ('audio', 'audio/ogg'),
    'amr': ('audio', 'audio/amr'),
    'ppt': ('document', 'application/vnd.ms-powerpoint'),
    'pptx': (
      'document',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ),
  };

  /// The largest photo or video taken as picked: it is made to fit
  /// WhatsApp's 5 MB and 16 MB before it is sent (see [prepareMedia]).
  static const maxOriginalPhoto = 60 * 1024 * 1024,
      maxOriginalVideo = 2 * 1024 * 1024 * 1024;

  /// [original] is a photo or video that will be compressed before it is
  /// sent, so only [maxOriginalPhoto] and [maxOriginalVideo] bound it.
  static Future<Attachment> fromFile(
    XFile file, {
    String? requiredKind,
    List<String>? kinds,
    bool original = false,
  }) async {
    final format = formats[file.name.split('.').last.toLowerCase()];
    final allowed = kinds ?? [?requiredKind];
    if (format == null ||
        (allowed.isNotEmpty && !allowed.contains(format.$1))) {
      throw const ApiFailure(
        'Choose a supported image, video, audio file or document.',
      );
    }
    final size = await file.length();
    if (original && (format.$1 == 'image' || format.$1 == 'video')) {
      final max = format.$1 == 'image' ? maxOriginalPhoto : maxOriginalVideo;
      if (size <= 0 || size > max) {
        throw ApiFailure(
          'This ${format.$1 == 'image' ? 'photo' : 'video'} is too large to send.',
        );
      }
      return Attachment(file, format.$1, size, format.$2);
    }
    final maxMb = switch (format.$1) {
      'image' => 5,
      'video' || 'audio' => 16,
      _ => 100,
    };
    if (size <= 0 || size > maxMb * 1024 * 1024) {
      throw ApiFailure(switch (format.$1) {
        'video' => 'WhatsApp accepts videos up to 16 MB. Record or choose a shorter one.',
        'image' => 'WhatsApp accepts photos up to 5 MB.',
        _ => 'The ${format.$1} must be between 1 byte and $maxMb MB.',
      });
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

/// [kinds] narrows the picker (gallery: image and video); [kind] is one kind.
Future<Attachment?> chooseAttachment({
  String? kind,
  List<String>? kinds,
}) async {
  final allowed = kinds ?? [?kind];
  final extensions = Attachment.formats.entries
      .where((e) => allowed.isEmpty || allowed.contains(e.value.$1))
      .map((e) => e.key)
      .toList();
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: allowed.isEmpty ? 'Attachments' : allowed.join(' or '),
        extensions: extensions,
        uniformTypeIdentifiers: const ['public.data'],
      ),
    ],
  );
  return file == null ? null : Attachment.fromFile(file, kinds: allowed);
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
  // Inbound media is stored as `storage/<number>/...` and served from the site
  // root, as the web inbox loads it (`/${media_path}`); other relative paths
  // are public-disk paths under /storage.
  final resolved = uri.hasScheme
      ? uri
      : base.resolve(
          value.startsWith('/')
              ? value
              : value.startsWith('storage/')
              ? '/$value'
              : '/storage/$value',
        );
  if (resolved.scheme != 'https' ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty) {
    return null;
  }
  // A sent voice note's link is the route WhatsApp fetches it from, which
  // older servers refused for the phone app's file names. The same file is on
  // the public disk, which the phone plays as well.
  final voice = RegExp(r'^/media/voice-notes/([^/]+)/([^/]+)/([^/]+\.ogg)$')
      .firstMatch(resolved.path);
  if (voice != null && resolved.host == base.host) {
    return resolved.replace(
      path: '/storage/${voice[1]}/${voice[2]}/audio/${voice[3]}',
    );
  }
  return resolved;
}

/// Files this phone sent, by the send's temporary id. A sent photo, video or
/// voice note keeps drawing from the phone's own copy, so the server
/// confirming it changes its ticks, not its picture.
final sentFiles = <String, Attachment>{};

/// A message's media, from the phone's own copy when it sent it.
MessageMedia? sentMedia(String tempId, String type) {
  final file = sentFiles[tempId];
  if (file == null || file.kind != type || file.file.path.isEmpty) return null;
  return MessageMedia(file.kind, Uri.file(file.file.path), file.name);
}

/// The picture behind a media link: the phone's own file, or the server's,
/// downloaded once and kept on the phone (see [MediaCache]).
ImageProvider mediaImage(Uri url) => url.scheme == 'file'
    ? FileImage(File(url.toFilePath()))
    : CachedMediaImage(url);

/// A video or voice note: the phone's copy when there is one; otherwise it
/// streams from the server while a copy is kept for next time.
VideoPlayerController mediaPlayer(Uri url) {
  if (url.scheme == 'file') {
    return VideoPlayerController.file(File(url.toFilePath()));
  }
  final kept = MediaCache.instance.ready(url);
  if (kept != null) return VideoPlayerController.file(kept);
  MediaCache.instance.keep(url);
  return VideoPlayerController.networkUrl(url);
}

/// "245 KB", "3.1 MB", as WhatsApp sizes a document.
String fileSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).round()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

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
    // Outgoing rows nest the file under its type; inbound rows store it flat.
    final nested = object(payload[type]);
    final media = nested.isEmpty && payload['media_path'] != null
        ? payload
        : nested;
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
    onTap: () => ['image', 'sticker', 'video'].contains(media.type)
        ? openMediaPreview(context, media, heroTag: 'tile-${media.url}')
        : Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MediaViewer(media)),
          ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (media.type == 'image' || media.type == 'sticker')
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Hero(
              tag: 'tile-${media.url}',
              child: Image(
                image: mediaImage(media.url),
                width: 250,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 90,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
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
    final controller = mediaPlayer(widget.media.url);
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
    appBar: AppBar(
      title: Text(widget.media.name),
      actions: [DownloadButton(widget.media)],
    ),
    body: Center(
      child: ['image', 'sticker'].contains(widget.media.type)
          ? InteractiveViewer(
              child: Image(
                image: mediaImage(widget.media.url),
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

/// Where photos and videos come from: the phone's gallery or its camera.
/// A seam so tests need neither.
abstract class MediaPicker {
  Future<XFile?> photo({required bool camera});
  Future<XFile?> video({required bool camera});

  /// One photo or video from the gallery.
  Future<XFile?> galleryItem();

  /// Up to [limit] photos and videos from the gallery, as WhatsApp lets one
  /// pick several to send together.
  Future<List<XFile>> galleryItems({int limit = 30});
}

/// The system gallery and camera through image_picker, as the files are:
/// they are compressed at the quality chosen when they are sent (see
/// media_quality.dart), not here.
class DeviceMediaPicker implements MediaPicker {
  final _picker = ImagePicker();

  @override
  Future<XFile?> photo({required bool camera}) => _picker.pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
  );

  @override
  Future<XFile?> video({required bool camera}) => _picker.pickVideo(
    source: camera ? ImageSource.camera : ImageSource.gallery,
  );

  @override
  Future<XFile?> galleryItem() => _picker.pickMedia();

  @override
  Future<List<XFile>> galleryItems({int limit = 30}) =>
      _picker.pickMultipleMedia(limit: limit);
}

/// What a picked photo or video is. A file can be named for another format
/// than its data (IMG_0042.heic holding a JPEG), so the kind is read from
/// the file itself and the name corrected. Photos in HEIC or WebP are taken:
/// they go as JPEG once compressed. Anything else is refused here, before
/// it is uploaded.
Future<Attachment> pickedAttachment(XFile file) async {
  final head = await _head(file);
  final photo = _isJpeg(head)
      ? 'jpg'
      : _isPng(head)
      ? 'png'
      : _isWebp(head)
      ? 'webp'
      : _isHeif(head)
      ? 'heic'
      : null;
  final ext = file.name.split('.').last.toLowerCase();
  if (photo != null) {
    final named = switch (photo) {
      'jpg' => ext == 'jpg' || ext == 'jpeg',
      'heic' => ext == 'heic' || ext == 'heif',
      _ => ext == photo,
    };
    return Attachment.fromFile(
      named ? file : await _renamed(file, photo),
      requiredKind: 'image',
      original: true,
    );
  }
  if (ext == 'mp4' || ext == '3gp') {
    return Attachment.fromFile(file, requiredKind: 'video', original: true);
  }
  if (_isMp4Family(head)) {
    // Camera apps name a recording .mov or nothing at all; the data is MP4.
    return Attachment.fromFile(
      await _renamed(file, 'mp4'),
      requiredKind: 'video',
      original: true,
    );
  }
  throw const ApiFailure(
    'This photo or video format cannot be sent on WhatsApp. Send it as a document instead.',
  );
}

Future<Uint8List> _head(XFile file) async {
  final bytes = <int>[];
  await for (final chunk in file.openRead(0, 12)) {
    bytes.addAll(chunk);
  }
  return Uint8List.fromList(bytes);
}

bool _isJpeg(Uint8List b) =>
    b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
bool _isPng(Uint8List b) =>
    b.length >= 4 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4E &&
    b[3] == 0x47;

bool _isWebp(Uint8List b) =>
    b.length >= 12 &&
    String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(b.sublist(8, 12)) == 'WEBP';

/// The ISO media brand ("ftyp" box), or null when the file has none.
String? _brand(Uint8List b) =>
    b.length < 12 || String.fromCharCodes(b.sublist(4, 8)) != 'ftyp'
    ? null
    : String.fromCharCodes(b.sublist(8, 12));

/// An iPhone's (or a newer Android's) HEIC/HEIF still.
bool _isHeif(Uint8List b) {
  final brand = _brand(b);
  return brand != null &&
      (brand.startsWith('hei') ||
          brand.startsWith('hev') ||
          brand == 'mif1' ||
          brand == 'msf1');
}

/// ISO media with an MP4 or 3GP brand, not HEIC/HEIF or AVIF stills.
bool _isMp4Family(Uint8List b) {
  final brand = _brand(b);
  return brand != null &&
      !brand.startsWith('hei') &&
      !brand.startsWith('hev') &&
      !brand.startsWith('mif') &&
      !brand.startsWith('msf') &&
      brand != 'avif';
}

Future<XFile> _renamed(XFile file, String ext) async {
  final copy = File(
    '${Directory.systemTemp.path}/media-${DateTime.now().microsecondsSinceEpoch}.$ext',
  );
  await copy.writeAsBytes(await file.readAsBytes(), flush: true);
  return XFile(copy.path, name: copy.uri.pathSegments.last);
}
