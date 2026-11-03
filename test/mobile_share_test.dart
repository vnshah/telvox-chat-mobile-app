import 'dart:async';

import 'package:dio/dio.dart' show FormData, RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/share_intake.dart';
import 'package:telvox_chat_mobile_app/mobile/share_sheet.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_attachments_test.dart' show temp, jpeg;

/// A phone whose share sheet hands the app [initialFiles] on launch.
class FakeShares implements SharedFiles {
  FakeShares([this.initialFiles = const []]);
  final List<XFile> initialFiles;
  final more = StreamController<List<XFile>>.broadcast();
  int forgotten = 0;
  @override
  Future<List<XFile>> initial() async => initialFiles;
  @override
  Stream<List<XFile>> get arriving => more.stream;
  @override
  Future<void> done() async => forgotten++;
}

/// Real file reads (checking each shared file) finish only on the real
/// event loop: let them, a frame at a time.
Future<void> settleFiles(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('a share is held until the app can act on it', () {
    test('the launch share waits; take hands it over once', () async {
      final photo = temp('share-photo.jpg', jpeg);
      final source = FakeShares([photo]);
      final intake = ShareIntake(source);
      await intake.start();
      expect(intake.pending.value, [photo]);
      expect(intake.take(), [photo]);
      expect(intake.pending.value, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(source.forgotten, 1);
      expect(intake.take(), isNull);

      // A share while the app is open is offered the same way.
      source.more.add([photo, photo]);
      await Future<void>.delayed(Duration.zero);
      expect(intake.pending.value, hasLength(2));
      intake.dispose();
    });
  });

  group('send to chats, as WhatsApp shares', () {
    late List<RequestOptions> sends;
    late MobileSession session;
    var refuse = <Object?>{};

    final chats = [
      {
        'id': 12,
        'profile_name': 'Priya',
        'wa_id': '919812345678',
        'service_expiration_timestamp': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 5))
            .toIso8601String(),
      },
      {'id': 13, 'profile_name': 'Rahul', 'wa_id': '919898989898'},
      {
        'id': 14,
        'profile_name': 'Closed window',
        'wa_id': '919900000000',
        'service_expiration_timestamp': '2020-01-01T00:00:00Z',
      },
    ];

    Future<void> open(
      WidgetTester tester,
      List<XFile> files, {
      Json? config,
    }) async {
      sends = [];
      final api = fakeApi((r, h) {
        if (r.path == 'inbox/send') {
          sends.add(r);
          final fields = Map.fromEntries((r.data as FormData).fields);
          if (refuse.contains(fields['contact_id'])) {
            return answer(r, h, {
              'success': false,
              'message': 'This contact’s messaging window has expired.',
            }, 400);
          }
          return answer(r, h, {'success': true});
        }
        answer(r, h, r.path == 'inbox/contacts' ? chats : {'success': true});
      })..wabaId = 7;
      api.token = 'token';
      session = MobileSession(api, MemoryStore())
        ..user = {'id': 1}
        ..config = config;
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: ShareTargetsPage(session, files),
        ),
      );
      await tester.pumpAndSettle();
    }

    tearDown(() => refuse = {});

    testWidgets('pick chats, preview, send each file to each chat', (
      tester,
    ) async {
      final photo = temp('share-photo.jpg', jpeg);
      final pdf = temp('quote.pdf', [0x25, 0x50, 0x44, 0x46, 1, 2, 3]);
      final unknown = temp('archive.xyz', [1, 2, 3]);
      await open(tester, [photo, pdf, unknown]);

      expect(find.text('Send to…'), findsOneWidget);
      expect(find.text('3 files'), findsOneWidget);
      // The chat whose window is closed says so.
      expect(
        find.text('Window closed: only a template can be sent'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('share-chat-12')));
      await tester.tap(find.byKey(const ValueKey('share-chat-13')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-next')));
      await settleFiles(tester);

      // The preview: the photo and the document go; the unknown file says why.
      expect(find.text('Preview'), findsOneWidget);
      await tester.dragUntilVisible(
        find.textContaining('This file will not be sent'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.textContaining('This file will not be sent'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.text('To: Priya, Rahul'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Our new brochure');

      await tester.tap(find.byKey(const ValueKey('share-send')));
      await settleFiles(tester);

      // Two files to two chats: four messages, each in its own format.
      expect(sends, hasLength(4));
      final sent = [
        for (final s in sends) Map.fromEntries((s.data as FormData).fields),
      ];
      expect(sent.map((f) => f['contact_id']), ['12', '12', '13', '13']);
      expect(sent.map((f) => f['message_type']), [
        'image',
        'document',
        'image',
        'document',
      ]);
      expect(sent.first['body'], 'Our new brochure');
      expect(find.text('Sent to 2 chats'), findsOneWidget);
      session.dispose();
    });

    testWidgets('a refused chat is reported; the others still get it', (
      tester,
    ) async {
      refuse = {'13'};
      await open(tester, [temp('share-photo.jpg', jpeg)]);
      await tester.tap(find.byKey(const ValueKey('share-chat-12')));
      await tester.tap(find.byKey(const ValueKey('share-chat-13')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-next')));
      await settleFiles(tester);
      await tester.tap(find.byKey(const ValueKey('share-send')));
      await settleFiles(tester);
      expect(sends, hasLength(2));
      expect(find.text('1 not sent'), findsOneWidget);
      expect(find.textContaining('Rahul'), findsWidgets);
      session.dispose();
    });

    testWidgets('a ticketing-only number cannot share to chats', (
      tester,
    ) async {
      await open(
        tester,
        [temp('share-photo.jpg', jpeg)],
        config: {
          'capabilities': {
            'actions': [
              {'name': 'inbox.contacts.list', 'allowed': false},
              {'name': 'ticket-inbox-api.tickets.list', 'allowed': true},
            ],
          },
        },
      );
      expect(find.text('Cannot share here'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-chat-12')), findsNothing);
      session.dispose();
    });
  });
}
