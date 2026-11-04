import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// A review image of swiping back from the left edge: the chat half way off
/// to the right, under the finger, with the chat list showing beneath it.
void main() {
  testWidgets('edge swipe back renders for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Chats')),
                body: ListView(
                  children: [
                    for (final name in ['Priya', 'Rahul', 'Meera', 'Arjun'])
                      ListTile(
                        leading: CircleAvatar(child: Text(name[0])),
                        title: Text(name),
                        subtitle: const Text('Thanks, see you tomorrow'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              backgroundColor: const Color(0xFFEFE7DE),
                              appBar: AppBar(title: Text(name)),
                              body: const Align(
                                alignment: Alignment.topLeft,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Text('Hello! Is the order ready?'),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Priya'));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(6, 400));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(155, 0));
      await tester.pump();
      await saveReviewImage(tester, boundary, 'build/review/swipe-back.png');
      await gesture.up();
      await tester.pumpAndSettle();
      // Let go before half way: the chat springs back.
      expect(find.text('Hello! Is the order ready?'), findsOneWidget);
    });
  });
}
