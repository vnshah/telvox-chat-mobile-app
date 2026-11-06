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
    // The row shows who it is now, under "Assigned to".
    expect(find.text('Asha'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    // The reason sheet: at most 100 characters, trimmed before sending.
    await tester.enterText(
      find.byType(AppTextFormField).last,
      '  issue resolved ',
    );
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Reopen'), findsOneWidget);
    expect(
      requests.firstWhere((r) => r.path == 'inbox/conversation/close').data,
      {'contact_id': 12, 'reason': 'issue resolved'},
    );

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
    await tester.ensureVisible(find.text('+3 more'));
    await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notes-row')),
      200,
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
    // Flutter's undo history keeps the starting text half a second after
    // the field appears; the page slides in faster than that.
    await tester.pump(const Duration(milliseconds: 600));

    // Undo puts back what was there; Redo brings the edit back.
    await tester.enterText(editor, 'Gate code changed to 5520');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text(long), findsOneWidget);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(find.text('Gate code changed to 5520'), findsOneWidget);

    int notePosts() => requests
        .where((r) => r.method == 'POST' && r.path == 'inbox/notes')
        .length;
    final keep = find.byKey(const ValueKey('leave-keep'));
    final save = find.byKey(const ValueKey('leave-save'));
    final discard = find.byKey(const ValueKey('leave-discard'));

    // Going back with changes asks first, and saves nothing on its own.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsOneWidget);
    expect(notePosts(), 0);
    await tester.tap(keep);
    await tester.pumpAndSettle();
    expect(find.text('Gate code changed to 5520'), findsOneWidget);
    expect(notePosts(), 0);

    // Save: the edit is stored and the list shows it at once.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(save);
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
    // Saving after Done edits that note, not a second one.
    await tester.enterText(editor, 'Sent the quote on Monday');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final posts = requests
        .where((r) => r.method == 'POST' && r.path == 'inbox/notes')
        .toList();
    expect(posts, hasLength(3));
    expect(posts.last.data, containsPair('note_id', 2));
    expect(find.text('Sent the quote on Monday'), findsOneWidget);

    // Discard: the change is dropped and nothing is sent.
    await tester.tap(find.text('Sent the quote on Monday'));
    await tester.pumpAndSettle();
    await tester.enterText(editor, 'Not this');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(discard);
    await tester.pumpAndSettle();
    expect(notePosts(), 3);
    expect(find.text('Sent the quote on Monday'), findsOneWidget);
    expect(find.text('Not this'), findsNothing);

    // An untouched note closes without asking.
    await tester.tap(find.text('Sent the quote on Monday'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsNothing);
    expect(find.byTooltip('Add note'), findsOneWidget);
    expect(notePosts(), 3);

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

  Json fieldsReply() => {
    'success': true,
    'data': {
      'customFields': [
        {'id': 1, 'name': 'City', 'type': '1', 'required': 1},
        {'id': 2, 'name': 'Newsletter', 'type': '13'},
        {'id': 3, 'name': 'Birthday', 'type': '6'},
        {'id': 4, 'name': 'Email', 'type': '9'},
      ],
      'customFieldValues': {
        '2': {'value': '1'},
        '3': {'start_date': '1990-05-04'},
        '4': {'value': 'priya@example.com'},
      },
    },
  };

  Finder fieldText(int id) => find.descendant(
    of: find.byKey(ValueKey('field-$id')),
    matching: find.byType(TextField),
  );

  testWidgets('custom fields save every change together', (tester) async {
    final session = await open(
      tester,
      (s) => ContactFieldsPage(s, 12),
      (r) => r.path == 'inbox/custom-fields' ? fieldsReply() : null,
    );
    expect(find.text('City *'), findsOneWidget);
    expect(find.text('4 May 1990'), findsOneWidget);
    // Nothing changed: no Save or Cancel.
    expect(find.byKey(const ValueKey('fields-save')), findsNothing);

    // Two fields changed, nothing sent yet.
    await tester.enterText(fieldText(1), 'Ahmedabad');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Edited'), findsNWidgets(2));
    expect(find.text('Save 2 changes'), findsOneWidget);
    expect(
      requests.where((r) => r.path == 'inbox/custom-fields/update'),
      isEmpty,
    );

    // One Save sends both.
    await tester.tap(find.byKey(const ValueKey('fields-save')));
    await tester.pumpAndSettle();
    final saved = requests
        .where((r) => r.path == 'inbox/custom-fields/update')
        .map((r) => r.data as Map)
        .toList();
    expect(saved, hasLength(2));
    expect(
      saved.firstWhere((b) => b['custom_field_id'] == 1),
      allOf(
        containsPair('field_type', 'text'),
        containsPair('value', 'Ahmedabad'),
      ),
    );
    expect(
      saved.firstWhere((b) => b['custom_field_id'] == 2),
      allOf(containsPair('field_type', 'select'), containsPair('value', '0')),
    );
    expect(find.text('Saved 2 fields'), findsOneWidget);
    expect(find.byKey(const ValueKey('fields-save')), findsNothing);
    expect(find.text('Edited'), findsNothing);
    expect(find.text('Ahmedabad'), findsOneWidget);
    // The list was not fetched again.
    expect(
      requests.where((r) => r.path == 'inbox/custom-fields'),
      hasLength(1),
    );
    await close(tester, session);
  });

  testWidgets('cancel puts the saved values back without sending', (
    tester,
  ) async {
    final session = await open(
      tester,
      (s) => ContactFieldsPage(s, 12),
      (r) => r.path == 'inbox/custom-fields' ? fieldsReply() : null,
    );
    await tester.enterText(fieldText(4), 'someone@else.com');
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fields-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('priya@example.com'), findsOneWidget);
    expect(find.text('someone@else.com'), findsNothing);
    expect(find.byKey(const ValueKey('fields-save')), findsNothing);

    // Typing the saved value back is not a change.
    await tester.enterText(fieldText(4), 'x');
    await tester.enterText(fieldText(4), 'priya@example.com');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fields-save')), findsNothing);
    expect(
      requests.where((r) => r.path == 'inbox/custom-fields/update'),
      isEmpty,
    );
    await close(tester, session);
  });

  testWidgets('a refused field stays changed and marked', (tester) async {
    final session = await open(
      tester,
      (s) => ContactFieldsPage(s, 12),
      (r) => switch (r.path) {
        'inbox/custom-fields' => fieldsReply(),
        'inbox/custom-fields/update' when r.data['custom_field_id'] == 4 => 422,
        _ => null,
      },
    );
    await tester.enterText(fieldText(1), 'Surat');
    await tester.enterText(fieldText(4), 'new@example.com');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fields-save')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 saved. Check the marked fields.'), findsOneWidget);
    // City saved; Email is still edited, with the server's reason under it.
    expect(find.text('Edited'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('field-4')),
        matching: find.textContaining('Not saved'),
      ),
      findsOneWidget,
    );
    await close(tester, session);
  });

  testWidgets('leaving with unsaved fields asks first', (tester) async {
    final session = await open(
      tester,
      (s) => Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ContactFieldsPage(s, 12)),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      (r) => r.path == 'inbox/custom-fields' ? fieldsReply() : null,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldText(1), 'Pune');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text('You changed a custom field. Save it before leaving?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('leave-discard')));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(
      requests.where((r) => r.path == 'inbox/custom-fields/update'),
      isEmpty,
    );
    await close(tester, session);
  });
}
