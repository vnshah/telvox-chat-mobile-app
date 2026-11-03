import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/notes.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'support/ui.dart';

/// Review images of the note screens: the list, a note as read, a note being
/// edited, and the question asked when leaving unsaved changes. Written to build/review/notes-*.png with each build.
void main() {
  testWidgets('note screens render for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    String ago(Duration d) => now.subtract(d).toUtc().toIso8601String();
    const quote =
        'Called about the delivery window. She prefers mornings before 11, '
        'and the gate code is 4417.\n\n'
        'Follow up on Friday with the revised quote for the 40-seat plan. '
        'Finance wants it split across two invoices.';
    var notes = <Json>[
      {
        'id': 3,
        'content': quote,
        'user': {'name': 'Asha Mehta'},
        'created_at': ago(const Duration(minutes: 40)),
      },
      {
        'id': 2,
        'content':
            'Asked for the WhatsApp catalogue link again. Sent it from the '
            'Templates screen; she confirmed it opens.',
        'user': {'name': 'Ravi Patel'},
        'created_at': ago(const Duration(days: 1, hours: 2)),
      },
      {
        'id': 1,
        'content': 'Prefers Gujarati for voice calls.',
        'user': {'name': 'Asha Mehta'},
        'created_at': ago(const Duration(days: 9)),
      },
    ];
    final session = MobileSession(
      fakeApi(
        (r, h) => answer(r, h, {
          'success': true,
          'data': switch (r.method) {
            'POST' => notes = [
              for (final n in notes)
                n['id'] == r.data['note_id']
                    ? {...n, 'content': r.data['note']}
                    : n,
            ],
            _ => notes,
          },
        }),
      ),
      MemoryStore(),
    );
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: NotesPage(session, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/notes-list.png');

      // The note as read: opened with the keyboard put away. Nothing has
      // changed, so Done is off.
      await tester.tap(find.textContaining('Called about the delivery'));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/notes-view.png');

      // Editing: the cursor at the end of a new line, Undo now available.
      final editor = find.byKey(const ValueKey('note-editor'));
      await tester.tap(editor);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(
        editor,
        '$quote\n\nUpdate: she approved the split. Send both invoices Monday.',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/notes-edit.png');

      // Back with unsaved changes asks before anything is saved.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/notes-leave.png');
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    session.dispose();
  });
}
