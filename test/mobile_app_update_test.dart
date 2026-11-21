import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/app.dart';
import 'package:telvox_chat_mobile_app/mobile/app_update.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;

const _required = {
  'status': 'required',
  'platform': 'android',
  'current_build': 81,
  'min_build': 85,
  'latest_build': 86,
  'play_store_url': 'https://play.google.com/store/apps/details?id=x',
  'apk_url': 'https://example.test/telvox.apk',
  'message': 'This update fixes calling.',
};

void main() {
  test('a request refused as too old (426) asks for the update', () async {
    final api = fakeApi(
      (r, h) => answer(r, h, {
        'success': false,
        'code': 'update_required',
        'message': 'Update',
        'update': _required,
      }, 426),
    );
    await expectLater(api.get('me'), throwsA(isA<ApiFailure>()));
    expect(api.updateRequired.value?['min_build'], 85);
  });

  test('the version check sets, offers or clears the update', () async {
    var reply = <String, Object?>{'update': _required};
    var status = 200;
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, reply, status)),
      MemoryStore(),
    );

    await session.checkForUpdate();
    expect(session.api.updateRequired.value?['status'], 'required');
    expect(session.updateOffered.value, isNull);

    reply = {
      'update': {..._required, 'status': 'available'},
    };
    await session.checkForUpdate();
    expect(session.api.updateRequired.value, isNull);
    expect(session.updateOffered.value?['latest_build'], 86);

    reply = {
      'update': {..._required, 'status': 'current'},
    };
    await session.checkForUpdate();
    expect(session.api.updateRequired.value, isNull);
    expect(session.updateOffered.value, isNull);

    // Refused outright is the same as told it is required.
    reply = {'success': false, 'update': _required};
    status = 426;
    await session.checkForUpdate();
    expect(session.api.updateRequired.value?['min_build'], 85);
    session.dispose();
  });

  test('Android offers Google Play and the APK; iPhone the App Store', () {
    expect(updateLinks(_required).map((l) => l.label), [
      'Update on Google Play',
      'Download the update (APK)',
    ]);
    expect(
      updateLinks({..._required, 'play_store_url': null})
          .map((l) => (l.label, l.primary)),
      [('Download the update (APK)', true)],
    );
    expect(
      updateLinks({
        'platform': 'ios',
        'app_store_url': 'https://apps.apple.com/app/x',
        'apk_url': 'https://example.test/telvox.apk',
      }).map((l) => l.label),
      ['Update on the App Store'],
    );
  });

  testWidgets('a build too old to use shows only the update page', (
    tester,
  ) async {
    final session = MobileSession(
      fakeApi((r, h) {
        if (r.path == 'app/version') {
          answer(r, h, {'update': _required});
        } else {
          answer(r, h, {});
        }
      }),
      MemoryStore(),
    );
    await tester.pumpWidget(MobileApplication(session: session));
    await tester.pumpAndSettle();

    expect(find.text('Update Telvox Chat'), findsOneWidget);
    expect(find.text('This update fixes calling.'), findsOneWidget);
    expect(find.text('Update on Google Play'), findsOneWidget);
    expect(find.text('Download the update (APK)'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    // Nothing of the app behind it: no way past but updating.
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);

    // Lifted on the server: "Check again" lets the app back.
    session.api.updateRequired.value = null;
    await tester.pumpAndSettle();
    expect(find.byType(UpdateRequiredScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('an offered update shows a bar that can be put off', (
    tester,
  ) async {
    final offered = ValueNotifier<Json?>({..._required, 'status': 'available'});
    // Where the app puts it: in the app's builder, above its navigator (and
    // so above the overlay that tooltips and the like need).
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => UpdateOfferBar(offered, child: child!),
        home: const Scaffold(body: Text('Chats')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New version available'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.close_rounded)).semanticLabel,
      'Not now',
    );
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('New version available'), findsNothing);

    // A newer build than the one put off is offered again.
    offered.value = {..._required, 'status': 'available', 'latest_build': 87};
    await tester.pumpAndSettle();
    expect(find.text('New version available'), findsOneWidget);
  });
}
