import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/message_content.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/send_policy.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/ui/chat_message.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'support/ui.dart';

Json details({String expiry = '2099-01-01T00:00:00Z'}) => {
  'contact': {
    'id': 12,
    'assigned_to': 1,
    'conversation_status': 1,
    'service_expiration_timestamp': expiry,
  },
  'assignUser': {'id': 1},
  'child_user_ids': [1, 2],
};
final sampleMessages = <Json>[
  {
    'id': 1,
    'type': 3,
    'message_type': 'CHAT_LOG',
    'message_body': 'Conversation assigned to <strong>Agent</strong>.',
    'created_at': '2026-10-29T10:00:00Z',
  },
  {
    'id': 2,
    'type': 2,
    'message_type': 'text',
    'message_body': 'Hello, can you help with my order?',
    'created_at': '2026-10-29T10:00:00Z',
  },
  {
    'id': 3,
    'type': 1,
    'message_type': 'template',
    'message_body': 'order_update',
    'message_body_json': {
      'preview': [
        {'type': 'BODY', 'text': 'Hello Alex, your order is ready.'},
        {'type': 'FOOTER', 'text': 'Thank you for choosing us.'},
        {
          'type': 'BUTTONS',
          'buttons': [
            {'text': 'View order'},
          ],
        },
      ],
    },
    'message_status': 3,
    'created_at': '2026-10-29T10:00:10Z',
  },
  {
    'id': 4,
    'type': 2,
    'message_type': 'interactive',
    'message_body':
        '{"full_name":"Alex","city":"Ahmedabad","flow_token":"hidden"}',
    'created_at': '2026-10-29T10:01:00Z',
  },
  {
    'id': 5,
    'type': 1,
    'message_type': 'text',
    'message_body': 'Thank you! I’ll check that for you.',
    'reaction': [
      {'emoji': '👍'},
    ],
    'message_status': 2,
    'created_at': '2026-10-29T10:01:10Z',
  },
];
void main() {
  test('rich payloads display customer content, never transport JSON or flow tokens', () {
    expect(
      MessageContent(sampleMessages[0]).text,
      'Conversation assigned to Agent.',
    );
    final template = MessageContent(sampleMessages[2]);
    expect(template.text, contains('Hello Alex'));
    expect(template.text, isNot(contains('order_update')));
    expect(template.buttons, ['View order']);
    final form = MessageContent(sampleMessages[3]);
    expect(form.fields['City'], 'Ahmedabad');
    expect(form.fields.keys, isNot(contains('Flow token')));
    final flow = MessageContent({
      'message_type': 'interactiveFlow',
      'message_body_json': {
        'component': {
          'body': {'text': 'Please register'},
          'action': {
            'parameters': {'flow_cta': 'Register', 'flow_token': 'hidden'},
          },
        },
      },
    });
    expect(flow.text, 'Please register');
    expect(flow.buttons, ['Register']);
    expect(
      MessageContent({'message_type': 'text', 'message_body': '{"example":1}'})
          .text,
      '{"example":1}',
    );
    expect(
      MessageContent({
        'message_type': 'interactive',
        'message_body': '{malformed',
      }).text,
      'Interactive message',
    );
  });
  test('service/referral window and all ownership restrictions apply to both send paths', () {
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {})),
      MemoryStore(),
    )..user = {'id': 1};
    final now = DateTime.utc(2026, 10, 29);
    expect(SendPolicy.evaluate(session, null, now: now).canSend, false);
    expect(SendPolicy.evaluate(session, details(), now: now).canSend, true);
    final closed = details(expiry: '2026-10-28T00:00:00Z');
    expect(SendPolicy.evaluate(session, closed, now: now).canSend, false);
    expect(SendPolicy.evaluate(session, closed, now: now).canTemplate, true);
    final referral = details(expiry: '2026-10-28T00:00:00Z');
    object(referral);
    (referral['contact'] as Json)['referral_conversion_expiration_timestamp'] =
        '2026-10-30T00:00:00Z';
    expect(SendPolicy.evaluate(session, referral, now: now).canSend, true);
    for (final restriction in ['is_blocked']) {
      final p = SendPolicy.evaluate(session, {
        ...details(),
        restriction: true,
      }, now: now);
      expect(p.canSend, false);
      expect(p.canTemplate, false);
    }
    for (final change in [
      {'conversation_owner_type': 1},
      {'conversation_status': 0},
      {'assigned_to': 9},
    ]) {
      final d = details();
      d['contact'] = {...object(d['contact']), ...change};
      if (change.containsKey('assigned_to')) d['assignUser'] = {'id': 9};
      final p = SendPolicy.evaluate(session, d, now: now);
      expect(p.canSend, false);
      expect(p.canTemplate, false);
    }
    expect(
      SendPolicy.evaluate(
        session,
        details(),
        ticket: {'assign_user_id': 1, 'status_is_closed': true},
        now: now,
      ).canTemplate,
      false,
    );
    expect(
      SendPolicy.evaluate(
        session,
        details(),
        ticket: {'assign_user_id': 9},
        now: now,
      ).canSend,
      false,
    );
    expect(
      SendPolicy.evaluate(session, {
        ...details(),
        'is_dnd': true,
      }, now: now).canSend,
      true,
    );
    final multi = {
      ...details(),
      'multiple_assignment_enabled': true,
      'assigned_user_ids': [2],
    };
    expect(SendPolicy.evaluate(session, multi, now: now).canSend, true);
    session.dispose();
  });
  testWidgets(
    'closed window removes composer, keeps templates and never posts text',
    (tester) async {
      var sends = 0;
      final api = fakeApi((r, h) {
        if (r.path == 'inbox/send') sends++;
        answer(r, h, switch (r.path) {
          'inbox/getContactDetails' => {
            'success': true,
            'data': details(expiry: '2020-01-01T00:00:00Z'),
          },
          'inbox/messages' => {
            'success': true,
            'data': sampleMessages,
            'meta': {'has_more': false},
          },
          _ => {'success': true, 'data': []},
        });
      });
      final session = MobileSession(api, MemoryStore())..user = {'id': 1};
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
      expect(find.byTooltip('Send message'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Send template'), findsOneWidget);
      expect(find.textContaining('Messaging window closed'), findsOneWidget);
      expect(sends, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
    },
  );
  testWidgets(
    'sending is optimistic before slow API completes and refresh is quiet',
    (tester) async {
      final wait = Completer<void>();
      final api = fakeApi((r, h) async {
        if (r.path == 'inbox/send') {
          await wait.future;
          answer(r, h, {
            'success': true,
            'sent_message': {
              'id': 100,
              'type': 1,
              'message_type': 'text',
              'message_body': 'Instant draft',
              'temp_message_id': r.data['temp_message_id'],
              'created_at': '2099-01-01T10:00:00Z',
            },
          });
          return;
        }
        answer(r, h, switch (r.path) {
          'inbox/getContactDetails' => {'success': true, 'data': details()},
          'inbox/messages' => {
            'success': true,
            'data': sampleMessages,
            'meta': {'has_more': false},
          },
          _ => {'success': true},
        });
      });
      final session = MobileSession(api, MemoryStore())..user = {'id': 1};
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: LiveChat(session, {'id': 12, 'profile_name': 'Alex'}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Instant draft');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.textContaining('Instant draft', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      wait.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Instant draft', findRichText: true),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
    },
  );
  testWidgets('conversation layouts render rich content on Android and iOS', (
    tester,
  ) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final session = MobileSession(
        fakeApi(
          (r, h) => answer(r, h, switch (r.path) {
            'inbox/getContactDetails' => {'success': true, 'data': details()},
            'inbox/messages' => {
              'success': true,
              'data': sampleMessages,
              'meta': {'has_more': false},
            },
            _ => {'success': true},
          }),
        ),
        MemoryStore(),
      )..user = {'id': 1};
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: T.themeFor(platform),
            home: LiveChat(session, {
              'id': 12,
              'profile_name': 'Alex Morgan',
              'wa_id': '919999999999',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('flow_token'), findsNothing);
      await saveReviewImage(
        tester,
        boundary,
        'build/review/live-chat-${platform.name}.png',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
    }
  });

  test('inbound stickers load from the stored path, as the web inbox does', () {
    final row = {
      'message_type': 'sticker',
      'message_body': 'sticker_attached',
      'message_body_json': '{"type":"sticker","media_name":"1.webp","media_path":"storage/9426555485/919724105194/sticker/1.webp","media_mime_type":"image/webp"}',
    };
    expect(
      MessageContent(row).media.single['media_path'],
      contains('sticker/1.webp'),
    );
    expect(
      MessageMedia.fromMessage(
        row,
        'https://chat.example.test/api/mobile/v1/',
      )?.url.toString(),
      'https://chat.example.test/storage/9426555485/919724105194/sticker/1.webp',
    );
  });

  test('voice calls are worded as WhatsApp words them', () {
    String call(Object body, [int? type]) => MessageContent({
      'message_type': 'voice_call',
      'message_body': body,
      'type': ?type,
    }).text;
    expect(call('Start calling...', 1), '📞 Voice call');
    expect(
      call('{"status":"COMPLETED","duration":65,"direction":"USER_INITIATED"}'),
      '📞 Voice call · 1 min 5 secs',
    );
    expect(
      call('{"status":"COMPLETED","duration":0,"direction":"USER_INITIATED"}'),
      '📞 Missed voice call',
    );
    expect(
      call(
        '{"status":"COMPLETED","duration":0,"direction":"BUSINESS_INITIATED"}',
      ),
      '📞 Voice call · No answer',
    );
    expect(call('{"status":"FAILED"}', 1), '📞 Voice call · Failed');
  });

  testWidgets('stickers have no bubble and calls show the call row', (
    tester,
  ) async {
    ApiMessage row(Json json) => ApiMessage({
      'id': json['id'],
      'created_at': '2026-10-30T13:06:03Z',
      ...json,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(
          body: Column(
            children: [
              LiveMessageView(
                message: row({
                  'id': 1,
                  'type': 2,
                  'message_type': 'sticker',
                  'message_body': 'sticker_attached',
                  'message_body_json': '{"type":"sticker","media_path":"storage/1/sticker/a.webp"}',
                }),
                apiBase: 'https://chat.example.test/api/mobile/v1/',
                first: true,
              ),
              LiveMessageView(
                message: row({
                  'id': 2,
                  'type': 2,
                  'message_type': 'voice_call',
                  'message_body': '{"status":"COMPLETED","duration":0,"direction":"USER_INITIATED"}',
                }),
                apiBase: 'https://chat.example.test/api/mobile/v1/',
                first: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(StickerView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StickerView),
        matching: find.byType(MessageBubble),
      ),
      findsNothing,
    );
    expect(find.text('18:36'), findsNWidgets(2));
    expect(find.text('Missed voice call'), findsOneWidget);
    expect(find.byIcon(Icons.call_missed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a call stored twice by a replayed webhook shows once', () {
    Map<String, Object> row(int id) => {
      'id': id,
      'type': 2,
      'message_type': 'voice_call',
      'message_id': 'wacid.SAME',
      'message_body': '{"status":"COMPLETED","duration":0}',
      'created_at': '2026-10-30T13:06:03Z',
    };
    final merged = mergeMessages([], [
      ApiMessage(row(269289)),
      ApiMessage(row(269290)),
    ]);
    expect(merged.map((m) => m.id), ['269290']);
  });
}
