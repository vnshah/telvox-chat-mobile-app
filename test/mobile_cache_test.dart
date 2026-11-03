import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/conversation_sync.dart';
import 'package:telvox_chat_mobile_app/mobile/list_sync.dart';
import 'package:telvox_chat_mobile_app/mobile/local_cache.dart';
import 'package:telvox_chat_mobile_app/mobile/screens.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_test.dart' show details;
import 'mobile_realtime_test.dart' show FakeSocket, realtimeConfig;

Json row(int id, String at, {int unread = 0, int status = 1}) => {
  'id': id,
  'profile_name': 'Contact $id',
  'last_message_date': at,
  'unread_message_count': unread,
  'conversation_status': status,
};

List<int> ids(List<Json> rows) => [for (final r in rows) r['id'] as int];

void main() {
  group('ListSync', () {
    const sync = ListSync.contacts;
    final list = [
      row(1, '2026-10-31 10:00:00'),
      row(2, '2026-10-31 09:00:00'),
      row(3, '2026-10-31 08:00:00'),
    ];

    test('a live event moves only that row, to the top', () {
      final next = sync.patch(list, {
        'id': 3,
        'last_message_date': '2026-10-31 11:00:00',
        'unread_message_count': 2,
        // Not an activity field: the event never overwrites it.
        'wa_id': '919999999999',
      })!;
      expect(ids(next), [3, 1, 2]);
      expect(next.first['unread_message_count'], 2);
      expect(next.first.containsKey('wa_id'), false);
    });

    test('a row leaves a tab it no longer matches', () {
      expect(ids(sync.patch(list, {'id': 1, 'conversation_status': 0})!), [
        2,
        3,
      ]);
      final unread = [row(1, '2026-10-31 10:00:00', unread: 1)];
      expect(
        sync.patch(unread, {
          'id': 1,
          'unread_message_count': 0,
        }, filter: 'unread'),
        isEmpty,
      );
    });

    test('a conversation the list does not show is left to the server', () {
      expect(sync.patch(list, {'id': 9}), isNull);
    });

    test('the first page is the truth for its window only', () {
      final local = [...list, row(4, '2026-10-30 08:00:00')];
      // Server: 5 is new, 2 left this tab, 1 and 3 are unchanged.
      final page = [
        row(5, '2026-10-31 12:00:00'),
        row(1, '2026-10-31 10:00:00'),
        row(3, '2026-10-31 08:00:00'),
      ];
      expect(ids(sync.reconcile(local, page, complete: false)), [5, 1, 3, 4]);
      expect(ids(sync.reconcile(local, page, complete: true)), [5, 1, 3]);
    });

    test('an open chat moves its row only forward, across date formats', () {
      // The list sends "Y-m-d H:i:s"; messages send ISO-8601 instants.
      final rows = [
        row(1, '2026-10-31 10:00:00'),
        row(2, '2026-10-31 09:00:00', unread: 3),
      ];
      final newer = sync.follow(rows, {
        'id': 2,
        'last_message': {'message_body': 'Bot reply'},
        'last_message_date': '2099-01-01T00:00:00Z',
        'unread_message_count': 0,
      })!;
      expect(ids(newer), [2, 1]);
      expect(newer.first['unread_message_count'], 0);
      expect(
        sync.follow(rows, {
          'id': 1,
          'last_message_date': '2000-01-01T00:00:00Z',
        }),
        isNull,
      );
      expect(sync.follow(rows, {'id': 9, 'last_message_date': 'x'}), isNull);
    });

    test('load more never shows a row twice', () {
      expect(ids(sync.append(list, [row(3, 'x'), row(6, 'y')])), [1, 2, 3, 6]);
    });
  });

  group('MemoryLocalCache', () {
    test(
      'upserts by id, keeps the newest messages, and replaces on demand',
      () async {
        final cache = MemoryLocalCache();
        await cache.open('a');
        await cache.putMessages(
          'c',
          [
            {
              'id': 1,
              'created_at': '2026-10-31T10:00:00Z',
              'message_status': 1,
            },
          ],
          {'sync': 's1'},
        );
        await cache.putMessages(
          'c',
          [
            {
              'id': 1,
              'created_at': '2026-10-31T10:00:00Z',
              'message_status': 3,
            },
            {'id': 2, 'created_at': '2026-10-31T10:01:00Z'},
          ],
          {'sync': 's2'},
        );
        var saved = (await cache.conversation('c'))!;
        expect(saved.messages.map((m) => m['id']), [1, 2]);
        expect(saved.messages.first['message_status'], 3);
        expect(saved.cursor['sync'], 's2');

        await cache.putMessages(
          'c',
          [
            {'id': 7, 'created_at': '2026-10-31T11:00:00Z'},
          ],
          {},
          replace: true,
        );
        saved = (await cache.conversation('c'))!;
        expect(saved.messages.map((m) => m['id']), [7]);
      },
    );

    test('another account never sees the previous one', () async {
      final cache = MemoryLocalCache();
      await cache.open('server#1');
      await cache.putList('list', [row(1, 'x')]);
      await cache.open('server#1');
      expect(await cache.list('list'), isNotNull);
      await cache.open('server#2');
      expect(await cache.list('list'), isNull);
    });
  });

  testWidgets('a chat opens from the phone, then checks its newest page', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final held = <RequestInterceptorHandler>[];
    final api = fakeApi((r, h) {
      if (r.path == 'inbox/messages') {
        requests.add(r);
        held.add(h);
        return;
      }
      answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {'success': true, 'data': details()},
        _ => {'success': true},
      });
    })..wabaId = 7;
    final cache = MemoryLocalCache();
    await cache.open('owner');
    await cache.putMessages(
      'chat:7:12:null',
      [
        {
          'id': 40,
          'type': 2,
          'message_type': 'text',
          'message_body': 'Kept from last time',
          'created_at': '2026-10-31T09:00:00Z',
        },
      ],
      {
        'sync': '2026-10-31T09:30:00Z',
        'more': true,
        'synced_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      },
    );
    final session = MobileSession(api, MemoryStore(), cache: cache)
      ..user = {'id': 1};
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
    await tester.pump();
    await tester.pump();
    // On screen before the server has answered.
    expect(
      find.textContaining('Kept from last time', findRichText: true),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    // The newest page in full, not only changes since the saved cursor: a
    // copy missing messages is repaired, not carried forward.
    final ask = object(requests.single.data);
    expect(ask.containsKey('updated_since'), false);
    expect(ask.containsKey('before_id'), false);

    answer(requests.single, held.single, {
      'success': true,
      'data': [
        {
          'id': 41,
          'type': 2,
          'message_type': 'text',
          'message_body': 'New while away',
          'created_at': '2026-10-31T10:00:00Z',
        },
      ],
      'meta': {'has_more': false, 'sync_from': '2026-10-31T10:05:00Z'},
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Kept from last time', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('New while away', findRichText: true),
      findsOneWidget,
    );
    // The inbox row follows the chat's newest message.
    expect(session.conversationActivity.value?['id'], 12);
    expect(
      object(
        session.conversationActivity.value?['last_message'],
      )['message_body'],
      'New while away',
    );
    final saved = (await cache.conversation('chat:7:12:null'))!;
    expect(saved.messages.map((m) => m['id']), [40, 41]);
    expect(saved.cursor['sync'], '2026-10-31T10:05:00Z');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });

  testWidgets('the inbox opens from the phone and a live event moves one row', (
    tester,
  ) async {
    final socket = FakeSocket();
    var listRequests = 0;
    var server = [row(2, '2026-10-31 11:00:00'), row(1, '2026-10-31 10:00:00')];
    final api = fakeApi((r, h) {
      if (r.path.endsWith('broadcasting/auth')) {
        return answer(r, h, {'auth': 'app-key:signature'});
      }
      if (r.path == 'inbox/contacts') listRequests++;
      answer(r, h, switch (r.path) {
        'inbox/contacts' => server,
        _ => {'success': true, 'data': <dynamic>[]},
      });
    })..wabaId = 7;
    final cache = MemoryLocalCache();
    await cache.open('owner');
    await cache.putList('list:7:contacts:all:', [
      row(1, '2026-10-31 10:00:00'),
      row(2, '2026-10-31 09:00:00'),
    ]);
    final session =
        MobileSession(
            api,
            MemoryStore(),
            cache: cache,
            realtimeConnector: (_) async => socket,
          )
          ..user = {'id': 1}
          ..config = realtimeConfig;
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(body: LiveList(session, kind: 0)),
      ),
    );
    await tester.pump();
    // The kept list renders first, in its kept order.
    expect(
      tester.getTopLeft(find.text('Contact 1')).dy,
      lessThan(tester.getTopLeft(find.text('Contact 2')).dy),
    );
    session.realtime.start();
    await tester.pumpAndSettle();
    socket.established();
    await tester.pumpAndSettle();
    // The background refresh brought the server's order.
    expect(
      tester.getTopLeft(find.text('Contact 2')).dy,
      lessThan(tester.getTopLeft(find.text('Contact 1')).dy),
    );

    server = [
      row(1, '2026-10-31 12:00:00', unread: 1),
      row(2, '2026-10-31 11:00:00'),
    ];
    final before = listRequests;
    socket.server('inbox.user.list.update', {
      'contact': {
        'id': 1,
        'last_message_date': '2026-10-31 12:00:00',
        'unread_message_count': 1,
      },
    }, channel: 'private-inbox.user.list.update.7.919426555485');
    await tester.pump();
    await tester.pump();
    // Moved at once, before any request.
    expect(listRequests, before);
    expect(
      tester.getTopLeft(find.text('Contact 1')).dy,
      lessThan(tester.getTopLeft(find.text('Contact 2')).dy),
    );
    // The new-message count shows on the row, as on WhatsApp.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('unread-1')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(listRequests, before + 1);

    // A second message raises the count on the same row.
    server = [
      row(1, '2026-10-31 12:05:00', unread: 2),
      row(2, '2026-10-31 11:00:00'),
    ];
    socket.server('inbox.user.list.update', {
      'contact': {
        'id': 1,
        'last_message_date': '2026-10-31 12:05:00',
        'unread_message_count': 2,
      },
    }, channel: 'private-inbox.user.list.update.7.919426555485');
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('unread-1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(ids((await cache.list('list:7:contacts:all:'))!), [1, 2]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.realtime.stop();
    await tester.pump();
    session.dispose();
  });

  testWidgets('a saved chat missing the bot\'s messages is repaired on open', (
    tester,
  ) async {
    // As the phone had it: the customer's messages, none of the bot's.
    Json row(int id, int type, String body, String at) => {
      'id': id,
      'type': type,
      'message_type': 'text',
      'message_body': body,
      'message_id': 'wamid.$id',
      'created_at': '2026-08-06 $at',
    };
    final server = [
      row(267742, 2, 'Hi', '15:49:28'),
      row(267743, 1, 'Register for Amrutanjali', '15:49:28'),
      row(267744, 2, 'Restart', '15:50:54'),
      row(267749, 1, 'Thank you for contacting us.', '15:51:09'),
    ];
    final requests = <Json>[];
    final api = fakeApi((r, h) {
      if (r.path == 'inbox/messages') requests.add(object(r.data));
      answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {'success': true, 'data': details()},
        'inbox/messages' => {
          'success': true,
          'data': server,
          'meta': {
            'has_more': false,
            'oldest_id': 267742,
            'sync_from': '2026-11-03T10:00:00Z',
          },
        },
        _ => {'success': true},
      });
    })..wabaId = 7;
    final cache = MemoryLocalCache();
    await cache.open('owner');
    await cache.putMessages(
      'chat:7:12:null',
      [
        // Older than the page: kept.
        row(267700, 2, 'Not needed', '11:28:00'),
        server[0],
        server[2],
      ],
      {
        'sync': '2026-11-03T09:00:00Z',
        'synced_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      },
    );
    final session = MobileSession(api, MemoryStore(), cache: cache)
      ..user = {'id': 1};
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: LiveChat(session, {
          'id': 12,
          'profile_name': 'Ravin',
          'wa_id': '919099801380',
        }),
      ),
    );
    await tester.pumpAndSettle();
    for (final text in [
      'Not needed',
      'Hi',
      'Register for Amrutanjali',
      'Restart',
      'Thank you for contacting us.',
    ]) {
      expect(
        find.textContaining(text, findRichText: true),
        findsOneWidget,
        reason: text,
      );
    }
    // And the copy is saved whole, so the next open starts right.
    final saved = (await cache.conversation('chat:7:12:null'))!;
    expect(saved.messages.map((m) => m['id']), [
      267700,
      267742,
      267743,
      267744,
      267749,
    ]);
    expect(saved.cursor['sync'], '2026-11-03T10:00:00Z');
    // Later live updates go back to asking only for changes.
    expect(requests.first.containsKey('updated_since'), false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });

  test('copies saved by an older build are dropped once', () async {
    final cache = MemoryLocalCache();
    // As the previous build named it: server and user only.
    await cache.open('https://chat.telvox.dev/api/mobile/v1/#1');
    await cache.putMessages(
      'chat:7:12:null',
      [
        {'id': 40, 'created_at': '2026-08-06 15:49:28'},
      ],
      {'sync': '2026-11-03T09:00:00Z'},
    );
    await cache.open(cacheOwner('https://chat.telvox.dev/api/mobile/v1/', 1));
    expect(await cache.conversation('chat:7:12:null'), isNull);
    // From then on the same owner keeps what it saved.
    await cache.putMessages('chat:7:12:null', [
      {'id': 41, 'created_at': '2026-08-06 15:50:00'},
    ], {});
    await cache.open(cacheOwner('https://chat.telvox.dev/api/mobile/v1/', 1));
    expect(await cache.conversation('chat:7:12:null'), isNotNull);
  });

  group('chats are synced onto the phone before they are opened', () {
    late List<Json> asked;
    late MobileSession session;
    late MemoryLocalCache cache;

    Json row(int id, String body) => {
      'id': id,
      'type': 2,
      'message_type': 'text',
      'message_body': body,
      'created_at': '2026-11-03T10:0$id:00Z',
    };

    Future<void> start() async {
      asked = [];
      cache = MemoryLocalCache();
      await cache.open('owner');
      final api = fakeApi((r, h) {
        if (r.path == 'inbox/messages') asked.add(object(r.data));
        answer(r, h, {
          'success': true,
          'data': [row(1, 'Synced in the background')],
          'meta': {'has_more': false, 'sync_from': '2026-11-03T10:10:00Z'},
        });
      })..wabaId = 7;
      api.token = 'token';
      session = MobileSession(api, MemoryStore(), cache: cache)
        ..user = {'id': 1};
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    test(
      'a chat that moved since its last sync is fetched and saved',
      () async {
        await start();
        final synced = DateTime.now().toUtc().subtract(
          const Duration(hours: 24),
        );
        await cache.putMessages(
          ConversationSync.keyFor(7, 12),
          [row(0, 'Old')],
          {'synced_at': synced.toIso8601String()},
        );
        await cache.putMessages(
          ConversationSync.keyFor(7, 13),
          [row(0, 'Old')],
          {'synced_at': DateTime.now().toUtc().toIso8601String()},
        );
        await session.conversations.prefetch([
          // Moved after the phone's copy: fetched.
          {
            'id': 12,
            'last_message_date': DateTime.now().toUtc().toIso8601String(),
          },
          // Nothing new since: left alone.
          {'id': 13, 'last_message_date': synced.toIso8601String()},
        ]);
        await settle();
        expect(asked.map((a) => a['contact_id']), [12]);
        final saved = (await cache.conversation(
          ConversationSync.keyFor(7, 12),
        ))!;
        expect(
          saved.messages.map((m) => m['message_body']),
          contains('Synced in the background'),
        );
        expect(saved.cursor['sync'], '2026-11-03T10:10:00Z');
        session.dispose();
      },
    );

    test(
      'not the chat on screen, not twice in a row, not every unopened one',
      () async {
        await start();
        session.visibleContacts.add('contact:20');
        await session.conversations.prefetch([
          for (var id = 20; id < 30; id++)
            {'id': id, 'last_message_date': '2026-11-03 10:00:00'},
        ]);
        await settle();
        // The open chat is skipped; of the rest only the first five new ones.
        expect(asked.map((a) => a['contact_id']), [21, 22, 23, 24, 25]);
        await session.conversations.prefetch([
          {'id': 21, 'last_message_date': '2026-11-03 10:00:00'},
        ]);
        await settle();
        expect(asked, hasLength(5));
        session.dispose();
      },
    );

    test('a push brings its chat up to date at once', () async {
      await start();
      session.conversations.pushed(31);
      await settle();
      expect(asked.single['contact_id'], 31);
      session.dispose();
    });
  });

  group('one request catches up every chat that moved', () {
    late List<RequestOptions> requests;
    late MobileSession session;
    late MemoryLocalCache cache;
    var syncAnswers = 0;

    Future<void> start({bool serverHasSync = true}) async {
      requests = [];
      syncAnswers = 0;
      cache = MemoryLocalCache();
      await cache.open('owner');
      final api = fakeApi((r, h) {
        requests.add(r);
        if (r.path == 'inbox/sync') {
          if (!serverHasSync) {
            return answer(r, h, {'success': false, 'message': 'Not found'}, 404);
          }
          syncAnswers++;
          return answer(r, h, {
            'success': true,
            'data': {
              'messages': [
                {
                  'id': 101,
                  'contact_master_id': 12,
                  'type': 2,
                  'message_body': 'While you were away',
                  'created_at': '2026-11-03T09:00:00Z',
                },
              ],
              'changes': [
                {'id': 1, 'contact_master_id': 13, 'message_status': 3},
              ],
            },
            'meta': {'has_more': false, 'sync_from': '2026-11-03T10:00:00Z'},
          });
        }
        answer(r, h, {
          'success': true,
          'data': <Json>[],
          'meta': {'has_more': false, 'sync_from': '2026-11-03T10:00:00Z'},
        });
      })..wabaId = 7;
      api.token = 'token';
      session = MobileSession(api, MemoryStore(), cache: cache)
        ..user = {'id': 1};
      final yesterday = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 24))
          .toIso8601String();
      for (final id in [12, 13]) {
        await cache.putMessages(ConversationSync.keyFor(7, id), [
          {
            'id': 1,
            'type': 1,
            'message_body': 'Sent yesterday',
            'message_status': 1,
            'created_at': '2026-11-02T09:00:00Z',
          },
        ], {'sync': yesterday, 'synced_at': yesterday});
      }
    }

    tearDown(() => ConversationSync.accountSyncMissing = false);

    final moved = [
      for (final id in [12, 13])
        {'id': id, 'last_message_date': DateTime.now().toUtc().toIso8601String()},
    ];

    test('new messages saved whole, ticks patched, in one request', () async {
      await start();
      await session.conversations.prefetch(moved);
      expect(requests.where((r) => r.path == 'inbox/sync'), hasLength(1));
      expect(requests.where((r) => r.path == 'inbox/messages'), isEmpty);
      final twelve = (await cache.conversation(ConversationSync.keyFor(7, 12)))!;
      expect(
        twelve.messages.map((m) => m['message_body']),
        contains('While you were away'),
      );
      expect(twelve.cursor['sync'], '2026-11-03T10:00:00Z');
      final thirteen = (await cache.conversation(ConversationSync.keyFor(7, 13)))!;
      expect(thirteen.messages.single['message_status'], 3);
      expect(thirteen.messages.single['message_body'], 'Sent yesterday');
      session.dispose();
    });

    test('an older server without it: chat by chat, as before', () async {
      await start(serverHasSync: false);
      await session.conversations.prefetch(moved);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        requests.where((r) => r.path == 'inbox/messages').map((r) => object(r.data)['contact_id']),
        [12, 13],
      );
      expect(ConversationSync.accountSyncMissing, isTrue);
      session.dispose();
    });

    test('a message carried in a push is saved with no request', () async {
      await start();
      await session.conversations.arrived({
        'type': 'message',
        'waba_user_id': '7',
        'contact_id': '12',
        'message': jsonEncode({
          'id': 102,
          'type': 2,
          'message_body': 'Pushed',
          'created_at': '2026-11-03T10:01:00Z',
        }),
      });
      expect(requests, isEmpty);
      final twelve = (await cache.conversation(ConversationSync.keyFor(7, 12)))!;
      expect(twelve.messages.map((m) => m['message_body']), contains('Pushed'));
      // Its cursor is untouched: the chat still asks for anything else.
      expect(twelve.cursor['sync'], isNot('2026-11-03T10:00:00Z'));
      // A chat the phone has no copy of is fetched instead.
      await session.conversations.arrived({
        'type': 'message',
        'waba_user_id': '7',
        'contact_id': '99',
        'message': jsonEncode({'id': 1}),
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests.single.path, 'inbox/messages');
      expect(syncAnswers, 0);
      session.dispose();
    });
  });
}
