import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_test.dart' show details;

/// One conversation on a fake server whose history the test edits, and
/// whose send reply it can hold back, as a slow network does.
class Server {
  final history = <Json>[
    {
      'id': 2,
      'type': 2,
      'message_id': 'wamid.2',
      'message_type': 'text',
      'message_body': 'Where is my order?',
      'created_at': '2026-11-03T10:00:00Z',
    },
  ];
  final sends = <RequestOptions>[];
  Completer<void>? hold;
  int failures = 0;

  String get tempId => '${sends.last.data['temp_message_id']}';

  /// The row the server saves for a send: the request it made, temp id and
  /// all, is what message_body_json stores (Interakt::storeMessage).
  Json saved(int id, String body, String temp) => {
    'id': id,
    'type': 1,
    'message_id': 'wamid.$id',
    'message_type': 'text',
    'message_body': body,
    'message_body_json': jsonEncode({
      'type': 'text',
      'text': {'body': body},
      'temp_message_id': temp,
    }),
    'message_status': 1,
    'created_at': '2026-11-03T10:05:00Z',
  };
}

void main() {
  late Server server;
  late MobileSession session;

  Future<void> open(WidgetTester tester) async {
    server = Server();
    final api = fakeApi((r, h) async {
      if (r.path == 'inbox/send') {
        server.sends.add(r);
        await server.hold?.future;
        if (server.failures > 0) {
          server.failures--;
          answer(r, h, {'success': false, 'message': 'Network down'}, 500);
          return;
        }
        final row = server.saved(
          100,
          '${r.data['body']}',
          '${r.data['temp_message_id']}',
        );
        server.history.removeWhere((m) => m['id'] == 100);
        server.history.add(row);
        answer(r, h, {
          'success': true,
          'sent_message': {
            ...row,
            'temp_message_id': r.data['temp_message_id'],
          },
        });
        return;
      }
      answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {'success': true, 'data': details()},
        'inbox/messages' => {
          'success': true,
          'data': [...server.history],
          'meta': {'has_more': false},
        },
        _ => {'success': true},
      });
    });
    session = MobileSession(api, MemoryStore())..user = {'id': 1};
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: LiveChat(session, {
          'id': 12,
          'profile_name': 'Alex',
          'wa_id': '919999999999',
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

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// What a realtime event does: the chat catches up with the server.
  Future<void> catchUp(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder bubble(String text) => find.textContaining(text, findRichText: true);

  test('the server’s row is the send it came from', () {
    final row = Server().saved(100, 'Hi', 'tmp-1');
    expect(ApiMessage(row).tempId, 'tmp-1');
    // A customer's message never claims to be one of our sends.
    expect(ApiMessage({...row, 'type': 2}).tempId, '');
  });

  testWidgets('a send the catch-up returns first is one bubble throughout', (
    tester,
  ) async {
    await open(tester);
    server.hold = Completer();
    await send(tester, 'On my way');
    // Sending: shown at once, with the clock.
    expect(bubble('On my way'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);

    // The webhook saved it and realtime announced it before the send's own
    // reply came back: the catch-up's row takes the sending bubble's place.
    server.history.add(server.saved(100, 'On my way', server.tempId));
    await catchUp(tester);
    expect(bubble('On my way'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsNothing);

    // The reply arriving late changes nothing.
    server.hold!.complete();
    await tester.pumpAndSettle();
    expect(bubble('On my way'), findsOneWidget);
    await close(tester);
  });

  testWidgets('one WhatsApp message stored twice shows once', (tester) async {
    await open(tester);
    server.history.addAll([
      for (final id in [5, 6])
        {
          'id': id,
          'type': 2,
          'message_id': 'wamid.same',
          'message_type': 'text',
          'message_body': 'Delivered twice by Meta',
          'created_at': '2026-11-03T10:01:00Z',
        },
    ]);
    await catchUp(tester);
    await tester.pumpAndSettle();
    expect(bubble('Delivered twice by Meta'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a failed send says so, and Retry sends it once', (tester) async {
    await open(tester);
    server.failures = 1;
    await send(tester, 'Are you there?');
    await tester.pumpAndSettle();
    expect(bubble('Are you there?'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Retry send'), findsOneWidget);

    await tester.tap(find.text('Retry send'));
    await tester.pumpAndSettle();
    expect(bubble('Are you there?'), findsOneWidget);
    expect(find.text('Retry send'), findsNothing);
    // The retry is the same message: the same temporary id both times.
    expect(server.sends, hasLength(2));
    expect(
      server.sends.first.data['temp_message_id'],
      server.sends.last.data['temp_message_id'],
    );
    await close(tester);
  });

  testWidgets('a document sends as its card, then keeps it once sent', (
    tester,
  ) async {
    sentFiles['tmp-doc'] = Attachment(
      XFile('/tmp/Quote-November.pdf'),
      'document',
      245760,
      'application/pdf',
    );
    addTearDown(() => sentFiles.remove('tmp-doc'));
    Widget row(Json json) => MaterialApp(
      theme: T.themeFor(TargetPlatform.android),
      home: Scaffold(
        body: LiveMessageView(
          message: ApiMessage(json),
          apiBase: 'https://dev.example.test/api/mobile/v1/',
          first: true,
        ),
      ),
    );
    // While sending (the chat's pending row): card, size, progress, clock.
    await tester.pumpWidget(
      row({
        'id': 'pending:tmp-doc',
        'temp_message_id': 'tmp-doc',
        'type': 1,
        'message_type': 'document',
        'message_body': '',
        'message_body_json': jsonEncode({
          'document': {'filename': 'Quote-November.pdf'},
        }),
        'message_status': 0,
        'upload_progress': .4,
        'created_at': '2026-11-03T10:05:00Z',
      }),
    );
    expect(find.byType(DocumentCard), findsOneWidget);
    expect(find.text('Quote-November.pdf'), findsOneWidget);
    expect(find.text('240 KB • PDF'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DocumentCard),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.schedule), findsOneWidget);

    // Sent (the server's row, same temporary id): same card, no progress.
    await tester.pumpWidget(
      row({
        'id': 301,
        'type': 1,
        'message_id': 'wamid.301',
        'message_type': 'document',
        'message_body': 'document_attached',
        'message_body_json': jsonEncode({
          'type': 'document',
          'document': {
            'link': 'https://dev.example.test/storage/a1b2.pdf',
            'filename': 'a1b2.pdf',
          },
          'temp_message_id': 'tmp-doc',
        }),
        'message_status': 1,
        'created_at': '2026-11-03T10:05:00Z',
      }),
    );
    expect(find.text('Quote-November.pdf'), findsOneWidget);
    expect(find.text('240 KB • PDF'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.schedule), findsNothing);
  });
}
