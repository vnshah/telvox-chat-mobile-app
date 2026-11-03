import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/conversation_search.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_test.dart' show details;

/// A conversation of 150 messages, served as the inbox's endpoints do:
/// the newest page, a page around a message (around_id/around_message_id),
/// pages before/after one, and search.
class History {
  History({this.jumps = true, this.searches = true});
  final bool jumps, searches;
  final requests = <RequestOptions>[];
  late final all = <Json>[
    for (var id = 1; id <= 150; id++)
      {
        'id': id,
        'type': id.isEven ? 2 : 1,
        'message_id': 'wamid.$id',
        'message_type': 'text',
        'message_body': id == 13
            ? 'The refund for order 4417 is approved'
            : id == 148
            ? 'Did the refund go through?'
            : 'Message $id',
        if (id == 148) ...{
          'contextual_reply_id': 'wamid.13',
          'contextual_message': 'The refund for order 4417 is approved',
          'contextual_message_type': 'text',
        },
        'created_at':
            '2026-10-${(1 + id ~/ 10).toString().padLeft(2, '0')}T10:${(id % 60).toString().padLeft(2, '0')}:00Z',
      },
  ];

  Json page(List<Json> data, Json meta) => {
    'success': true,
    'data': data,
    'meta': {
      'oldest_id': data.isEmpty ? null : data.first['id'],
      'newest_id': data.isEmpty ? null : data.last['id'],
      'sync_from': '2026-11-03T10:00:00Z',
      ...meta,
    },
  };

  Object reply(RequestOptions r) {
    final d = (r.data as Map?) ?? {};
    if (r.path == 'inbox/getContactDetails') {
      return {'success': true, 'data': details()};
    }
    if (r.path == 'inbox/messages/search') {
      if (!searches) return 404;
      final q = '${d['q']}'.toLowerCase();
      return {
        'success': true,
        'data': [
          for (final m in all.reversed)
            if ('${m['message_body']}'.toLowerCase().contains(q))
              {
                'id': m['id'],
                'message_id': m['message_id'],
                'type': m['type'],
                'message_type': 'text',
                'created_at': m['created_at'],
                'text': m['message_body'],
                'sender_name': m['type'] == 1 ? 'Asha' : null,
              },
        ],
        'meta': {'has_more': false, 'next_before_id': null},
      };
    }
    if (r.path != 'inbox/messages') return {'success': true};
    final around = d['around_id'] ?? d['around_message_id'];
    if (around != null && jumps) {
      final at = all.indexWhere(
        (m) => m['id'] == around || m['message_id'] == around,
      );
      if (at < 0) return 404;
      final from = (at - 20).clamp(0, all.length), to = (at + 21).clamp(0, all.length);
      return page(all.sublist(from, to), {
        'has_more': from > 0,
        'target_id': all[at]['id'],
        'has_more_before': from > 0,
        'has_more_after': to < all.length,
      });
    }
    if (d['after_id'] != null) {
      final rest = all.where((m) => (m['id'] as int) > (d['after_id'] as int));
      return page(rest.take(50).toList(), {'has_more': rest.length > 50});
    }
    if (d['before_id'] != null) {
      final rest = all
          .where((m) => (m['id'] as int) < (d['before_id'] as int))
          .toList();
      final start = (rest.length - 50).clamp(0, rest.length);
      return page(rest.sublist(start), {'has_more': start > 0});
    }
    if (d['updated_since'] != null) return page([], {'has_more': false});
    return page(all.sublist(100), {'has_more': true});
  }
}

