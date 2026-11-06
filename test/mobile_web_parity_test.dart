import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/assignment.dart';
import 'package:telvox_chat_mobile_app/mobile/contact_actions.dart';
import 'package:telvox_chat_mobile_app/mobile/calls.dart'
    show CallPermission, callPermissionLabel, callPermissionStatus;
import 'package:telvox_chat_mobile_app/mobile/list_filter.dart';
import 'package:telvox_chat_mobile_app/mobile/message_info.dart';
import 'package:telvox_chat_mobile_app/ui/delivery_tick.dart';
import 'package:telvox_chat_mobile_app/mobile/message_notes.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart'
    show messageSource, productCardOf;
import 'package:telvox_chat_mobile_app/mobile/product_send.dart';
import 'package:telvox_chat_mobile_app/mobile/template_plan.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart'
    show ApiMessage, InboxRepository;
import 'package:telvox_chat_mobile_app/mobile/screens.dart'
    show QuickAddContact;
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

/// The contact details the web inbox's panel reads.
Json details({
  Json contact = const {},
  bool bot = false,
  bool multi = false,
  List<Json> tags = const [],
}) => {
  'success': true,
  'data': {
    'contact': {
      'id': 12,
      'profile_name': 'Priya',
      'conversation_status': 1,
      ...contact,
    },
    'assignUser': null,
    'can_assign_contact': true,
    'multiple_assignment_enabled': multi,
    'assigned_user_ids': <int>[],
    'ai_bot_enabled': bot,
    'ai_bot_label': bot ? 'Assign to Maya' : 'Assign to Bot',
    'users': [
      {
        'id': 4,
        'name': 'Asha',
        'role_name': 'Manager',
        'department_name': 'Sales',
      },
      {'id': 5, 'name': 'Ravi', 'role_name': 'Sub user'},
    ],
    'tags': tags,
    'notes': const [],
  },
};

