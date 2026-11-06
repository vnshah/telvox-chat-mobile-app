import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/media_save.dart';

/// Download saves a chat's file where people look for it on a phone: photos
/// and videos in the gallery, everything else in Downloads (Files on iPhone),
/// always under the file's own name.
void main() {
  late List<(String, String)> saved;
  late Directory dir;

  setUp(() async {
    saved = [];
    dir = await Directory.systemTemp.createTemp('download-test-');
    saveToGallery = (file, {required video}) async =>
        saved.add((video ? 'gallery-video' : 'gallery-image', file.path));
    saveToDownloads = (file, name) async => saved.add(('downloads', name));
  });
  tearDown(() => dir.delete(recursive: true));

  Future<MessageMedia> media(String type, String stored, String name) async {
    final file = File('${dir.path}/$stored')..writeAsBytesSync([1, 2, 3]);
    return MessageMedia(type, file.uri, name);
  }

  test('a photo and a video go to the gallery, by their own names', () async {
    final photo = await media('image', '9f2c1.bin', 'shop-front.jpg');
    expect(await downloadMedia(photo), contains('Saved to'));
    expect(saved.single.$1, 'gallery-image');
    expect(saved.single.$2, endsWith('shop-front.jpg'));

    saved.clear();
    await downloadMedia(await media('video', 'clip.mp4', 'video'));
    expect(saved.single.$1, 'gallery-video');
    expect(saved.single.$2, endsWith('clip.mp4'));
  });

  test('a document goes to Downloads with its name and extension', () async {
    final doc = await media('document', 'a1b2.pdf', 'Quotation');
    final where = await downloadMedia(doc);
    expect(saved.single, ('downloads', 'Quotation.pdf'));
    expect(where, Platform.isIOS ? contains('Files') : 'Saved to Downloads.');
  });

  test('a name with path characters is made safe', () {
    expect(
      fileName(
        MessageMedia('document', Uri.parse('https://x.test/f.pdf'), 'a/b:c'),
      ),
      'a_b_c.pdf',
    );
  });

  test('a refused gallery says how to allow it', () async {
    saveToGallery = (_, {required video}) async =>
        throw const DownloadRefused();
    expect(
      () async => downloadMedia(await media('image', 'p.jpg', 'p.jpg')),
      throwsA(isA<DownloadRefused>()),
    );
  });
}
