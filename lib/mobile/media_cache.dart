import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Chat media kept on the phone after its first download: photos, stickers,
/// videos and voice notes open from the phone's copy afterwards, across
/// restarts, instead of being fetched from the server again.
///
/// The copies live in the app's cache folder, so clearing the app's cache or
/// storage removes them too; anything missing is simply fetched again. Each
/// file is written to a `.part` file and renamed only once complete, so a
/// cut-off download is never used. A copy is checked against the server at
/// most once a [revalidateAfter] (ETag / Last-Modified: unchanged costs no
/// download). The folder is kept under [maxBytes], least recently used first.
/// Signing out empties it.
class MediaCache {
  MediaCache({
    required this.folder,
    Dio? dio,
    this.maxBytes = 500 * 1024 * 1024,
    this.revalidateAfter = const Duration(days: 7),
    this.backgroundLimit = 50 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 60),
             ),
           ),
       _now = clock ?? DateTime.now;

  /// The app's cache folder, `media/` within it.
  MediaCache.platform()
    : this(
        folder: () async =>
            Directory('${(await getApplicationCacheDirectory()).path}/media'),
      );

  /// The one the app uses; tests put their own here.
  static MediaCache instance = MediaCache.platform();

  /// Where the copies live.
  final Future<Directory> Function() folder;
  final Dio _dio;
  final DateTime Function() _now;
  final int maxBytes;
  final Duration revalidateAfter;

  /// Files larger than this are not saved while they are being streamed
  /// (a long video plays from the server rather than being fetched twice).
  final int backgroundLimit;

  Directory? _dir;
  Map<String, _Entry>? _index;
  Future<void>? _loading;
  final _fetching = <String, Future<File>>{};
  Timer? _saveSoon;

  static String keyFor(Uri url) =>
      sha256.convert(utf8.encode(url.toString())).toString();

  /// Reads the index once; [ready] knows nothing before this.
  Future<void> load() => _loading ??= () async {
    final dir = await folder();
    await dir.create(recursive: true);
    _dir = dir;
    final index = <String, _Entry>{};
    try {
      final saved = jsonDecode(
        await File('${dir.path}/index.json').readAsString(),
      );
      if (saved is Map) {
        for (final e in saved.entries) {
          final entry = _Entry.fromJson(e.value);
          if (entry != null) index['${e.key}'] = entry;
        }
      }
    } catch (_) {
      // No index yet, or a broken one: start afresh; files are re-fetched.
    }
    _index = index;
  }();

  /// The phone's copy of [url] if it is already here and whole, without
  /// waiting: for players that must be created at once.
  File? ready(Uri url) {
    final dir = _dir;
    final entry = _index?[keyFor(url)];
    if (dir == null || entry == null) return null;
    final file = File('${dir.path}/${entry.file}');
    try {
      if (file.lengthSync() != entry.bytes) return null;
    } catch (_) {
      return null;
    }
    entry.usedAt = _now();
    _remember();
    return file;
  }

  /// The phone's copy of [url], fetched first if it is not here (or is
  /// missing or incomplete). One download per file at a time.
  Future<File> file(Uri url) async {
    await load();
    final key = keyFor(url);
    final have = ready(url);
    if (have != null) {
      final entry = _index![key]!;
      if (_now().difference(entry.checkedAt) > revalidateAfter) {
        unawaited(_revalidate(url, key, entry).catchError((_) {}));
      }
      return have;
    }
    // A block, not an arrow: whenComplete waits on a returned future, and
    // remove() would return this very download.
    return _fetching[key] ??= _download(url, key).whenComplete(() {
      _fetching.remove(key);
    });
  }

  /// Saves [url] for next time while it is played from the server, unless
  /// it is very large.
  void keep(Uri url) {
    unawaited(() async {
      try {
        await load();
        if (ready(url) != null) return;
        final head = await _dio.headUri<void>(url);
        final size = int.tryParse(
          head.headers.value(Headers.contentLengthHeader) ?? '',
        );
        if (size != null && size > backgroundLimit) return;
        await file(url);
      } catch (_) {
        // Next time it streams again.
      }
    }());
  }

  Future<File> _download(Uri url, String key) async {
    final dir = _dir!;
    final name = '$key${_extension(url)}';
    final part = File('${dir.path}/$name.part');
    final response = await _dio.downloadUri(url, part.path);
    final bytes = await part.length();
    final expected = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (bytes == 0 || (expected != null && expected != bytes)) {
      await part.delete().catchError((_) => part);
      throw const FileSystemException('Incomplete download');
    }
    final file = await part.rename('${dir.path}/$name');
    final now = _now();
    _index![key] = _Entry(
      url: url.toString(),
      file: name,
      bytes: bytes,
      etag: response.headers.value('etag'),
      modified: response.headers.value('last-modified'),
      checkedAt: now,
      usedAt: now,
    );
    await _trim();
    _remember();
    return file;
  }

  /// Asks the server whether the copy is still current; a changed file
  /// replaces it, an unchanged one costs no download.
  Future<void> _revalidate(Uri url, String key, _Entry entry) async {
    final response = await _dio.headUri<void>(
      url,
      options: Options(
        validateStatus: (_) => true,
        headers: {
          'If-None-Match': ?entry.etag,
          'If-Modified-Since': ?entry.modified,
        },
      ),
    );
    final status = response.statusCode ?? 0;
    final etag = response.headers.value('etag');
    final modified = response.headers.value('last-modified');
    final changed =
        status == 200 &&
        ((etag != null && etag != entry.etag) ||
            (modified != null && modified != entry.modified));
    if (changed) {
      await _download(url, key);
      return;
    }
    // Unchanged (304, or 200 with the same validators), or gone from the
    // server: the phone's copy stays.
    if (status == 304 || status == 200 || status == 404 || status == 410) {
      entry.checkedAt = _now();
      _remember();
    }
  }

  /// Keeps the folder under [maxBytes], least recently used first.
  Future<void> _trim() async {
    final index = _index!;
    var total = index.values.fold<int>(0, (n, e) => n + e.bytes);
    if (total <= maxBytes) return;
    final oldest = index.entries.toList()
      ..sort((a, b) => a.value.usedAt.compareTo(b.value.usedAt));
    for (final e in oldest) {
      if (total <= maxBytes) break;
      index.remove(e.key);
      total -= e.value.bytes;
      await File('${_dir!.path}/${e.value.file}')
          .delete()
          .catchError((_) => File(''));
    }
  }

  /// Signing out: no other account sees this one's media.
  Future<void> wipe() async {
    _saveSoon?.cancel();
    try {
      final dir = _dir ?? await folder();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Nothing to remove.
    }
    _index = {};
    _dir = null;
    _loading = null;
  }

  /// Writes the index soon after a change, once for a burst of them.
  void _remember() {
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(milliseconds: 500), () {
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _saveSoon?.cancel();
    final dir = _dir;
    final index = _index;
    if (dir == null || index == null) return;
    try {
      final tmp = File('${dir.path}/index.json.part');
      await tmp.writeAsString(
        jsonEncode({for (final e in index.entries) e.key: e.value.toJson()}),
      );
      await tmp.rename('${dir.path}/index.json');
    } catch (_) {
      // Written again on the next change.
    }
  }

  static String _extension(Uri url) {
    final last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    final dot = last.lastIndexOf('.');
    if (dot < 0 || last.length - dot > 6) return '';
    return last.substring(dot).toLowerCase();
  }
}

