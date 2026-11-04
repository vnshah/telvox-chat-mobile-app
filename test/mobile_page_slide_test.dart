import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

/// A list page that opens a second page, as the inbox opens a chat.
Future<void> openSecond(WidgetTester tester, Widget second) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: T.themeFor(TargetPlatform.android),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Chats')),
          body: Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => second)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.text('Second'), findsOneWidget);
}

Widget page({Widget? body}) => Scaffold(
  appBar: AppBar(title: const Text('Second')),
  body: body ?? const SizedBox.expand(),
);

/// Where the second page's left edge is now: 0 when fully shown.
double edgeOf(WidgetTester tester) =>
    tester.getTopLeft(find.byType(Scaffold).last).dx;

void main() {
  testWidgets('a swipe from the left edge past half way goes back', (
    tester,
  ) async {
    await openSecond(tester, page());
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    final gesture = await tester.startGesture(const Offset(6, 400));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(Offset(width * .6, 0));
    await tester.pump();
    // The page follows the finger, and the list shows beneath it.
    expect(edgeOf(tester), closeTo(width * .6, 30));
    expect(find.text('Chats'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(find.text('Chats'), findsOneWidget);
  });

  testWidgets('a short slow swipe springs back', (tester) async {
    await openSecond(tester, page());
    await tester.timedDragFrom(
      const Offset(6, 400),
      const Offset(80, 0),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(edgeOf(tester), 0);
  });

  testWidgets('a quick flick from the edge goes back', (tester) async {
    await openSecond(tester, page());
    await tester.flingFrom(const Offset(6, 400), const Offset(90, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('a swipe from the middle is left to the page', (tester) async {
    final scroll = ScrollController();
    await openSecond(
      tester,
      page(
        body: SizedBox(
          height: 120,
          child: ListView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < 20; i++)
                SizedBox(width: 100, child: Text('Card $i')),
            ],
          ),
        ),
      ),
    );
    // Swiping the carousel moves it, not the page.
    await tester.dragFrom(const Offset(300, 140), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.dragFrom(const Offset(200, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a page that asks before leaving is not swiped away', (
    tester,
  ) async {
    var asked = 0;
    await openSecond(
      tester,
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) asked++;
        },
        child: page(),
      ),
    );
    await tester.dragFrom(const Offset(6, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(edgeOf(tester), 0);

    // The back button still asks, as before.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('the back button at the edge still works', (tester) async {
    await openSecond(tester, page());
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('the first page ignores the swipe', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: T.themeFor(TargetPlatform.android), home: page()),
    );
    await tester.dragFrom(const Offset(6, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
