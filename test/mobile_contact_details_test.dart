import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/contact_actions.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

Json details({List<Json> tags = const [], List<Json> notes = const []}) => {
  'success': true,
  'data': {
    'contact': {'id': 12, 'profile_name': 'Priya', 'conversation_status': 1},
    'assignUser': null,
    'can_assign_contact': true,
    'users': [
      {'id': 4, 'name': 'Asha'},
    ],
    'tags': tags,
    'notes': notes,
  },
};

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
      final body = reply(r);
      if (body is int) {
        answer(r, h, {'success': false, 'message': 'Not saved'}, body);
        return;
      }
      answer(r, h, body ?? {'success': true});
    });
    final session = MobileSession(api, MemoryStore());
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

  bool doneEnabled() => find
      .ancestor(
        of: find.byIcon(Icons.check_rounded),
        matching: find.byType(IconButton),
      )
      .evaluate()
      .map((e) => (e.widget as IconButton).onPressed != null)
      .first;

  int detailLoads() =>
      requests.where((r) => r.path == 'inbox/getContactDetails').length;

  testWidgets('a change updates its own section, with no page reload', (
    tester,
  ) async {
    final session = await open(
      tester,
      (s) => ContactActionsPage(s, 12),
      (r) => switch (r.path) {
        'inbox/getContactDetails' => details(),
        'inbox/contacts/12/assign' => {
          'success': true,
          'data': {
            'contact': {'id': 12, 'assigned_to': 4},
            'assignUser': {'id': 4, 'name': 'Asha'},
          },
        },
        _ => null,
      },
    );
    // No page-wide progress bar at rest.
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('Assigned to').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choice-4')));
    await tester.pumpAndSettle();
    expect(find.text('Assigned to Asha'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Reopen'), findsOneWidget);
    expect(requests.map((r) => r.path), contains('inbox/conversation/close'));

    // The server's answers were enough: the contact was loaded once.
    expect(detailLoads(), 1);
    await close(tester, session);
  });

  testWidgets('a failed change puts back what was there', (tester) async {
    final session = await open(
      tester,
      (s) => ContactActionsPage(s, 12),
      (r) => switch (r.path) {
        'inbox/getContactDetails' => details(),
        'inbox/contacts/12/favorite' => 500,
        _ => null,
      },
    );
    await tester.tap(find.text('Favourite'));
    await tester.pumpAndSettle();
    expect(find.text('Favourite'), findsOneWidget);
    expect(find.text('Unfavourite'), findsNothing);
    await close(tester, session);
  });

  testWidgets('many tags stay compact until asked for', (tester) async {
    final session = await open(
      tester,
      (s) => ContactActionsPage(s, 12),
      (r) => r.path == 'inbox/getContactDetails'
          ? details(
              tags: [
                for (var i = 1; i <= 9; i++) {'id': i, 'name': 'Tag $i'},
              ],
            )
          : null,
    );
    expect(find.text('Tag 6'), findsOneWidget);
    expect(find.text('Tag 7'), findsNothing);
    await tester.tap(find.text('+3 more'));
    await tester.pumpAndSettle();
    expect(find.text('Tag 9'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    // Removing one shows at once.
    await tester.tap(find.bySemanticsLabel('Remove Tag 2'));
    await tester.pumpAndSettle();
    expect(find.text('Tag 2'), findsNothing);
    expect(requests.map((r) => r.path), contains('inbox/contacts/tag/remove'));
    expect(detailLoads(), 1);
    await close(tester, session);
  });

  testWidgets('notes list as previews and open in a full-screen editor', (
    tester,
  ) async {
    const long =
        'Called about the delivery window. She prefers mornings, and the '
        'gate code is 4417. Follow up on Friday with the revised quote.';
    final first = {
      'id': 1,
      'content': long,
      'user': {'name': 'Asha'},
    };
    var saved = [first];
    final session = await open(
      tester,
      (s) => ContactActionsPage(s, 12),
      (r) => switch ((r.method, r.path)) {
        (_, 'inbox/getContactDetails') => details(notes: [first]),
        ('GET', 'inbox/notes') => {'success': true, 'data': saved},
        ('POST', 'inbox/notes') => {
          'success': true,
          'data': saved = [
            if (r.data['note_id'] == null)
              {
                'id': 2,
                'content': r.data['note'],
                'user': {'name': 'Asha'},
              },
            for (final n in saved)
              n['id'] == r.data['note_id']
                  ? {...n, 'content': r.data['note']}
                  : n,
          ],
        },
        _ => null,
      },
    );
    await tester.ensureVisible(find.byKey(const ValueKey('notes-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-row')));
    await tester.pumpAndSettle();
    // A preview, two lines at most.
    expect(tester.widget<Text>(find.text(long)).maxLines, 2);

    // Tapping a note opens it for editing, keyboard up.
    await tester.tap(find.text(long));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('note-editor'));
    expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
    // Nothing changed yet, so there is nothing for Done to save.
    expect(doneEnabled(), isFalse);

    // Undo puts back what was there; Redo brings the edit back.
    await tester.enterText(editor, 'Gate code changed to 5520');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text(long), findsOneWidget);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(find.text('Gate code changed to 5520'), findsOneWidget);

    // Leaving saves the edit, and the list shows it at once.
    await tester.pageBack();
    await tester.pumpAndSettle();
    final edit = requests.lastWhere(
      (r) => r.path == 'inbox/notes' && r.method == 'POST',
    );
    expect(edit.data, containsPair('note_id', 1));
    expect(find.text('Gate code changed to 5520'), findsOneWidget);

    // A new note: a blank page, saved with Done.
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    expect(find.text('New note'), findsOneWidget);
    expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
    expect(doneEnabled(), isFalse);
    await tester.enterText(editor, 'Sent the quote');
    await tester.pump();
    expect(doneEnabled(), isTrue);
    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(doneEnabled(), isFalse);
    // More typing after Done edits that note, not a second one.
    await tester.enterText(editor, 'Sent the quote on Monday');
    await tester.pageBack();
    await tester.pumpAndSettle();
    final posts = requests
        .where((r) => r.method == 'POST' && r.path == 'inbox/notes')
        .toList();
    expect(posts, hasLength(3));
    expect(posts.last.data, containsPair('note_id', 2));
    expect(find.text('Sent the quote on Monday'), findsOneWidget);

    // An untouched note is not saved again.
    await tester.tap(find.text('Sent the quote on Monday'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      requests.where((r) => r.method == 'POST' && r.path == 'inbox/notes'),
      hasLength(3),
    );

    // Back on the contact, the notes row already counts it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 notes · Sent the quote on Monday'),
      findsOneWidget,
    );
    expect(detailLoads(), 1);
    await close(tester, session);
  });

  testWidgets('custom fields read as a form and save one field in place', (
    tester,
  ) async {
    final session = await open(
      tester,
      (s) => ContactFieldsPage(s, 12),
      (r) => r.path == 'inbox/custom-fields'
          ? {
              'success': true,
              'data': {
                'customFields': [
                  {'id': 1, 'name': 'City', 'type': '1', 'required': 1},
                  {'id': 2, 'name': 'Newsletter', 'type': '13'},
                  {'id': 3, 'name': 'Birthday', 'type': '6'},
                ],
                'customFieldValues': {
                  '2': {'value': '1'},
                  '3': {'start_date': '1990-05-04'},
                },
              },
            }
          : null,
    );
    expect(find.text('City *'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    // A switch reads On, not "1"; a date reads as a date.
    expect(find.text('On'), findsOneWidget);
    expect(find.text('4 May 1990'), findsOneWidget);

    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Ahmedabad');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Ahmedabad'), findsOneWidget);
    final saved = requests.singleWhere(
      (r) => r.path == 'inbox/custom-fields/update',
    );
    expect(saved.data, containsPair('field_type', 'text'));
    expect(saved.data, containsPair('value', 'Ahmedabad'));
    // One field changed; the list was not fetched again.
    expect(
      requests.where((r) => r.path == 'inbox/custom-fields'),
      hasLength(1),
    );
    await close(tester, session);
  });
}
