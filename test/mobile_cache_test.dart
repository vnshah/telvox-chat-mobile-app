import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
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

  testWidgets('a chat opens from the phone and asks only for what changed', (
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
        'synced_at': DateTime.now().toUtc().toIso8601String(),
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
    final ask = object(requests.single.data);
    expect(ask['updated_since'], '2026-10-31T09:30:00Z');
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
}
