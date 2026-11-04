import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/account_menu.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;
import 'support/ui.dart';

/// Review images of the account menu with the privacy policy and deletion,
/// and the question deleting asks first.
void main() {
  testWidgets('account menu and deletion render for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {'success': true})),
      MemoryStore(),
    )..user = {'id': 1, 'name': 'Asha Mehta', 'email': 'asha@telvox.dev'};
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Inbox'),
                actions: [AccountMenu(session: session, onSignOut: () {})],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/account-menu.png');
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await saveReviewImage(
        tester,
        boundary,
        'build/review/account-delete.png',
      );
    });
    session.dispose();
  });
}