void main() {
  late List<RequestOptions> requests;

  Future<MobileSession> open(
    WidgetTester tester,
    Object? Function(RequestOptions) reply,
  ) async {
    requests = [];
    final api = fakeApi((r, h) {
      requests.add(r);
      answer(r, h, reply(r) ?? {'success': true});
    });
    final session = MobileSession(api, MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: ContactActionsPage(session, 12),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> close(WidgetTester tester, MobileSession session) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  }

  group('assigning, as the web assign dropdown offers it', () {
    test('agents carry their role and department; no plain Unassigned', () {
      final plan = Assignment(object(details()['data']));
      expect(plan.options.map((o) => o['name']), ['Asha', 'Ravi']);
      expect(plan.options.first['detail'], 'Manager - Sales');
      // No department: no second line, as on the web.
      expect(plan.options.last.containsKey('detail'), isFalse);
      expect(plan.available, isTrue);
    });

    test('the bot is offered only when a bot can take the chat', () {
      final plan = Assignment(
        object(
          details(bot: true, contact: {'conversation_owner_type': 1})['data'],
        ),
      );
      expect(plan.options.first, {
        'id': Assignment.bot,
        'name': 'Assign to Maya',
      });
      expect(plan.value, Assignment.bot);
      // Choosing it clears the assignment; the server hands it to the bot.
      expect(plan.body(Assignment.bot), {'user_id': null});
      expect(plan.body(4), {'user_id': 4});
    });

    test('several agents: the bot clears them all, take over adds me', () {
      final data = object(details(bot: true, multi: true)['data'])
        ..['assigned_user_ids'] = [5];
      final plan = Assignment(data);
      expect(plan.body([Assignment.bot, 4]), {'user_ids': <int>[]});
      expect(plan.body([4, 5]), {
        'user_ids': [4, 5],
      });
      expect(plan.takeOverBody(9), {
        'user_ids': [5, 9],
      });
      expect(plan.takeOverBody(5), {
        'user_ids': [5],
      });
      expect(Assignment(object(details()['data'])).takeOverBody(9), {
        'user_id': 9,
      });
    });

    test('no one to offer and no bot: nothing to assign', () {
      final data = object(details()['data'])..['users'] = [];
      expect(Assignment(data).available, isFalse);
    });

    testWidgets('the picker shows the bot label and departments', (
      tester,
    ) async {
      final session = await open(
        tester,
        (r) => switch (r.path) {
          'inbox/getContactDetails' => details(bot: true),
          'inbox/contacts/12/assign' => {
            'success': true,
            'data': {
              'contact': {'id': 12, 'conversation_owner_type': 1},
              'assignUser': null,
            },
          },
          _ => null,
        },
      );
      await tester.tap(find.text('Assigned to').first);
      await tester.pumpAndSettle();
      expect(find.text('Manager - Sales'), findsOneWidget);
      await tester.tap(find.text('Assign to Maya'));
      await tester.pumpAndSettle();
      expect(
        requests.firstWhere((r) => r.path == 'inbox/contacts/12/assign').data,
        {'user_id': null},
      );
      // The bot owns it now, as the web button reads.
      expect(find.text('Bot'), findsOneWidget);
      await close(tester, session);
    });
  });

  testWidgets('a search with no match adds that name as a tag, at once', (
    tester,
  ) async {
    var made = false;
    final session = await open(
      tester,
      (r) => switch (r.path) {
        'inbox/getContactDetails' => details(
          tags: [
            {'id': 1, 'name': 'Lead'},
          ],
        ),
        'inbox/tags' => {
          'success': true,
          'data': [
            {'id': 3, 'name': 'VIP'},
            if (made) {'id': 8, 'name': 'Wholesale'},
          ],
        },
        'inbox/tags/add' => () {
          made = true;
          return {'success': true, 'message': 'Tag added successfully'};
        }(),
        _ => null,
      },
    );
    await tester.ensureVisible(find.text('Add tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();

    // A tag that exists is found, and no new one is offered for it.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('tag-search')),
        matching: find.byType(EditableText),
      ),
      'vip',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('choice-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-create')), findsNothing);
    // Nor for one already on the contact.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('tag-search')),
        matching: find.byType(EditableText),
      ),
      'Lead',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('tag-create')), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('tag-search')),
        matching: find.byType(EditableText),
      ),
      ' Wholesale ',
    );
    await tester.pump();
    expect(
      find.text('Add new tag "Wholesale"', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tag-create')));
    await tester.pumpAndSettle();
    expect(requests.firstWhere((r) => r.path == 'inbox/tags/add').data, {
      'name': 'Wholesale',
    });
    // Made and put on the contact, with nothing typed twice.
    expect(
      requests.firstWhere((r) => r.path == 'inbox/contacts/tag/add').data,
      {'contact_id': 12, 'tag_id': 8},
    );
    expect(find.byKey(const ValueKey('tag-search')), findsNothing);
    expect(find.text('Wholesale'), findsOneWidget);
    await close(tester, session);
  });

  testWidgets('a new tag name is at most 30 characters', (tester) async {
    final session = await open(
      tester,
      (r) => switch (r.path) {
        'inbox/getContactDetails' => details(),
        'inbox/tags' => {'success': true, 'data': <Json>[]},
        _ => null,
      },
    );
    await tester.ensureVisible(find.text('Add tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
    expect(find.text('No tags yet. Type a name to add one.'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('tag-search')),
        matching: find.byType(EditableText),
      ),
      'Wholesale buyers from the north zone',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tag-create')));
    await tester.pump();
    expect(find.text('Tag name must be 30 characters or less'), findsOneWidget);
    expect(requests.where((r) => r.path == 'inbox/tags/add'), isEmpty);
    await close(tester, session);
  });

  testWidgets('marketing opt-in is its own switch, beside DND', (tester) async {
    final session = await open(
      tester,
      (r) => switch (r.path) {
        'inbox/getContactDetails' => details(contact: {'marketing_otp': 0}),
        _ => null,
      },
    );
    final row = find.byKey(const ValueKey('marketing-opt-in'));
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
      requests.firstWhere((r) => r.path == 'inbox/contacts/12/profile').data,
      {'marketing_otp': 1},
    );
    final toggle = tester.widget<Switch>(
      find.descendant(of: row, matching: find.byType(Switch)),
    );
    expect(toggle.value, isTrue);
    await close(tester, session);
  });

  group('a message kept as a note, as the web copies it', () {
    ApiMessage message(String type, Object? body, {String text = ''}) =>
        ApiMessage({
          'id': 1,
          'type': 2,
          'message_id': 'wamid.A',
          'message_type': type,
          'message_body': text,
          'message_body_json': body,
        });

    test('text, interactive and template bodies', () {
      expect(
        noteText(
          message('text', {
            'text': {'body': ' Hello there '},
          }),
        ),
        'Hello there',
      );
      expect(
        noteText(
          message('interactiveWithButton', {
            'component': {
              'body': {'text': 'Pick a slot'},
            },
          }),
        ),
        'Pick a slot',
      );
      expect(
        noteText(
          message('template', {
            'preview': [
              {'type': 'HEADER', 'text': 'Hi'},
              {'type': 'BODY', 'text': 'Your order shipped'},
            ],
          }),
        ),
        'Your order shipped',
      );
    });

    test('media, voice notes and stickers cannot be kept', () {
      expect(supportsNote(message('text', null, text: 'Hi')), isTrue);
      for (final type in ['image', 'audio', 'sticker', 'document']) {
        expect(supportsNote(message(type, null)), isFalse);
      }
    });

    test('a message knows its note by its WhatsApp id', () {
      final m = message('text', null, text: 'Hi');
      expect(
        noteFor(m, [
          {'id': 1, 'message_id': null},
        ]),
        isNull,
      );
      expect(
        noteFor(m, [
          {'id': 2, 'message_id': 'wamid.A'},
        ])?['id'],
        2,
      );
    });
  });

  test('a profile picture is shown only from a web address', () {
    expect(
      profilePicture('https://pps.whatsapp.net/v/a.jpg'),
      'https://pps.whatsapp.net/v/a.jpg',
    );
    expect(profilePicture(null), isNull);
    expect(profilePicture(''), isNull);
    expect(profilePicture('storage/a.jpg'), isNull);
  });

  group('the list filter, as the web popover sends it', () {
    test('any of the tags and one assignee go with the list request', () async {
      final sent = <Object?>[];
      final api = fakeApi((r, h) {
        sent.add(r.data);
        answer(r, h, {'success': true, 'data': <Json>[]});
      });
      final repo = InboxRepository(api);
      await repo.contacts(filter: 'all');
      await repo.contacts(filter: 'all', tags: [3, 7], assignedTo: 12);
      expect(object(sent.first).containsKey('tags'), isFalse);
      expect(object(sent.last)['tags'], [3, 7]);
      expect(object(sent.last)['assignedTo'], 12);
    });

    test('a filter is on while it has a tag or an assignee', () {
      expect(const ListFilter().active, isFalse);
      expect(
        const ListFilter(tags: [7, 3]).key,
        const ListFilter(tags: [3, 7]).key,
      );
      expect(const ListFilter(assignedTo: 4).active, isTrue);
    });
  });

  group('a new contact, as the web popover takes it', () {
    Future<MobileSession> sheet(WidgetTester tester) async {
      requests = [];
      final api = fakeApi((r, h) {
        requests.add(r);
        answer(r, h, switch (r.path) {
          'inbox/getCountries' => {
            'success': true,
            'default_code': '65',
            'data': [
              {
                'id': 1,
                'code': '91',
                'name': 'India',
                'flag': '🇮🇳',
                'alpha2Code': 'IN',
              },
              {
                'id': 2,
                'code': '65',
                'name': 'Singapore',
                'flag': '🇸🇬',
                'alpha2Code': 'SG',
              },
            ],
          },
          _ => {
            'success': true,
            'data': {'id': 40},
          },
        });
      });
      final session = MobileSession(api, MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: Scaffold(body: QuickAddContact(session)),
        ),
      );
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('opens on the number\'s country and checks the phone', (
      tester,
    ) async {
      final session = await sheet(tester);
      expect(find.text('🇸🇬 +65'), findsOneWidget);
      final fields = find.byType(AppTextFormField);
      await tester.enterText(fields.first, 'Mei');
      await tester.enterText(fields.last, '81234');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        find.text('Phone number must be at least 8 characters long'),
        findsOneWidget,
      );
      await tester.enterText(fields.last, '8123-4567');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        find.text('Phone number must contain only digits'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('country-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('country-IN')));
      await tester.pumpAndSettle();
      await tester.enterText(fields.last, '98110 00099');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(requests.firstWhere((r) => r.path == 'inbox/contact/new').data, {
        'name': 'Mei',
        'phone': '9811000099',
        'country': '91',
      });
      await close(tester, session);
    });
  });

  group('who sent it, as the web marks outgoing messages', () {
    ApiMessage sent(Json extra) =>
        ApiMessage({'id': 1, 'type': 1, 'message_type': 'text', ...extra});
    test('broadcast, automation, chatbot and API sends are marked', () {
      expect(messageSource(sent({'message_source': 1})), 1);
      expect(messageSource(sent({'message_source': '4'})), 4);
      expect(messageSource(sent({'message_source': 0})), 0);
    });
    test('an AI-written message gets no other mark; customers none', () {
      expect(messageSource(sent({'message_source': 3, 'sent_by_ai': 1})), 0);
      expect(
        messageSource(ApiMessage({'id': 2, 'type': 2, 'message_source': 1})),
        0,
      );
    });
  });

  group('product cards, as the web draws them', () {
    ApiMessage product(String type, Json body) => ApiMessage({
      'id': 1,
      'type': 1,
      'message_type': type,
      'message_body_json': body,
    });
    test('a single product, a list and an order', () {
      final single = productCardOf(
        product('interactiveSingleProduct', {
          'product': {'name': 'Blue mug', 'price': '499', 'image_url': ''},
        }),
      )!;
      expect(single.title, 'Blue mug');
      expect(single.button, 'View');
      final list = productCardOf(
        product('interactiveMultipleProduct', {
          'component': {
            'header': {'text': 'Our picks'},
          },
          'products': [
            {'name': 'A'},
            {'name': 'B'},
          ],
        }),
      )!;
      expect((list.title, list.subtitle), ('Our picks', '2 Items'));
      final order = productCardOf(
        product('order', {'total_items': 3, 'estimated_total': '1,497.00'}),
      )!;
      expect(order.subtitle, '₹1,497.00 (estimated total)');
      expect(order.button, isNull);
    });
    test('without the server\'s product details, no card', () {
      expect(
        productCardOf(product('interactiveSingleProduct', {'component': {}})),
        isNull,
      );
    });
  });

  group('tracked links in a template, as the web fills them', () {
    TemplatePlan plan() => TemplatePlan(
      {
        'category': 'MARKETING',
        'rowdata': [
          {
            'type': 'BODY',
            'text': 'Hi {{1}}, see {{2}}',
            'tracked_link_variables': {'2': 21},
          },
          {
            'type': 'BUTTONS',
            'buttons': [
              {
                'type': 'URL',
                'text': 'Shop',
                'url': 'https://t.example/{{1}}',
                'tracked_link_id': 17,
              },
            ],
          },
        ],
      },
      trackedLinks: [
        {'id': 17, 'name': 'Spring sale'},
        {'id': 18, 'name': 'Winter sale'},
      ],
    );

    test('nothing to type for a tracked link; typed values stay in order', () {
      final p = plan();
      expect(p.inputs.map((i) => i.key), [
        'body.0',
        'tracked.body.2',
        'tracked.button',
      ]);
      expect(p.requirements, ['body_text']);
      final v = p.variables({...p.defaults, 'body.0': 'Asha'});
      expect(v, {
        'bodyText': ['Asha'],
      });
    });

    test('a link the agent changes is sent; the template\'s own is not', () {
      final p = plan();
      final v = p.variables({
        ...p.defaults,
        'body.0': 'Asha',
        'tracked.button': '18',
        'tracked.body.2': '17',
      });
      expect(v['tracked_link_id'], '18');
      expect(v['tracked_body_links'], {'2': '17'});
    });
  });

  testWidgets('a product list goes out as the web sends it', (tester) async {
    requests = [];
    final api = fakeApi((r, h) {
      requests.add(r);
      answer(r, h, switch (r.path) {
        'inbox/get-catalogues' => {
          'success': true,
          'catalogues': [
            {
              'id': 3,
              'name': 'Main',
              'fb_catalogue_id': '900',
              'product_count': 2,
            },
          ],
        },
        _ => {
          'success': true,
          'products': [
            {'id': 12, 'name': 'Blue mug', 'price': '499'},
            {'id': 15, 'name': 'Red mug', 'price': '499'},
          ],
        },
      });
    });
    final session = MobileSession(api, MemoryStore());
    Json? sent;
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => sent = await Navigator.push<Json>(
              context,
              MaterialPageRoute(builder: (_) => ProductSendPage(session)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Main (2 Products)'), findsOneWidget);
    expect(
      requests
          .firstWhere((r) => r.path == 'inbox/get-products')
          .queryParameters,
      {'catalogue_id': 3},
    );
    await tester.tap(find.text('Multiple Products'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-15')));
    await tester.tap(find.byKey(const ValueKey('product-12')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('product-body')),
      'Our picks for you',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('product-send')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('product-send')));
    await tester.pump();
    // WhatsApp needs a header on a list.
    expect(find.text('Please enter a header'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('product-header')),
      'Mugs',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('product-send')));
    await tester.pumpAndSettle();
    expect(sent, {
      'message_type': 'multiple_product',
      'body': 'Our picks for you',
      'catalog_id': '900',
      'multipleProduct': '12,15',
      'header': 'Mugs',
      'footer': null,
    });
    await close(tester, session);
  });

  group('call permission, as the contact records it', () {
    test('permanent, temporary, expired, declined or not given', () {
      expect(
        callPermissionStatus({
          'call_permission': 'accept',
          'call_permission_permanent': 1,
        }).state,
        CallPermission.permanent,
      );
      expect(
        callPermissionLabel({
          'call_permission': 'accept',
          'call_permission_permanent': true,
        }),
        'Allowed permanently',
      );
      final later = DateTime.now().add(const Duration(days: 3));
      expect(
        callPermissionStatus({
          'call_permission': 'accept',
          'call_permission_expiration': later.toIso8601String(),
        }).state,
        CallPermission.temporary,
      );
      expect(
        callPermissionStatus({
          'call_permission': 'accept',
          'call_permission_expiration': '2020-01-01T00:00:00Z',
        }).state,
        CallPermission.expired,
      );
      expect(
        callPermissionStatus({'call_permission': 'reject'}).state,
        CallPermission.declined,
      );
      expect(callPermissionLabel(const {}), 'Not given yet');
    });
  });

  testWidgets('the web inbox\'s delivery marks, each its own', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (final s in const [0, 1, 2, 3, 4, 5]) DeliveryTick(s),
          ],
        ),
      ),
    );
    for (final s in [0, 1, 2, 3, 4, 5]) {
      expect(find.byKey(ValueKey('tick-$s')), findsOneWidget);
    }
    expect(DeliveryTick.label(3), 'Read');
    expect(DeliveryTick.label(4), 'Not delivered');
  });

  testWidgets('message info shows the receipts and the message\'s details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessageInfoPage(
          ApiMessage({
            'id': 1,
            'type': 1,
            'message_id': 'wamid.HBg1',
            'message_type': 'text',
            'message_body': 'Your order ships today',
            'message_status': 3,
            'message_source': 1,
            'sender_name': 'Asha',
            'sent_at': '2026-11-06 10:00:00',
            'delivered_at': '2026-11-06 10:00:05',
            'read_at': '2026-11-06 10:02:00',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The message, as in the chat.
    expect(
      find.textContaining('Your order ships today', findRichText: true),
      findsWidgets,
    );
    for (final key in ['info-read', 'info-delivered', 'info-sent']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('Read'), findsWidgets);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('by a broadcast'), findsOneWidget);
    expect(find.text('wamid.HBg1'), findsOneWidget);
  });
}
