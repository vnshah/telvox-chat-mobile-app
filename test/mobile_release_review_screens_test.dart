import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/canned_responses.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart' show TicketNoteBubble;
import 'package:telvox_chat_mobile_app/mobile/composer.dart';
import 'package:telvox_chat_mobile_app/mobile/contact_actions.dart'
    show TagPickerSheet;
import 'package:telvox_chat_mobile_app/mobile/list_filter.dart';
import 'package:telvox_chat_mobile_app/mobile/message_info.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart'
    show ProductCard, productCardOf;
import 'package:telvox_chat_mobile_app/mobile/models.dart' show ApiMessage;
import 'package:telvox_chat_mobile_app/mobile/split_ticket.dart';
import 'package:telvox_chat_mobile_app/mobile/tickets.dart'
    show DispositionSheet;
import 'package:telvox_chat_mobile_app/ui/chat_message.dart';
import 'package:telvox_chat_mobile_app/ui/data.dart' show Message;
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'support/ui.dart';

/// Review images of the screens a release changed, on an Android phone's
/// width: build/review/release-*.png.
void main() {
  late MobileSession session;

  setUp(() {
    session = MobileSession(
      fakeApi(
        (r, h) => answer(r, h, switch (r.path) {
          'inbox/ticket_tags' => {
            'success': true,
            'data': [
              {'id': 1, 'name': 'VIP'},
              {'id': 2, 'name': 'Refund'},
              {'id': 3, 'name': 'Savanna_Fibre'},
            ],
          },
          'inbox/ticket_metadata' => {
            'success': true,
            'data': {
              'statuses': [
                {'id': 1, 'name': 'Open'},
                {'id': 2, 'name': 'Pending'},
                {'id': 3, 'name': 'Closed'},
              ],
              'priorities': [
                {'id': 1, 'name': 'Low'},
                {'id': 2, 'name': 'High'},
              ],
            },
          },
          'inbox/users' => [
            {'id': 4, 'name': 'Asha'},
            {'id': 5, 'name': 'Ravi'},
          ],
          'inbox/ticket_create_metadata' => {
            'success': true,
            'data': {
              'departments': [
                {'id': 3, 'name': 'Billing'},
              ],
              'statuses': [
                {'id': 1, 'name': 'Open'},
              ],
              'priorities': [
                {'id': 2, 'name': 'High'},
              ],
              'users': [
                {'id': 4, 'name': 'Asha'},
              ],
              'defaults': {
                'department_id': 3,
                'status_id': 1,
                'priority_id': null,
                'assign_user_id': 4,
              },
            },
          },
          _ => {'success': true, 'data': <Json>[]},
        }),
      ),
      MemoryStore(),
    );
  });
  tearDown(() => session.dispose());

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget Function(BuildContext) open, {
    bool sheet = true,
    String? tap,
    Future<void> Function()? then,
  }) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Builder(
              builder: (context) => sheet
                  ? Scaffold(
                      backgroundColor: const Color(0xFFEFE7DE),
                      body: Center(
                        child: TextButton(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: open,
                          ),
                          child: const Text('open'),
                        ),
                      ),
                    )
                  : open(context),
            ),
          ),
        ),
      );
      if (sheet || tap != null) {
        await tester.tap(find.text(tap ?? 'open'));
      }
      await tester.pumpAndSettle();
      if (then != null) {
        await then();
        await tester.pumpAndSettle();
      }
      await saveReviewImage(tester, boundary, 'build/review/release-$name.png');
    });
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('ticks, origin marks, failed mark and a product card', (
    tester,
  ) async {
    final product = productCardOf(
      ApiMessage({
        'id': 1,
        'type': 1,
        'message_type': 'interactiveSingleProduct',
        'message_body_json': {
          'product': {'name': 'Fibre 100 Mbps plan', 'price': '₹799'},
        },
      }),
    )!;
    await shot(
      tester,
      'chat-marks',
      (_) => Scaffold(
        appBar: AppBar(title: const Text('Ravin')),
        backgroundColor: const Color(0xFFEFE7DE),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final (text, status, source, reason) in [
              ('Sending…', 0, 0, null),
              ('Sent', 1, 0, null),
              ('Delivered', 2, 0, null),
              ('Read', 3, 0, null),
              ('From a broadcast', 3, 1, null),
              ('From an automation', 2, 2, null),
              ('Failed — tap the red mark for why', 4, 0, 'Refused'),
              ('Blocked by WhatsApp', 5, 0, 'Blocked'),
            ])
              Align(
                alignment: Alignment.centerRight,
                child: MessageBubble(
                  message: Message(
                    text,
                    out: true,
                    time: '16:20',
                    deliveryStatus: status,
                    source: source,
                    failedReason: reason,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: MessageBubble(
                message: const Message(
                  'Our best plan for you',
                  out: true,
                  time: '16:21',
                  deliveryStatus: 3,
                ),
                maxWidth: 271,
                contentBefore: ProductCard(product),
                footer: const BubbleButtons([
                  (Icons.storefront_outlined, 'View'),
                ]),
              ),
            ),
          ],
        ),
      ),
      sheet: false,
    );
  });

  testWidgets('message info', (tester) async {
    await shot(
      tester,
      'message-info',
      (_) => MessageInfoPage(
        ApiMessage({
          'id': 1,
          'type': 1,
          'message_id': 'wamid.HBgMOTE5MDk5ODAxMzgwFQIAERgS',
          'message_type': 'text',
          'message_body': 'Your order ships today',
          'message_status': 3,
          'message_source': 0,
          'sender_name': 'Renav Business',
          'created_at': '2026-11-06T10:00:00Z',
          'sent_at': '2026-11-06T10:00:01Z',
          'delivered_at': '2026-11-06T10:00:05Z',
          'read_at': '2026-11-06T10:02:00Z',
        }),
      ),
      sheet: false,
    );
  });

  testWidgets('attach sheet with Product and Call permission', (tester) async {
    await shot(
      tester,
      'attach',
      (context) => Scaffold(
        backgroundColor: const Color(0xFFEFE7DE),
        body: Center(
          child: TextButton(
            onPressed: () => showAttachSheet(
              context,
              templates: true,
              products: true,
              callPermission: true,
            ),
            child: const Text('attach'),
          ),
        ),
      ),
      sheet: false,
      tap: 'attach',
    );
  });

  testWidgets('ticket filter', (tester) async {
    await shot(
      tester,
      'ticket-filter',
      (_) => ListFilterSheet(
        session: session,
        initial: const ListFilter(status: 2, ticketType: 'overdue', tags: [1]),
        tickets: true,
      ),
    );
  });

  testWidgets('tag search with Add new tag', (tester) async {
    await shot(
      tester,
      'tag-picker',
      (_) => TagPickerSheet(
        load: () async => [
          {'id': 1, 'name': 'VIP'},
          {'id': 2, 'name': 'Wholesale'},
        ],
        attach: (_) async => null,
        create: (_) async => null,
      ),
      then: () => tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('tag-search')),
          matching: find.byType(EditableText),
        ),
        'Fibre lead',
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposition on close', (tester) async {
    await shot(
      tester,
      'disposition',
      (_) => DispositionSheet(
        categories: const [
          {
            'id': 1,
            'name': 'Sales',
            'dispositions': [
              {'id': 4, 'name': 'Converted'},
              {'id': 5, 'name': 'Lost'},
              {'id': 6, 'name': 'Follow up'},
            ],
          },
          {
            'id': 2,
            'name': 'Support',
            'dispositions': [
              {'id': 7, 'name': 'Resolved'},
            ],
          },
        ],
        initial: 4,
        save: (_) async => null,
      ),
    );
  });

  testWidgets('split ticket', (tester) async {
    await shot(
      tester,
      'split-ticket',
      (_) => SplitTicketPage(session, 7, const [101, 102]),
      sheet: false,
    );
  });

  testWidgets('quick replies', (tester) async {
    await shot(
      tester,
      'quick-replies',
      (_) => CannedResponseSheet(
        session: session,
        data: const {
          'uncategorised': [
            {
              'id': 9,
              'title': 'Greeting',
              'shortcut': '/hi',
              'body': 'Hello {{customer_name}}, how can we help?',
            },
          ],
          'categories': [
            {
              'id': 1,
              'name': 'Billing',
              'responses': [
                {
                  'id': 5,
                  'title': 'Refund',
                  'shortcut': '/refund',
                  'body': 'Your refund for {{ticket_number}} is on its way.',
                },
              ],
            },
          ],
        },
      ),
    );
  });

  testWidgets('internal note in a ticket chat', (tester) async {
    await shot(
      tester,
      'ticket-note',
      (_) => Scaffold(
        backgroundColor: const Color(0xFFEFE7DE),
        body: Center(
          child: TicketNoteBubble(
            {
              'id': 1,
              'content': 'Customer asked for a call back after 5 pm.',
              'created_at': DateTime.now()
                  .subtract(const Duration(minutes: 12))
                  .toUtc()
                  .toIso8601String(),
              'author': {'name': 'Asha'},
            },
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
      sheet: false,
    );
  });
}
