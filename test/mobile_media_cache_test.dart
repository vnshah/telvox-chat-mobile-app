import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/media_cache.dart';

/// A storage server: each file has bytes and an ETag; HEAD and conditional
/// requests behave as nginx serving /storage does.
class FakeStorage implements HttpClientAdapter {
  final files = <String, (List<int>, String)>{};
  final requests = <String>[];

  /// Says the file is longer than what it sends: a cut-off download.
  bool truncate = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.uri.path}');
    final file = files[options.uri.path];
    if (file == null) return ResponseBody.fromString('', 404);
    final (bytes, etag) = file;
    if (options.headers['If-None-Match'] == etag) {
      return ResponseBody.fromBytes(
        [],
        304,
        headers: {
          'etag': [etag],
        },
      );
    }
    final head = options.method == 'HEAD';
    return ResponseBody.fromBytes(
      head ? [] : (truncate ? bytes.sublist(0, bytes.length ~/ 2) : bytes),
      200,
      headers: {
        'etag': [etag],
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory folder;
  late FakeStorage server;
  var now = DateTime(2026, 11, 4, 10);

  MediaCache cache({int maxBytes = 1 << 20, int backgroundLimit = 1 << 20}) =>
      MediaCache(
        folder: () async => folder,
        dio: Dio()..httpClientAdapter = server,
        maxBytes: maxBytes,
        backgroundLimit: backgroundLimit,
        clock: () => now,
      );

  final photo = Uri.parse('https://chat.example.test/storage/7/image/a.jpg');
  final note = Uri.parse('https://chat.example.test/storage/7/audio/b.ogg');

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('media-cache-test');
    server = FakeStorage()
      ..files[photo.path] = (utf8.encode('photo-bytes'), '"v1"')
      ..files[note.path] = (utf8.encode('voice-note-bytes'), '"n1"');
    now = DateTime(2026, 11, 4, 10);
  });
  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  test('downloaded once, then opened from the phone', () async {
    final media = cache();
    final first = await media.file(photo);
    expect(await first.readAsString(), 'photo-bytes');
    expect(server.requests, ['GET ${photo.path}']);

    final again = await media.file(photo);
    expect(again.path, first.path);
    expect(server.requests, hasLength(1));
  });

  test('still there after the app is closed and opened again', () async {
    final before = cache();
    await before.file(photo);
    await before.flush();

    final reopened = cache();
    await reopened.load();
    final kept = reopened.ready(photo);
    expect(kept, isNotNull);
    expect(await kept!.readAsString(), 'photo-bytes');
    await reopened.file(photo);
    expect(server.requests, hasLength(1));
  });

  test('a copy that went missing is fetched again', () async {
    final media = cache();
    final file = await media.file(photo);
    await file.delete();
    expect(media.ready(photo), isNull);
    final again = await media.file(photo);
    expect(await again.readAsString(), 'photo-bytes');
    expect(server.requests, hasLength(2));
  });

  test('a cut-off download is never used', () async {
    final media = cache();
    server.truncate = true;
    await expectLater(media.file(photo), throwsA(isA<FileSystemException>()));
    expect(media.ready(photo), isNull);
    final leftovers = folder
        .listSync()
        .map((f) => f.path)
        .where((p) => !p.endsWith('index.json'));
    expect(leftovers, isEmpty);

    server.truncate = false;
    expect(await (await media.file(photo)).readAsString(), 'photo-bytes');
  });

  test('two screens asking at once share one download', () async {
    final media = cache();
    final both = await Future.wait([media.file(photo), media.file(photo)]);
    expect(both[0].path, both[1].path);
    expect(server.requests, hasLength(1));
  });

  test(
    'checked weekly: unchanged costs no download, changed replaces',
    () async {
      final media = cache();
      await media.file(photo);

      // Within the week: no check at all.
      now = now.add(const Duration(days: 3));
      await media.file(photo);
      expect(server.requests, hasLength(1));

      // After it: a HEAD with the ETag; unchanged is a 304.
      now = now.add(const Duration(days: 5));
      await media.file(photo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.requests.last, 'HEAD ${photo.path}');
      expect(server.requests.where((r) => r.startsWith('GET')), hasLength(1));

      // Changed on the server: fetched again and replaced.
      server.files[photo.path] = (utf8.encode('new-photo'), '"v2"');
      now = now.add(const Duration(days: 8));
      await media.file(photo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.requests.where((r) => r.startsWith('GET')), hasLength(2));
      expect(await (await media.file(photo)).readAsString(), 'new-photo');
    },
  );

  test('kept under its size, least recently used first', () async {
    final media = cache(maxBytes: 20);
    await media.file(photo); // 11 bytes
    now = now.add(const Duration(minutes: 1));
    await media.file(note); // 16 bytes: over 20, the photo goes
    expect(media.ready(photo), isNull);
    expect(media.ready(note), isNotNull);
  });

  test('signing out empties it; media is fetched again when needed', () async {
    final media = cache();
    await media.file(photo);
    await media.wipe();
    expect(await folder.exists(), isFalse);
    expect(media.ready(photo), isNull);
    expect(await (await media.file(photo)).readAsString(), 'photo-bytes');
    expect(server.requests.where((r) => r.startsWith('GET')), hasLength(2));
  });

  test(
    'a played voice note is kept for next time; a huge video is not',
    () async {
      final media = cache(backgroundLimit: 12);
      media.keep(note); // 16 bytes, over the limit
      media.keep(photo); // 11 bytes
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(media.ready(note), isNull);
      expect(media.ready(photo), isNotNull);
    },
  );
}
