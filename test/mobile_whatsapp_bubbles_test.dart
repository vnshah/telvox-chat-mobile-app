import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

/// Messages drawn as WhatsApp draws them: a template's buttons with their
/// icons and its footer small and grey, a form response as a card, and a
/// long press selecting the message with the top bar turned into actions.
/// The message's words, drawn with its time beside them.
Finder shop() => find.textContaining('Where is your shop?', findRichText: true);

void main() {
  late List<RequestOptions> requests;
  late MobileSession session;
  final now = DateTime.now().toUtc().toIso8601String();

  final question = {
    'id': 1,
    'type': 2,
    'message_id': 'wamid.question',
    'message_type': 'text',
    'message_body': 'Where is your shop?',
    'created_at': now,
  };
  final template = {
    'id': 2,
    'type': 1,
    'message_id': 'wamid.template',
    'message_type': 'template',
    'message_body': 'opt_in',
    'message_body_json': jsonEncode({
      'preview': [
        {
          'type': 'HEADER',
          'image': {'link': 'https://chat.example.test/storage/7/diyas.jpg'},
        },
        {'type': 'BODY', 'text': 'Hi Rahil, thanks for confirming opt-in!'},
        {
          'type': 'FOOTER',
          'text': 'Send STOP to stop receiving these messages',
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
  };
  final form = {
    'id': 3,
    'type': 2,
    'message_id': 'wamid.form',
    'message_type': 'interactive',
    'message_body_json': jsonEncode({
      'interactive': {
        'type': 'nfm_reply',
        'nfm_reply': {
          'name': 'flow',
          'response_json': jsonEncode({
            'full_name': 'Ravin',
            'email_address': 'ravin@example.test',
            'flow_token': 'secret',
          }),
        },
      },
    }),
    'created_at': now,
  };

  Future<void> chat(WidgetTester tester, List<Json> rows) async {
    requests = [];
    final api = fakeApi((r, h) {
      requests.add(r);
      answer(r, h, switch (r.path) {
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
      });
    });
    session = MobileSession(api, MemoryStore())..user = {'id': 1};
    api
      ..token = 'test'
      ..wabaId = 7;
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: LiveChat(session, {
          'id': 2,
          'wa_id': '919999999999',
          'profile_name': 'Rahil',
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

  testWidgets('a template: icons on its buttons, a grey footer, a full photo', (
    tester,
  ) async {
    await chat(tester, [template]);
    expect(
      find.text('Hi Rahil, thanks for confirming opt-in!'),
      findsOneWidget,
    );
    // Quick reply ↩ and link ⧉, as WhatsApp marks them.
    expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    // The footer is its own small grey line, not part of the body.
    final footer = tester.widget<Text>(
      find.byKey(const ValueKey('message-footer')),
    );
    expect(footer.data, 'Send STOP to stop receiving these messages');
    expect(footer.style!.color, T.muted);
    expect(footer.style!.fontSize, lessThan(15));
    // The header photo fills the bubble's width.
    final photo = tester.getSize(find.byKey(const ValueKey('header-media')));
    expect(photo.width, 412 * .82 - 6);
    await close(tester);
  });

  testWidgets('a form response is a card; View response opens the answers', (
    tester,
  ) async {
    await chat(tester, [form]);
    expect(find.byKey(const ValueKey('form-response-card')), findsOneWidget);
    expect(find.text('Response received'), findsOneWidget);
    // The answers are not spread through the chat any more.
    expect(find.text('Full name: Ravin'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('view-form-response')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('form-response-sheet'));
    expect(
      find.descendant(of: sheet, matching: find.text('Full name')),
      findsOneWidget,
    );
    expect(find.descendant(of: sheet, matching: find.text('Ravin')), findsOne);
    // A form's own token is never shown.
    expect(find.text('secret'), findsNothing);
    await close(tester);
  });

  testWidgets('a long press selects the message, as WhatsApp does', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await chat(tester, [question]);
    await tester.longPress(shop());
    await tester.pumpAndSettle();

    // The top bar turns into the message's actions.
    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-reply')), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-copy')), findsOneWidget);
    // Info is for your own sent messages.
    expect(find.byKey(const ValueKey('selection-info')), findsNothing);
    // Its reactions float above it.
    expect(find.byKey(const ValueKey('message-reaction-picker')), findsOne);

    await tester.tap(find.byKey(const ValueKey('selection-copy')));
    await tester.pumpAndSettle();
    expect(copied, 'Where is your shop?');
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);

    // A reaction is sent, and the selection lets go.
    await tester.longPress(shop());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('React with 👍'));
    await tester.pumpAndSettle();
    final reaction = requests.lastWhere((r) => r.path == 'inbox/reactions');
    expect(reaction.method, 'POST');
    expect(reaction.data['emoji'], '👍');
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    await close(tester);
  });

  testWidgets('back, × or a second tap lets the selection go', (tester) async {
    await chat(tester, [question]);
    await tester.longPress(shop());
    await tester.pumpAndSettle();
    // Back: the selection goes, the chat stays.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    expect(shop(), findsOneWidget);

    await tester.longPress(shop());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);

    await tester.longPress(shop());
    await tester.pumpAndSettle();
    await tester.tap(shop());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);

    // Reply from the selection puts the message in the composer's quote.
    await tester.longPress(shop());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-reply')));
    await tester.pumpAndSettle();
    expect(shop(), findsAtLeastNWidgets(2));
    await close(tester);
  });
}
