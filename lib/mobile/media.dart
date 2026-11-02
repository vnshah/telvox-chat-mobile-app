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
  static Future<Attachment> fromFile(
    XFile file, {
    String? requiredKind,
    List<String>? kinds,
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

/// Where photos and videos come from: the phone's gallery or its camera.
/// A seam so tests need neither.
abstract class MediaPicker {
  Future<XFile?> photo({required bool camera});
  Future<XFile?> video({required bool camera});

  /// One photo or video from the gallery.
  Future<XFile?> galleryItem();
}

/// The system gallery and camera through image_picker. Photos are re-encoded
/// as WhatsApp sends them: at most 2560 px on the long side, JPEG quality 85,
/// which also turns an iPhone's HEIC photo into a JPEG WhatsApp accepts.
class DeviceMediaPicker implements MediaPicker {
  final _picker = ImagePicker();
  static const _maxSide = 2560.0, _quality = 85;

  @override
  Future<XFile?> photo({required bool camera}) => _picker.pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: _maxSide,
    maxHeight: _maxSide,
    imageQuality: _quality,
  );

  @override
  Future<XFile?> video({required bool camera}) => _picker.pickVideo(
    source: camera ? ImageSource.camera : ImageSource.gallery,
  );

  @override
  Future<XFile?> galleryItem() => _picker.pickMedia(
    maxWidth: _maxSide,
    maxHeight: _maxSide,
    imageQuality: _quality,
  );
}

/// What a picked photo or video is sent as. A re-encoded photo can keep its
/// original name (IMG_0042.heic) on JPEG data, so the kind is read from the
/// file itself and the name corrected; anything WhatsApp would refuse is
/// refused here, before it is uploaded.
Future<Attachment> pickedAttachment(XFile file) async {
  final head = await _head(file);
  final photo = _isJpeg(head)
      ? 'jpg'
      : _isPng(head)
      ? 'png'
      : null;
  if (photo != null) {
    final ext = file.name.split('.').last.toLowerCase();
    final named = photo == 'jpg' ? ext == 'jpg' || ext == 'jpeg' : ext == 'png';
    return Attachment.fromFile(
      named ? file : await _renamed(file, photo),
      requiredKind: 'image',
    );
  }
  final ext = file.name.split('.').last.toLowerCase();
  if (ext == 'mp4' || ext == '3gp') {
    return Attachment.fromFile(file, requiredKind: 'video');
  }
  if (_isMp4Family(head)) {
    // Camera apps name a recording .mov or nothing at all; the data is MP4.
    return Attachment.fromFile(
      await _renamed(file, 'mp4'),
      requiredKind: 'video',
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

/// ISO media ("ftyp" box) with an MP4 or 3GP brand, not HEIC/HEIF stills.
bool _isMp4Family(Uint8List b) {
  if (b.length < 12 || String.fromCharCodes(b.sublist(4, 8)) != 'ftyp') {
    return false;
  }
  final brand = String.fromCharCodes(b.sublist(8, 12));
  return !brand.startsWith('hei') &&
      !brand.startsWith('mif') &&
      brand != 'avif';
}

Future<XFile> _renamed(XFile file, String ext) async {
  final copy = File(
    '${Directory.systemTemp.path}/media-${DateTime.now().microsecondsSinceEpoch}.$ext',
  );
  await copy.writeAsBytes(await file.readAsBytes(), flush: true);
  return XFile(copy.path, name: copy.uri.pathSegments.last);
}
