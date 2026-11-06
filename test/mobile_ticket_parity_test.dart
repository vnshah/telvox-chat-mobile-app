import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/canned_responses.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart' show TicketNoteBubble;
import 'package:telvox_chat_mobile_app/mobile/conversation_window.dart';
import 'package:telvox_chat_mobile_app/mobile/list_filter.dart';
import 'package:telvox_chat_mobile_app/mobile/split_ticket.dart';
import 'package:telvox_chat_mobile_app/mobile/tickets.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

/// The ticket inbox, as the web ticket inbox behaves.
void main() {
  late List<RequestOptions> requests;

  Future<MobileSession> open(
    WidgetTester tester,
    Widget Function(MobileSession) page,
    Object? Function(RequestOptions) reply,
  ) async {
    requests = [];
    final api = fakeApi((r, h) {
      requests.add(r);
      answer(r, h, reply(r) ?? {'success': true});
    });
    final session = MobileSession(api, MemoryStore())..user = {'id': 1};
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: page(session),
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

  test('the session timer counts the window down, then says it closed', () {
    final now = DateTime.utc(2026, 11, 6, 10);
    expect(
      sessionTimerLabel(
        now.add(const Duration(hours: 71, minutes: 59, seconds: 58)),
        now,
      ),
      '71:59:58',
    );
    expect(
      sessionTimerLabel(now.add(const Duration(seconds: 5)), now),
      '00:00:05',
    );
    expect(sessionTimerLabel(now, now), 'Session Closed');
    expect(sessionTimerLabel(null, now), 'Session Closed');
  });

  test('a canned response is filled as the web fills it', () {
    expect(
      fillCannedResponse(
        'Hi {{customer_name}}, ticket {{ticket_number}} is with '
        '{{agent_name}} in {{department}}. {{unknown}}',
        customerName: 'Priya',
        ticketNumber: 'TKT1762',
        agentName: 'Asha',
        department: 'Billing',
      ),
      'Hi Priya, ticket TKT1762 is with Asha in Billing. {{unknown}}',
    );
  });

  test('the ticket filter sends what the web sends', () {
    const f = ListFilter(
      status: 5,
      priority: 2,
      ticketType: 'overdue',
      tags: [3],
      assignedTo: 12,
    );
    expect(f.body, {
      'tags': [3],
      'assignedTo': 12,
      'status': 5,
      'priority': 2,
      'ticketType': 'overdue',
    });
    expect(const ListFilter(ticketType: 'reopened').active, isTrue);
    expect(ticketTypes.keys, [
      'reopened',
      'overdue',
      'waiting_customer',
      'first_response_pending',
    ]);
  });

  test('a note says how long ago, as the web does', () {
    final now = DateTime.utc(2026, 11, 6, 12);
    expect(TicketNoteBubble.ago('2026-11-06T11:59:40Z', now), 'just now');
    expect(TicketNoteBubble.ago('2026-11-06T11:55:00Z', now), '5m ago');
    expect(TicketNoteBubble.ago('2026-11-06T09:00:00Z', now), '3h ago');
    expect(TicketNoteBubble.ago('2026-11-04T12:00:00Z', now), '2d ago');
  });

  /// A ticket assigned to this agent (id 1).
  Json details({bool closed = false, Object? disposition}) => {
    'success': true,
    'data': {
      'ticket': {
        'id': 7,
        'ticket_number': 'TKT1762345678',
        'subject': 'Refund',
        'status_id': closed ? 2 : 1,
        'status_is_closed': closed ? 1 : 0,
        'closed_at': closed ? '2026-11-06T10:00:00Z' : null,
        'assign_user_id': 1,
        'disposition_id': disposition,
      },
      'contact': {'id': 5, 'profile_name': 'Priya'},
      'users': [
        {'id': 1, 'name': 'Me'},
      ],
      'ticket_notes': <Json>[],
      'ticket_tags': <Json>[],
    },
  };

  const dispositions = {
    'success': true,
    'data': [
      {
        'id': 1,
        'name': 'Sales',
        'dispositions': [
          {'id': 4, 'name': 'Converted'},
          {'id': 5, 'name': 'Lost'},
        ],
      },
      {
        'id': 2,
        'name': 'Support',
        'dispositions': [
          {'id': 6, 'name': 'Resolved'},
        ],
      },
    ],
  };

  testWidgets('closing a ticket offers only the web\'s statuses, then asks '
      'what came of it', (tester) async {
    var closed = false;
    final session = await open(
      tester,
      (s) => TicketPage(s, 7),
      (r) => switch (r.path) {
        'inbox/ticket_details' => details(closed: closed),
        'inbox/ticket_metadata' => {
          'success': true,
          'data': {
            'statuses': [
              {'id': 1, 'name': 'Open', 'is_closed': 0, 'is_reopen': 0},
              {'id': 2, 'name': 'Closed', 'is_closed': 1, 'is_reopen': 0},
              {'id': 3, 'name': 'Reopened', 'is_closed': 0, 'is_reopen': 1},
            ],
            'priorities': <Json>[],
          },
        },
        'inbox/tickets/7/status' => () {
          closed = true;
          return {'success': true};
        }(),
        'inbox/tickets/7/dispositions' => dispositions,
        _ => null,
      },
    );
    expect(find.text('#TKT1762345678'), findsOneWidget);
    await tester.tap(find.text('Status').first);
    await tester.pumpAndSettle();
    // An open ticket is not "reopened".
    expect(find.byKey(const ValueKey('choice-3')), findsNothing);
    // The web asks without a ticket, so statuses are not cut by department.
    expect(
      requests
          .firstWhere((r) => r.path == 'inbox/ticket_metadata')
          .queryParameters,
      isEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('choice-2')));
    await tester.pumpAndSettle();

    expect(find.text('Select disposition'), findsOneWidget);
    // Save waits for a pick; another tab starts with nothing picked.
    await tester.tap(find.byKey(const ValueKey('disposition-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('disposition-tab-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('disposition-6')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('disposition-save')));
    await tester.pumpAndSettle();
    expect(
      requests.firstWhere((r) => r.path == 'inbox/tickets/7/disposition').data,
      {'disposition_id': 6},
    );
    expect(find.text('Select disposition'), findsNothing);
    await close(tester, session);
  });

  testWidgets('a closed ticket without a disposition asks for one on opening', (
    tester,
  ) async {
    final session = await open(
      tester,
      (s) => TicketPage(s, 7),
      (r) => switch (r.path) {
        'inbox/ticket_details' => details(closed: true),
        'inbox/tickets/7/dispositions' => dispositions,
        _ => null,
      },
    );
    expect(find.text('Select disposition'), findsOneWidget);
    await close(tester, session);
  });

  testWidgets('with no dispositions set up, nothing is asked', (tester) async {
    final session = await open(
      tester,
      (s) => TicketPage(s, 7),
      (r) => switch (r.path) {
        'inbox/ticket_details' => details(closed: true),
        'inbox/tickets/7/dispositions' => {'success': true, 'data': <Json>[]},
        _ => null,
      },
    );
    expect(find.text('Select disposition'), findsNothing);
    await close(tester, session);
  });

  testWidgets('a split starts on the settings\' defaults and sends the picks', (
    tester,
  ) async {
    Json? made;
    final session = await open(
      tester,
      (s) => Builder(
        builder: (context) => TextButton(
          onPressed: () async => made = await Navigator.push<Json>(
            context,
            MaterialPageRoute(
              builder: (_) => SplitTicketPage(s, 7, [101, 102]),
            ),
          ),
          child: const Text('split'),
        ),
      ),
      (r) => switch (r.path) {
        'inbox/ticket_create_metadata' => {
          'success': true,
          'data': {
            'departments': [
              {'id': 3, 'name': 'Billing'},
            ],
            'statuses': [
              {'id': 1, 'name': 'Open'},
            ],
            'priorities': <Json>[],
            'users': [
              {'id': 1, 'name': 'Me'},
            ],
            'defaults': {
              'department_id': 3,
              'status_id': 1,
              'priority_id': null,
              'assign_user_id': 1,
            },
          },
        },
        'inbox/tickets/7/split' => {
          'success': true,
          'data': {
            'new_ticket': {'id': 9, 'ticket_number': 'TKT99'},
          },
        },
        _ => null,
      },
    );
    await tester.tap(find.text('split'));
    await tester.pumpAndSettle();
    expect(
      find.text('2 messages will be copied to a new ticket'),
      findsOneWidget,
    );
    expect(find.text('Status (default from settings)'), findsOneWidget);
    // Priority has nothing to offer, so it is not shown.
    expect(find.byKey(const ValueKey('split-priority_id')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('split-subject')),
      ' Second issue ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('split-submit')));
    await tester.pumpAndSettle();
    expect(requests.firstWhere((r) => r.path == 'inbox/tickets/7/split').data, {
      'message_ids': [101, 102],
      'subject': 'Second issue',
      'department_id': 3,
      'status_id': 1,
      'priority_id': null,
      'assign_user_id': 1,
    });
    expect(made?['ticket_number'], 'TKT99');
    await close(tester, session);
  });

  testWidgets('quick replies come in tabs, with shortcuts, and search', (
    tester,
  ) async {
    String? picked;
    final session = await open(
      tester,
      (s) => Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (_) => CannedResponseSheet(
              session: s,
              data: {
                'uncategorised': [
                  {
                    'id': 9,
                    'title': 'Greeting',
                    'shortcut': '/hi',
                    'body': 'Hello {{customer_name}}',
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
                        'body': 'Refund on its way',
                      },
                    ],
                  },
                ],
              },
            ),
          ),
          child: const Text('open'),
        ),
      ),
      (r) => switch (r.path) {
        'inbox/canned-responses/search' => {
          'success': true,
          'data': [
            {
              'id': 5,
              'title': 'Refund',
              'shortcut': '/refund',
              'body': 'Refund on its way',
            },
          ],
        },
        _ => null,
      },
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('General (1)'), findsOneWidget);
    expect(find.text('/hi'), findsOneWidget);
    await tester.tap(find.text('Billing (1)'));
    await tester.pump();
    expect(find.text('Refund'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('canned-search')),
        matching: find.byType(EditableText),
      ),
      '/ref',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      requests
          .firstWhere((r) => r.path == 'inbox/canned-responses/search')
          .queryParameters,
      {'q': '/ref'},
    );
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(picked, 'Refund on its way');
    await close(tester, session);
  });
}
