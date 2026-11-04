import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/app.dart';
import 'package:telvox_chat_mobile_app/mobile/connection.dart';
import 'package:telvox_chat_mobile_app/mobile/realtime.dart';

import 'mobile_api_test.dart' show MemoryStore, answer, fakeApi;
import 'mobile_realtime_test.dart' show FakeSocket, realtimeConfig;

/// A phone whose network and server reachability the test decides.
class FakeNetwork {
  final links = StreamController<bool>.broadcast();
  bool linked = true;
  bool reachable = true;
  int probes = 0;

  ConnectionMonitor monitor({Duration retry = const Duration(seconds: 5)}) =>
      ConnectionMonitor(
        probe: () async {
          probes++;
          return reachable;
        },
        links: links.stream,
        linked: () async => linked,
        retry: retry,
      );
}

void main() {
  group('the connection monitor', () {
    test('no network is offline at once; a network is confirmed', () async {
      final net = FakeNetwork();
      final monitor = net.monitor();
      await monitor.start();
      expect(monitor.online, isTrue);
      final probed = net.probes;

      net.links.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(monitor.online, isFalse);
      // The phone said so: no need to ask the server.
      expect(net.probes, probed);

      net.links.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(net.probes, probed + 1);
      expect(monitor.online, isTrue);
      monitor.dispose();
    });

    test('Wi-Fi without internet is offline, and it keeps checking', () async {
      final net = FakeNetwork()..reachable = false;
      final monitor = net.monitor(retry: const Duration(milliseconds: 20));
      await monitor.start();
      expect(monitor.online, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(net.probes, greaterThan(1));

      net.reachable = true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(monitor.online, isTrue);
      final settled = net.probes;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Back online, it stops asking.
      expect(net.probes, settled);
      monitor.dispose();
    });

    test('opened with no network: offline before asking anyone', () async {
      final net = FakeNetwork()..linked = false;
      final monitor = net.monitor();
      await monitor.start();
      expect(monitor.online, isFalse);
      expect(net.probes, 0);
      monitor.dispose();
    });

    test(
      'in the background it stops polling; back in the app it checks',
      () async {
        final net = FakeNetwork()..reachable = false;
        final monitor = net.monitor(retry: const Duration(milliseconds: 20));
        await monitor.start();
        expect(monitor.online, isFalse);

        monitor.pause();
        final paused = net.probes;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(net.probes, paused);

        net.reachable = true;
        monitor.resume();
        await Future<void>.delayed(Duration.zero);
        expect(net.probes, paused + 1);
        expect(monitor.online, isTrue);
        monitor.dispose();
      },
    );

    test('a request that got no answer checks; before start nothing', () async {
      final net = FakeNetwork();
      final monitor = net.monitor();
      monitor.unreachable();
      await Future<void>.delayed(Duration.zero);
      expect(net.probes, 0);

      await monitor.start();
      net.reachable = false;
      monitor.unreachable();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.online, isFalse);
      monitor.dispose();
    });
  });

  group('the offline bar', () {
    late FakeNetwork net;
    late MobileSession session;

    Future<void> app(WidgetTester tester) async {
      net = FakeNetwork();
      session = MobileSession(
        fakeApi((r, h) => answer(r, h, {})),
        MemoryStore(),
        connection: net.monitor(),
      );
      await tester.pumpWidget(MobileApplication(session: session));
      await tester.pumpAndSettle();
    }

    Future<void> network(WidgetTester tester, bool up) async {
      net.reachable = up;
      net.links.add(up);
      await tester.pump();
      await tester.pump();
    }

    tearDown(() {
      session.connection.dispose();
      session.dispose();
    });

    testWidgets('a bar shows offline; the app stays usable beneath it', (
      tester,
    ) async {
      await app(tester);
      expect(find.byKey(const ValueKey('offline-bar')), findsNothing);

      await network(tester, false);
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsOneWidget);
      // Nothing is covered: the screen beneath still works.
      expect(find.text('Sign in'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'asha@telvox.dev');
      expect(find.text('asha@telvox.dev'), findsOneWidget);

      await network(tester, true);
      await tester.pumpAndSettle();
      expect(find.text('Back online'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('offline-bar')), findsNothing);
      expect(find.text('asha@telvox.dev'), findsOneWidget);
    });

    testWidgets('back works as usual while offline', (tester) async {
      await app(tester);
      unawaited(
        session.calls.navigator!.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('An open page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await network(tester, false);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('An open page'), findsNothing);
      expect(find.text('No internet connection'), findsOneWidget);
      await network(tester, true);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping the bar checks at once', (tester) async {
      await app(tester);
      await network(tester, false);
      await tester.pumpAndSettle();
      net.reachable = true;
      await tester.tap(find.byKey(const ValueKey('offline-bar')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Back online'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('a dropped live connection checks, for Wi-Fi without internet', (
    tester,
  ) async {
    final net = FakeNetwork();
    final sockets = <FakeSocket>[];
    final session = MobileSession(
      fakeApi((r, h) => answer(r, h, {'auth': 'app-key:signature'}))
        ..token = 'token'
        ..wabaId = 7,
      MemoryStore(),
      connection: net.monitor(),
      realtimeConnector: (_) async {
        final socket = FakeSocket();
        sockets.add(socket);
        return socket;
      },
    )..config = realtimeConfig;
    await tester.runAsync(session.connection.start);
    session.realtime.start();
    await tester.pump();
    sockets.last.established();
    await tester.pumpAndSettle();
    expect(session.realtime.state, RealtimeState.connected);
    final probed = net.probes;

    // The phone still shows Wi-Fi, but nothing gets through.
    net.reachable = false;
    await sockets.last.incoming.close();
    await tester.pump();
    await tester.pump();
    expect(session.realtime.state, RealtimeState.reconnecting);
    expect(net.probes, greaterThan(probed));
    expect(session.connection.online, isFalse);

    session.realtime.stop();
    session.connection.dispose();
    session.dispose();
  });

  test(
    'opened offline, the app waits for the network, not the sign-in',
    () async {
      var reachable = false;
      final store = MemoryStore();
      final net = FakeNetwork()..reachable = false;
      final session = MobileSession(
        fakeApi((r, h) {
          if (!reachable) {
            return h.reject(
              DioException.connectionError(
                requestOptions: r,
                reason: 'offline',
              ),
            );
          }
          answer(r, h, switch (r.path) {
            'me' => {'id': 1, 'bound_waba_user_id': 7},
            _ => {'inbox': <String, dynamic>{}},
          });
        }),
        store,
        connection: net.monitor(),
      );
      store.values[session.storageKey] = jsonEncode({
        'token': 'token',
        'waba_id': 7,
      });
      await session.connection.start();
      await session.restore();

      expect(session.awaitingNetwork, isTrue);
      expect(session.error, isNull);
      expect(session.signedIn, isFalse);
      // The sign-in is kept, not forgotten.
      expect(store.values.containsKey(session.storageKey), isTrue);
      expect(session.api.token, 'token');

      reachable = true;
      net.reachable = true;
      await session.connection.check();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.awaitingNetwork, isFalse);
      expect(session.ready, isTrue);
      expect(session.api.wabaId, 7);
      session.connection.dispose();
      session.dispose();
    },
  );

  test(
    'opened offline with the account kept, the inbox opens from the phone',
    () async {
      var reachable = true;
      var name = 'Asha';
      final store = MemoryStore();
      Future<MobileSession> open(FakeNetwork net) async {
        final session = MobileSession(
          fakeApi((r, h) {
            if (!reachable) {
              return h.reject(
                DioException.connectionError(
                  requestOptions: r,
                  reason: 'offline',
                ),
              );
            }
            answer(r, h, switch (r.path) {
              'me' => {'id': 1, 'name': name, 'bound_waba_user_id': 7},
              _ => {
                'inbox': <String, dynamic>{'number': 'Sales'},
              },
            });
          }),
          store,
          connection: net.monitor(),
        );
        await session.connection.start();
        return session;
      }

      // Online once: signed in, the account is kept with the sign-in.
      store.values['session.dev.example.test'] = jsonEncode({
        'token': 'token',
        'waba_id': 7,
      });
      final first = await open(FakeNetwork());
      await first.restore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(first.ready, isTrue);
      first.connection.dispose();
      first.dispose();

      // Opened again with no network: straight into the inbox.
      reachable = false;
      final net = FakeNetwork()..reachable = false;
      final session = await open(net);
      await session.restore();
      expect(session.ready, isTrue);
      expect(session.awaitingNetwork, isTrue);
      expect(session.user!['name'], 'Asha');
      expect(session.api.wabaId, 7);
      expect(object(session.config!['inbox'])['number'], 'Sales');

      // Back online: refreshed in place; the app is not rebuilt.
      final generation = session.generation;
      name = 'Asha Mehta';
      reachable = true;
      net.reachable = true;
      await session.connection.check();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.awaitingNetwork, isFalse);
      expect(session.user!['name'], 'Asha Mehta');
      expect(session.generation, generation);

      // Signing out forgets the kept account too.
      session.api.onUnauthorized!();
      expect(store.values.keys.where((k) => k.startsWith('account.')), isEmpty);
      session.connection.dispose();
      session.dispose();
    },
  );
}
