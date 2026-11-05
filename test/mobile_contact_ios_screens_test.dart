import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/contact_actions.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'support/ui.dart';

/// A review image of the contact page as an iPhone draws it: iOS's grouped
/// list in its own system colours, as WhatsApp's contact info.
void main() {
  testWidgets('the iOS contact page renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = fakeApi(
      (r, h) => answer(r, h, switch (r.path) {
        'inbox/getContactDetails' => {
          'success': true,
          'data': {
            'contact': {
              'id': 12,
              'profile_name': 'Rahil',
              'display_wa_id': '+91 97241 05194',
              'conversation_status': 1,
              'is_favourite': 1,
              'service_expiration_timestamp': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 19, minutes: 30))
                  .toIso8601String(),
            },
            'assignUser': {'id': 4, 'name': 'BSNL 485'},
            'can_assign_contact': true,
            'users': [
              {'id': 4, 'name': 'BSNL 485'},
            ],
            'tags': [],
            'notes': [
              {'id': 1, 'note': 'Hello'},
            ],
          },
        },
        _ => {'success': true},
      }),
    );
    final session = MobileSession(api, MemoryStore());
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.iOS),
            home: ContactActionsPage(session, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/contact-ios.png');
    });
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