void main() {
  late History server;
  late MobileSession session;

  Future<void> open(WidgetTester tester, [History? history]) async {
    server = history ?? History();
    final api = fakeApi((r, h) {
      server.requests.add(r);
      final body = server.reply(r);
      if (body is int) {
        answer(r, h, {'success': false, 'message': 'Not found'}, body);
      } else {
        answer(r, h, body);
      }
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

  Iterable<Map> asked(String key) => server.requests
      .where((r) => r.path == 'inbox/messages')
      .map((r) => r.data as Map)
      .where((d) => d.containsKey(key));

  Future<void> search(WidgetTester tester, String words) async {
    await tester.tap(find.byTooltip('Search chat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), words);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Finder lit() => find.byWidgetPredicate(
    (w) =>
        w is AnimatedContainer &&
        (w.decoration as BoxDecoration?)?.color != Colors.transparent &&
        w.decoration != null,
  );

  test('found words are marked, whatever their case', () {
    final span = marked('Refund approved; the REFUND is sent', 'refund');
    final parts = span.children!.cast<TextSpan>();
    expect(
      parts.where((p) => p.style != null).map((p) => p.text),
      ['Refund', 'REFUND'],
    );
  });

  testWidgets('search waits for a pause and two letters, then lists matches', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Search chat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'r');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Type at least 2 letters to search this chat.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ref');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'refund');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    // One request for the pause, not one per keystroke.
    final searches = server.requests.where(
      (r) => r.path == 'inbox/messages/search',
    );
    expect(searches, hasLength(1));
    expect((searches.single.data as Map)['q'], 'refund');
    // Newest first, each with who wrote it.
    expect(find.byKey(const ValueKey('search-result-148')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-result-13')), findsOneWidget);
    Finder authorOf(int id) => find.descendant(
      of: find.byKey(ValueKey('search-result-$id')),
      matching: find.byType(Text),
    );
    // The customer by name; an agent by theirs.
    expect(
      tester.widgetList<Text>(authorOf(148)).map((t) => t.data),
      contains('Alex'),
    );
    expect(
      tester.widgetList<Text>(authorOf(13)).map((t) => t.data),
      contains('Asha'),
    );
    await close(tester);
  });

  testWidgets('choosing a match jumps to it, lit, then back to the latest', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('Message 150', findRichText: true), findsOneWidget);
    await search(tester, 'approved');
    await tester.tap(find.byKey(const ValueKey('search-result-13')));
    await tester.pumpAndSettle();

    // The page around it, with the message on screen and lit up.
    expect(asked('around_id').single['around_id'], 13);
    expect(
      find.textContaining('The refund for order 4417', findRichText: true),
      findsWidgets,
    );
    expect(lit(), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(lit(), findsNothing);

    // Jump to latest goes straight back to the newest messages.
    await tester.tap(find.byTooltip('Scroll to latest'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Message 150', findRichText: true), findsOneWidget);
    await close(tester);
  });

  testWidgets('after a jump, reaching the bottom pages newer messages in', (
    tester,
  ) async {
    await open(tester);
    await search(tester, 'approved');
    await tester.tap(find.byKey(const ValueKey('search-result-13')));
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    list.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(asked('after_id').first['after_id'], 33);
    await close(tester);
  });

  testWidgets('tapping a reply quote shows the message it quotes', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(
      find.text('The refund for order 4417 is approved').first,
    );
    await tester.pumpAndSettle();
    // Not loaded yet: fetched by its WhatsApp id.
    expect(asked('around_message_id').single['around_message_id'], 'wamid.13');
    expect(lit(), findsOneWidget);
    await tester.pumpAndSettle();
    await close(tester);
  });

  testWidgets('servers without search or jumping say so, and nothing breaks', (
    tester,
  ) async {
    await open(tester, History(jumps: false, searches: false));
    await search(tester, 'refund');
    expect(find.text('Search is not available on this server yet.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // A quote on an older server: the newest page comes back, not a jump.
    await tester.tap(
      find.text('The refund for order 4417 is approved').first,
    );
    await tester.pumpAndSettle();
    expect(find.text('This server cannot open older messages yet.'), findsOneWidget);
    expect(find.textContaining('Message 150', findRichText: true), findsOneWidget);
    await close(tester);
  });
}
