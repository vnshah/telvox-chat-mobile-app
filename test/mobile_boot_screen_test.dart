import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/app.dart';
import 'package:telvox_chat_mobile_app/mobile/boot_screen.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

/// A phone whose saved session takes as long as the test likes to read.
class SlowStore extends MemoryStore {
  final opened = Completer<void>();
  @override
  Future<String?> read(String key) async {
    await opened.future;
    return super.read(key);
  }
}

void main() {
  testWidgets('the launch screen carries on while the app signs back in', (
    tester,
  ) async {
    final store = SlowStore();
    final session = MobileSession(fakeApi((r, h) => answer(r, h, {})), store);
    await tester.pumpWidget(MobileApplication(session: session));

    expect(find.byType(BootScreen), findsOneWidget);
    final spinner = find.byType(CircularProgressIndicator);
    double shown() => tester
        .widget<FadeTransition>(
          // Its own fade; the whole app fades too, once signed in.
          find
              .ancestor(of: spinner, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    // The first frame is the phone's launch screen: the bubble alone.
    Opacity layer(Finder text) => tester.widget<Opacity>(
      find.ancestor(of: text, matching: find.byType(Opacity)).first,
    );
    expect(layer(find.text('THE TELVOX FAMILY')).opacity, 0);
    // Then, from the next frame, the rest of the splash unfolds from it.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(layer(find.text('THE TELVOX FAMILY')).opacity, 1);
    expect(layer(find.text('telvox')).opacity, 1);
    expect(find.text('Chat'), findsOneWidget);
    // A quick start shows no spinner.
    expect(shown(), 0);
    // A slow one shows it is still at work.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(shown(), 1);

    store.opened.complete();
    await tester.pump();
    await tester.pump();
    // Signed in (or not), the boot screen fades into the app, no cut.
    expect(find.byType(BootScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(BootScreen), findsNothing);
    session.dispose();
  });
}
