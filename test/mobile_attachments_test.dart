import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/camera.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/location.dart';
import 'package:telvox_chat_mobile_app/mobile/maps.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/media_quality.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/send_media.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'fake_media.dart';
import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

/// A file in the temp folder with [bytes], named as a camera would name it.
XFile temp(String name, List<int> bytes) {
  final file = File('${Directory.systemTemp.path}/attach-test-$name')
    ..writeAsBytesSync(bytes);
  return XFile(file.path, name: name);
}

final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 1)];
final png = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...List.filled(64, 1),
];
List<int> iso(String brand) => [
  0,
  0,
  0,
  0x18,
  ...'ftyp'.codeUnits,
  ...brand.codeUnits,
  ...List.filled(64, 1),
];

class FakeMediaPicker implements MediaPicker {
  FakeMediaPicker(this.file);
  final XFile? file;
  final asked = <String>[];
  @override
  Future<XFile?> photo({required bool camera}) async {
    asked.add('photo:$camera');
    return file;
  }

  @override
  Future<XFile?> video({required bool camera}) async {
    asked.add('video:$camera');
    return file;
  }

  @override
  Future<XFile?> galleryItem() async {
    asked.add('gallery');
    return file;
  }

  @override
  Future<List<XFile>> galleryItems({int limit = 30}) async {
    asked.add('gallery $limit');
    return [?file];
  }
}

class FakePlaces implements PlaceLookup {
  @override
  Future<Place?> at(double latitude, double longitude) async => (
    latitude: latitude,
    longitude: longitude,
    name: null,
    address: 'Ashram Road, Ahmedabad, Gujarat 380009, India',
  );

  @override
  Future<List<Place>> search(String query) async => [
    (
      latitude: 23.0300,
      longitude: 72.5800,
      name: query,
      address: 'Navrangpura, Ahmedabad, India',
    ),
  ];
}

class FakeLocation implements LocationSource {
  @override
  Future<({double latitude, double longitude})> current() async =>
      (latitude: 23.0225, longitude: 72.5714);
}

