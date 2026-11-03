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

  testWidgets('notes open as a list of previews, then in full', (tester) async {
    const long =
        'Called about the delivery window. She prefers mornings, and the '
        'gate code is 4417. Follow up on Friday with the revised quote.';
    final saved = [
      {
        'id': 2,
        'content': 'Sent the quote',
        'user': {'name': 'Asha'},
      },
      {
        'id': 1,
        'content': long,
        'user': {'name': 'Asha'},
      },
    ];
    final session = await open(
      tester,
      (s) => ContactActionsPage(s, 12),
      (r) => switch ((r.method, r.path)) {
        (_, 'inbox/getContactDetails') => details(notes: [saved[1]]),
        ('GET', 'inbox/notes') => {
          'success': true,
          'data': [saved[1]],
        },
        ('POST', 'inbox/notes') => {'success': true, 'data': saved},
        _ => null,
      },
    );
    await tester.ensureVisible(find.byKey(const ValueKey('notes-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-row')));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsWidgets);
    // A preview, two lines at most.
    final preview = tester.widget<Text>(find.text(long));
    expect(preview.maxLines, 2);

    await tester.tap(find.text(long));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Adding a note: a tall box whose text starts at the top.
    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    final box = tester.widget<TextField>(find.byType(TextField));
    expect(box.minLines, greaterThanOrEqualTo(6));
    expect(box.textAlignVertical, TextAlignVertical.top);
    expect(box.decoration?.hintText, contains('note'));
    await tester.enterText(find.byType(TextField), 'Sent the quote');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Sent the quote'), findsOneWidget);

    // Back on the contact, the notes row already counts it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('2 notes · Sent the quote'), findsOneWidget);
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