class _Entry {
  _Entry({
    required this.url,
    required this.file,
    required this.bytes,
    required this.checkedAt,
    required this.usedAt,
    this.etag,
    this.modified,
  });
  final String url, file;
  final int bytes;
  final String? etag, modified;
  DateTime checkedAt, usedAt;

  Map<String, Object?> toJson() => {
    'url': url,
    'file': file,
    'bytes': bytes,
    'etag': etag,
    'modified': modified,
    'checked_at': checkedAt.toIso8601String(),
    'used_at': usedAt.toIso8601String(),
  };

  static _Entry? fromJson(Object? json) {
    if (json is! Map) return null;
    final checked = DateTime.tryParse('${json['checked_at']}');
    final used = DateTime.tryParse('${json['used_at']}');
    final bytes = json['bytes'];
    if (json['file'] is! String || bytes is! int || checked == null) {
      return null;
    }
    return _Entry(
      url: '${json['url']}',
      file: json['file'] as String,
      bytes: bytes,
      etag: json['etag'] as String?,
      modified: json['modified'] as String?,
      checkedAt: checked,
      usedAt: used ?? checked,
    );
  }
}

/// A picture from the server, drawn from the phone's copy (fetched once).
@immutable
class CachedMediaImage extends ImageProvider<CachedMediaImage> {
  const CachedMediaImage(this.url);
  final Uri url;

  @override
  Future<CachedMediaImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CachedMediaImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url.toString(),
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final file = await MediaCache.instance.file(url);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('Empty media file');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is CachedMediaImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
