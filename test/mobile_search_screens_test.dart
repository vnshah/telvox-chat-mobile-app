import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_search_test.dart' show History;
import 'support/ui.dart';

/// Review images of searching a chat: the matches, and the chat jumped to
/// one with it lit up. Written to build/review/search-*.png.
void main() {
  testWidgets('conversation search renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = History();
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, server.reply(r))),
      MemoryStore(),
    )..user = {'id': 1};
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: LiveChat(session, {
              'id': 12,
              'profile_name': 'Alex',
              'wa_id': '919999999999',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search chat'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'refund');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await saveReviewImage(
        tester,
        boundary,
        'build/review/search-results.png',
      );

      await tester.tap(find.byKey(const ValueKey('search-result-13')));
      // Frame by frame, as the device draws it: scrolled to, still lit.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await saveReviewImage(tester, boundary, 'build/review/search-jumped.png');
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });
}
