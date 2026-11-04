import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/media_cache.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;
import 'support/ui.dart';

/// Serves one generated photo for every media link.
class _PhotoServer implements HttpClientAdapter {
  _PhotoServer(this.bytes);
  final List<int> bytes;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    options.method == 'HEAD' ? [] : bytes,
    200,
    headers: {
      Headers.contentLengthHeader: ['${bytes.length}'],
    },
  );
  @override
  void close({bool force = false}) {}
}

/// Review images of messages drawn as WhatsApp draws them.
void main() {
  testWidgets('WhatsApp-style messages render for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A warm 4:3 photo standing in for the template's header.
    final photo = img.Image(width: 400, height: 300);
    for (final p in photo) {
      p
        ..r = 120 + (p.x * 120 ~/ 400)
        ..g = 40 + (p.y * 90 ~/ 300)
        ..b = 30;
    }
    final folder = await tester.runAsync(
      () => Directory.systemTemp.createTemp('wa-shots'),
    );
    final previous = MediaCache.instance;
    MediaCache.instance = MediaCache(
      folder: () async => folder!,
      dio: Dio()..httpClientAdapter = _PhotoServer(img.encodePng(photo)),
    );
    addTearDown(() => MediaCache.instance = previous);

    final now = DateTime.now().toUtc().toIso8601String();
    final rows = [
      {
        'id': 1,
        'type': 1,
        'message_id': 'wamid.t',
        'message_type': 'template',
        'message_body': 'opt_in',
        'message_body_json': jsonEncode({
          'preview': [
            {
              'type': 'HEADER',
              'image': {'link': 'https://chat.example.test/storage/diyas.jpg'},
            },
            {
              'type': 'BODY',
              'text':
                  'Hi rahil Thanks for confirming opt-in! You will now '
                  'receive notifications via WhatsApp.',
            },
            {
              'type': 'FOOTER',
              'text': 'Send STOP to stop receiving these messages from us',
            },
            {
              'type': 'BUTTONS',
              'buttons': [
                {'type': 'QUICK_REPLY', 'text': 'Ok'},
                {'type': 'URL', 'text': 'Visit our website'},
              ],
            },
          ],
        }),
        'created_at': now,
      },
      {
        'id': 2,
        'type': 2,
        'message_id': 'wamid.f',
        'message_type': 'interactive',
        'message_body_json': jsonEncode({
          'interactive': {
            'type': 'nfm_reply',
            'nfm_reply': {
              'response_json': jsonEncode({
                'full_name': 'Ravin',
                'business_name': 'Bussiness.ravin&lakhani',
                'mobile_number': '9376161238',
                'email_address': 'ravin@lakhani.com',
                'preferred_demo_date': '2026-11-04',
              }),
            },
          },
        }),
        'created_at': now,
      },
      {
        'id': 3,
        'type': 2,
        'message_id': 'wamid.q',
        'message_type': 'text',
        'message_body': 'Where is your shop?',
        'created_at': now,
      },
    ];
    final api = fakeApi(
      (r, h) => answer(r, h, switch (r.path) {
        'inbox/messages' => {
          'success': true,
          'data': rows,
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
      }),
    );
    final session = MobileSession(api, MemoryStore())..user = {'id': 1};
    api
      ..token = 'test'
      ..wabaId = 7;
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: LiveChat(session, {
              'id': 2,
              'wa_id': '919724105194',
              'profile_name': 'Rahil',
            }),
          ),
        ),
      );
      // The photo is fetched into the cache, then drawn.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/wa-template.png');

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/wa-form.png');

      await tester.tap(find.byKey(const ValueKey('view-form-response')));
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/wa-form-sheet.png');
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();

      await tester.longPress(
        find.textContaining('Where is your shop?', findRichText: true),
      );
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/wa-select.png');
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });
}
