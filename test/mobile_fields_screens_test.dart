import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/contact_actions.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'support/ui.dart';

/// Review images of the custom fields form, as saved and with unsaved
/// changes waiting on Save or Cancel. Written to build/review/fields-*.png.
void main() {
  testWidgets('custom fields form renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = MobileSession(
      fakeApi(
        (r, h) => answer(r, h, {
          'success': true,
          'data': {
            'customFields': [
              {'id': 1, 'name': 'City', 'type': '1', 'required': 1},
              {
                'id': 2,
                'name': 'Plan',
                'type': '12',
                'option_value': 'Starter,Growth,Enterprise',
              },
              {'id': 3, 'name': 'Newsletter', 'type': '13'},
              {'id': 4, 'name': 'Birthday', 'type': '6'},
              {'id': 5, 'name': 'Contract', 'type': '7'},
              {'id': 6, 'name': 'Email', 'type': '9'},
              {'id': 7, 'name': 'Notes for delivery', 'type': '2'},
            ],
            'customFieldValues': {
              '1': {'value': 'Surat'},
              '2': {'value': 'Growth'},
              '3': {'value': '1'},
              '4': {'start_date': '1990-05-04'},
              '5': {'start_date': '2026-01-01', 'end_date': '2026-12-31'},
              '6': {'value': 'priya@example.com'},
            },
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
            home: ContactFieldsPage(session, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/fields-saved.png');

      Finder text(int id) => find.descendant(
        of: find.byKey(ValueKey('field-$id')),
        matching: find.byType(TextField),
      );
      await tester.enterText(text(1), 'Ahmedabad');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/fields-edited.png');
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    session.dispose();
  });
}
