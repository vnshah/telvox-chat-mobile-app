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
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

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
}

class FakeLocation implements LocationSource {
  @override
  Future<({double latitude, double longitude})> current() async =>
      (latitude: 23.0225, longitude: 72.5714);
}

void main() {
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

    test('a photo still in HEIC is refused before it is uploaded', () async {
      await expectLater(
        pickedAttachment(temp('still.heic', iso('heic'))),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('Send it as a document'),
          ),
        ),
      );
    });

    test('a video over 16 MB says how to fix it', () async {
      final big = temp('long.mp4', [
        ...iso('isom'),
        ...Uint8List(16 * 1024 * 1024 + 1),
      ]);
      await expectLater(
        pickedAttachment(big),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('16 MB'),
          ),
        ),
      );
    });
  });

  group('in a chat', () {
    late List<RequestOptions> sends;
    late MobileSession session;

    Future<void> openChat(WidgetTester tester) async {
      sends = [];
      final api = fakeApi((r, h) {
        if (r.path == 'inbox/send') sends.add(r);
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

    testWidgets('sends this phone’s location as a map pin', (tester) async {
      locationSource = FakeLocation();
      await openChat(tester);
      await attach(tester, 'Location');
      await tester.tap(find.text('Send your current location'));
      await tester.pumpAndSettle();
      final body = sends.single.data as Map;
      expect(body['message_type'], 'send_location');
      expect(body['location'], {
        'latitude': '23.0225',
        'longitude': '72.5714',
        'name': 'Location',
      });
      // Shown as the location card it becomes.
      expect(find.byType(LocationCard), findsOneWidget);
      await close(tester);
    });

    testWidgets('asks the customer for their location', (tester) async {
      await openChat(tester);
      await attach(tester, 'Location');
      await tester.tap(find.text('Ask for their location'));
      await tester.pumpAndSettle();
      final body = sends.single.data as Map;
      expect(body['message_type'], 'location');
      expect(body['body'], 'Please share your location.');
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