void main() {
  setUp(() => mediaCompressor = FakeCompressor());

  group('photos and videos are sent as WhatsApp accepts them', () {
    test('a re-encoded photo named .heic goes as a JPEG', () async {
      final a = await pickedAttachment(temp('IMG_0042.heic', jpeg));
      expect(a.kind, 'image');
      expect(a.mime, 'image/jpeg');
      expect(a.name, endsWith('.jpg'));
    });

    test('a PNG stays a PNG, and an MP4 named .mov goes as MP4', () async {
      expect((await pickedAttachment(temp('shot.png', png))).mime, 'image/png');
      final video = await pickedAttachment(temp('clip.mov', iso('isom')));
      expect(video.kind, 'video');
      expect(video.name, endsWith('.mp4'));
    });

    test('a photo still in HEIC or WebP is taken, to go as JPEG', () async {
      final heic = await pickedAttachment(temp('still.heic', iso('heic')));
      expect((heic.kind, heic.mime), ('image', 'image/heic'));
      final webp = await pickedAttachment(
        temp('sticker.png', [
          ...'RIFF'.codeUnits,
          0,
          0,
          0,
          0,
          ...'WEBP'.codeUnits,
        ]),
      );
      expect((webp.kind, webp.mime), ('image', 'image/webp'));
      expect(webp.name, endsWith('.webp'));
    });

    test('a video over 16 MB is taken: it is compressed to fit', () async {
      final big = temp('long.mp4', [
        ...iso('isom'),
        ...Uint8List(16 * 1024 * 1024 + 1),
      ]);
      expect((await pickedAttachment(big)).kind, 'video');
    });

    test('a file that is no photo or video says to send a document', () async {
      await expectLater(
        pickedAttachment(
          temp('notes.bin', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('Send it as a document'),
          ),
        ),
      );
    });
  });

  group('in a chat', () {
    late List<RequestOptions> sends;
    late MobileSession session;

    /// Holds the send's reply back, as a slow upload does.
    Completer<void>? holdSend;

    /// The send's reply; by default a bare success.
    Json Function(RequestOptions)? sendReply;

    Future<void> openChat(WidgetTester tester) async {
      sends = [];
      final api = fakeApi((r, h) async {
        if (r.path == 'inbox/send') {
          sends.add(r);
          await holdSend?.future;
          answer(r, h, sendReply?.call(r) ?? {'success': true});
          return;
        }
        answer(r, h, switch (r.path) {
          'inbox/messages' => {
            'success': true,
            'data': [
              {
                'id': 1,
                'type': 2,
                'message_type': 'text',
                'message_body': 'Where is your shop?',
                'created_at': DateTime.now().toUtc().toIso8601String(),
              },
            ],
            'meta': {'has_more': false},
          },
          'inbox/getContactDetails' => {
            'success': true,
            'data': {
              'contact': {
                'service_expiration_timestamp': '2099-01-01T00:00:00Z',
                'assigned_to': 1,
                'conversation_status': 1,
              },
              'assignUser': {'id': 1},
              'child_user_ids': [1],
            },
          },
          _ => {'success': true},
        });
      });
      session = MobileSession(api, MemoryStore())..user = {'id': 1};
      api
        ..token = 'test'
        ..wabaId = 7;
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: LiveChat(session, {
            'id': 2,
            'wa_id': '919999999999',
            'profile_name': 'Customer',
          }),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
    }

    Future<void> attach(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('the attach sheet offers the camera and location', (
      tester,
    ) async {
      await openChat(tester);
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      for (final label in [
        'Document',
        'Gallery',
        'Camera',
        'Location',
        'Audio',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await close(tester);
    });

    testWidgets('shares the point under the pin, with its address', (
      tester,
    ) async {
      locationSource = FakeLocation();
      placeLookup = FakePlaces();
      await openChat(tester);
      await attach(tester, 'Location');
      await tester.tap(find.text('Share a location'));
      await tester.pumpAndSettle();
      // Starts at this phone, named by the geocoder; a name can be added.
      expect(find.text('23.02250, 72.57140'), findsOneWidget);
      expect(
        find.text('Ashram Road, Ahmedabad, Gujarat 380009, India'),
        findsOneWidget,
      );
      expect(sends, isEmpty);
      await tester.enterText(find.byType(TextField).at(1), 'Head office');
      await tester.tap(find.byKey(const ValueKey('send-location')));
      await tester.pumpAndSettle();
      final body = sends.single.data as Map;
      expect(body['message_type'], 'send_location');
      expect(body['location'], {
        'latitude': '23.0225',
        'longitude': '72.5714',
        'name': 'Head office',
        'address': 'Ashram Road, Ahmedabad, Gujarat 380009, India',
      });
      // Shown as the location card it becomes.
      expect(find.byType(LocationCard), findsOneWidget);
      expect(find.text('Head office'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Open Head office in Google Maps',
        ),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('shares a place found by search', (tester) async {
      locationSource = FakeLocation();
      placeLookup = FakePlaces();
      await openChat(tester);
      await attach(tester, 'Location');
      await tester.tap(find.text('Share a location'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Law Garden');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('place-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('send-location')));
      await tester.pumpAndSettle();
      expect((sends.single.data as Map)['location'], {
        'latitude': '23.03',
        'longitude': '72.58',
        'name': 'Law Garden',
        'address': 'Navrangpura, Ahmedabad, India',
      });
      await close(tester);
    });

    testWidgets('asks the customer for their location in its own words', (
      tester,
    ) async {
      await openChat(tester);
      await attach(tester, 'Location');
      expect(find.text('Ask permission to call'), findsNothing);
      await tester.tap(find.text('Ask for their location'));
      await tester.pumpAndSettle();
      expect(sends, isEmpty);
      await tester.enterText(
        find.byType(TextField).last,
        'Please share the delivery location.',
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      final body = sends.single.data as Map;
      expect(body['message_type'], 'location');
      expect(body['body'], 'Please share the delivery location.');
      await close(tester);
    });

    testWidgets('asks permission to call where the number allows calling', (
      tester,
    ) async {
      await openChat(tester);
      session.config = {
        'capabilities': {
          'message_types': {'call_permission_request': true},
        },
      };
      await attach(tester, 'Location');
      await tester.tap(find.text('Ask permission to call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      final body = sends.single.data as Map;
      expect(body['message_type'], 'call_permission_request');
      expect(body['body'], isNotEmpty);
      await close(tester);
    });

    testWidgets('a photo from the camera is sent with its caption at once', (
      tester,
    ) async {
      openCamera = (_) async => CapturedMedia(
        temp('camera-shot.jpg', jpeg),
        video: false,
        caption: 'Here it is',
      );
      await openChat(tester);
      // Run on the real event loop: the photo is checked from its file.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Camera'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final send = sends.single.data as FormData;
      final fields = Map.fromEntries(send.fields);
      expect(fields['message_type'], 'image');
      expect(fields['body'], 'Here it is');
      expect(send.files.single.value.filename, endsWith('camera-shot.jpg'));
      // The camera hides while there is text to send, as on WhatsApp.
      await tester.enterText(find.byType(TextField), 'Typing');
      await tester.pump();
      expect(find.byTooltip('Camera'), findsNothing);
      await close(tester);
    });

    testWidgets('gallery picks are previewed, then each goes at the quality', (
      tester,
    ) async {
      final codec = FakeCompressor();
      mediaCompressor = codec;
      final picker = FakeMediaPicker(temp('gallery.jpg', jpeg));
      final (picking, previewing) = (mediaPicker, openSendMedia);
      addTearDown(() {
        mediaPicker = picking;
        openSendMedia = previewing;
      });
      mediaPicker = picker;
      List<Attachment>? previewed;
      openSendMedia = (_, items, to) async {
        previewed = items;
        return MediaBatch([
          for (final a in items) (a, 'From the gallery'),
        ], MediaQuality.hd);
      };
      await openChat(tester);
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gallery'));
      // Picked, checked, compressed and sent on the real event loop.
      for (var i = 0; i < 20 && sends.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(picker.asked, ['gallery 30']);
      expect(previewed!.single.kind, 'image');
      final fields = Map.fromEntries((sends.single.data as FormData).fields);
      expect(fields['message_type'], 'image');
      expect(fields['body'], 'From the gallery');
      // Compressed at HD, the first step HD tries.
      expect(codec.calls, ['photo 4096 90']);
      await close(tester);
    });

    testWidgets('a photo shows itself while it sends, and keeps it once sent', (
      tester,
    ) async {
      openCamera = (_) async =>
          CapturedMedia(temp('sending.jpg', jpeg), video: false, caption: '');
      holdSend = Completer();
      addTearDown(() {
        holdSend = null;
        sendReply = null;
      });
      sendReply = (r) {
        final temp = Map.fromEntries(
          (r.data as FormData).fields,
        )['temp_message_id'];
        return {
          'success': true,
          'sent_message': {
            'id': 300,
            'type': 1,
            'message_id': 'wamid.300',
            'message_type': 'image',
            'message_body': 'image_attached',
            'message_body_json': jsonEncode({
              'type': 'image',
              'image': {'link': 'https://dev.example.test/storage/x.jpg'},
              'temp_message_id': temp,
            }),
            'temp_message_id': temp,
            'message_status': 1,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        };
      };
      await openChat(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Camera'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // The photo itself, from the phone, under the upload ring; no file name.
      Finder photo() =>
          find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
      expect(photo(), findsOneWidget);
      expect(find.byType(UploadRing), findsOneWidget);
      expect(find.textContaining('sending.jpg'), findsNothing);
      final before = tester.element(photo());

      // Sent: the ring goes, the same picture stays — not swapped for the
      // server's copy, not drawn twice.
      holdSend!.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(UploadRing), findsNothing);
      expect(photo(), findsOneWidget);
      expect(find.byType(MediaFrame), findsOneWidget);
      expect(tester.element(photo()), same(before));
      await close(tester);
    });

    testWidgets('the emoji button swaps the keyboard for the emoji panel', (
      tester,
    ) async {
      await openChat(tester);
      expect(find.byKey(const ValueKey('emoji-panel')), findsNothing);
      await tester.tap(find.byTooltip('Emoji'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-panel')), findsOneWidget);
      expect(find.byTooltip('Keyboard'), findsOneWidget);
      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-panel')), findsNothing);
      await close(tester);
    });
  });

  testWidgets('the preview sends what was taken with the caption, or retakes', (
    tester,
  ) async {
    CapturedMedia? result;
    var popped = false;
    final shot = temp('preview.jpg', jpeg);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<CapturedMedia>(
                MaterialPageRoute(
                  builder: (_) => MediaPreviewPage(shot, video: false),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('retake')));
    await tester.pumpAndSettle();
    expect(popped, true);
    expect(result, isNull);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('caption')), 'Invoice');
    await tester.tap(find.byKey(const ValueKey('send-captured')));
    await tester.pumpAndSettle();
    expect(result?.caption, 'Invoice');
    expect(result?.file.path, shot.path);
    expect(result?.video, false);
  });
}
