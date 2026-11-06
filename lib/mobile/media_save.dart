import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import 'media.dart' show MessageMedia;
import 'media_cache.dart';

/// Hands a file to the phone's share sheet, where Save to Files, Save image
/// and the other apps are. Replaced in tests.
Future<void> Function(File file, String name, Rect? origin) shareFile =
    (file, name, origin) => SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        fileNameOverrides: [name],
        sharePositionOrigin: origin,
      ),
    );

/// Puts a photo or video in the phone's gallery (Photos on iPhone).
/// Replaced in tests.
Future<void> Function(File file, {required bool video}) saveToGallery =
    (file, {required video}) async {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const DownloadRefused();
      }
      video ? await Gal.putVideo(file.path) : await Gal.putImage(file.path);
    };

/// Puts any other file in Downloads on Android, or in the app's folder in
/// the Files app on iPhone. Replaced in tests.
Future<void> Function(File file, String name) saveToDownloads =
    (file, name) async {
      final dot = name.lastIndexOf('.');
      await FileSaver.instance.saveFile(
        name: dot > 0 ? name.substring(0, dot) : name,
        filePath: file.path,
        fileExtension: dot > 0 ? name.substring(dot + 1) : '',
      );
    };

/// The phone would not let the app save to the gallery.
class DownloadRefused implements Exception {
  const DownloadRefused();
  @override
  String toString() =>
      'Allow Telvox Chat to add photos in Settings to save this.';
}

/// The phone's copy of [media], fetched first when it is not here.
Future<File> mediaFile(MessageMedia media) => media.url.isScheme('file')
    ? Future.value(File(media.url.toFilePath()))
    : MediaCache.instance.file(media.url);

/// The web viewer's Download, on a phone: the file is fetched (or taken
/// from the phone's copy) and offered to save or send elsewhere.
Future<void> saveMedia(BuildContext context, MessageMedia media) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  await shareFile(await mediaFile(media), fileName(media), origin);
}

/// Saves [media] onto the phone, where people look for it: a photo or video
/// in the gallery, anything else in Downloads (Files on iPhone). Says where.
Future<String> downloadMedia(MessageMedia media) async {
  final name = fileName(media);
  final cached = await mediaFile(media);
  // The gallery and Downloads name the file by its own name and extension;
  // the phone's copy is kept under a hashed name.
  final named = await _named(cached, name);
  try {
    if (media.type == 'image' || media.type == 'video') {
      await saveToGallery(named, video: media.type == 'video');
      return Platform.isIOS ? 'Saved to Photos.' : 'Saved to Gallery.';
    }
    await saveToDownloads(named, name);
    return Platform.isIOS
        ? 'Saved to Files › Telvox Chat.'
        : 'Saved to Downloads.';
  } finally {
    if (named.path != cached.path) {
      named.delete().catchError((_) => named);
    }
  }
}

Future<File> _named(File file, String name) async {
  final base = file.path.split(Platform.pathSeparator).last;
  if (base == name) return file;
  final dir = await Directory.systemTemp.createTemp('telvox-save-');
  return file.copy('${dir.path}${Platform.pathSeparator}$name');
}

/// A name the saved file keeps: the message's file name, or the address's
/// last part, with its extension.
@visibleForTesting
String fileName(MessageMedia media) {
  final last = media.url.pathSegments.isEmpty
      ? ''
      : media.url.pathSegments.last;
  final name = media.name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (name.isEmpty || name == media.type) return last.isEmpty ? 'file' : last;
  final ext = last.contains('.') ? last.substring(last.lastIndexOf('.')) : '';
  return name.contains('.') || ext.isEmpty ? name : '$name$ext';
}

/// Download, wherever a file is shown: saves it onto the phone and says
/// where it went. Spins while the file is fetched.
class DownloadButton extends StatefulWidget {
  const DownloadButton(this.media, {super.key, this.color, this.size = 24});
  final MessageMedia media;
  final Color? color;
  final double size;
  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  var busy = false;

  Future<void> download() async {
    if (busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => busy = true);
    try {
      final where = await downloadMedia(widget.media);
      messenger?.showSnackBar(SnackBar(content: Text(where)));
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            e is DownloadRefused ? '$e' : 'The file could not be saved.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('download-file'),
    tooltip: 'Download',
    color: widget.color,
    iconSize: widget.size,
    visualDensity: VisualDensity.compact,
    onPressed: busy ? null : download,
    icon: busy
        ? SizedBox.square(
            dimension: widget.size * .8,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.color,
            ),
          )
        : const Icon(Icons.download_rounded),
  );
}
