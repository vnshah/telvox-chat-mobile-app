import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/location.dart';
import 'package:telvox_chat_mobile_app/mobile/maps.dart';
import 'package:telvox_chat_mobile_app/mobile/message_content.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/ui/chat_message.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// Rows as the inbox stores them (InboxSendMessageController, Interakt and
/// the webhook), for the requests and locations a chat shows.
final now = DateTime.now().toUtc();
String at(int minutes) =>
    now.subtract(Duration(minutes: 60 - minutes)).toIso8601String();

final callRequest = {
  'id': 1,
  'type': 1,
  'message_type': 'interactiveCallPermissionRequest',
  'message_body': jsonEncode({
    'type': 'interactiveCallPermissionRequest',
    'component': {
      'type': 'call_permission_request',
      'body': {'text': 'Can we call you about your order?'},
      'action': {'name': 'call_permission_request'},
    },
  }),
  'message_body_json': jsonEncode({
    'type': 'interactiveCallPermissionRequest',
    'component': {
      'type': 'call_permission_request',
      'body': {'text': 'Can we call you about your order?'},
      'action': {'name': 'call_permission_request'},
    },
  }),
  'message_status': 3,
  'created_at': at(1),
};

final locationRequest = {
  'id': 2,
  'type': 1,
  'message_id': 'wamid.request',
  'message_type': 'interactiveGetAddress',
  'message_body_json': jsonEncode({
    'type': 'interactiveGetAddress',
    'component': {
      'type': 'location_request_message',
      'body': {'text': 'Please share your location.'},
      'action': {'name': 'send_location'},
    },
  }),
  'message_status': 3,
  'created_at': at(2),
};

final sentLocation = {
  'id': 3,
  'type': 1,
  'message_type': 'location',
  'message_body_json': jsonEncode({
    'type': 'location',
    'location': {
      'latitude': '23.0300',
      'longitude': '72.5800',
      'name': 'Head office',
      'address': 'Ashram Road, Ahmedabad, Gujarat 380009',
    },
  }),
  'message_status': 3,
  'created_at': at(3),
};

/// The customer's pin, in answer to the request: no name or address.
final receivedLocation = {
  'id': 4,
  'type': 2,
  'message_type': 'location',
  'message_body': 'Current location',
  'contextual_reply_id': 'wamid.request',
  'contextual_message': 'Please share your location.',
  'contextual_message_type': 'interactiveGetAddress',
  'contextual_message_json': locationRequest['message_body_json'],
  'message_body_json': jsonEncode({
    'type': 'location',
    'context': {'id': 'wamid.request'},
    'location': {'latitude': 21.170240, 'longitude': 72.831062},
  }),
  'created_at': at(4),
};

void main() {
  test('requests carry the customer’s button; locations read as words', () {
    final call = MessageContent(callRequest);
    expect(call.request, 'call');
    expect(call.text, 'Can we call you about your order?');

    final ask = MessageContent(locationRequest);
    expect(ask.request, 'location');
    expect(ask.buttons, ['Send location']);

    // An inbox preview or reply quote names the place, not its coordinates.
    expect(MessageContent(sentLocation).summary, 'Head office');
    expect(MessageContent(receivedLocation).summary, 'Location');
  });

  testWidgets('each request and location renders as WhatsApp frames it', (
    tester,
  ) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: T.themeFor(TargetPlatform.android),
          home: Scaffold(
            backgroundColor: const Color(0xFFEFE7DE),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(8, 40, 8, 8),
              children: [
                for (final Json r in [
                  callRequest,
                  locationRequest,
                  sentLocation,
                  receivedLocation,
                ])
                  LiveMessageView(
                    message: ApiMessage(r),
                    apiBase: 'https://example.test/api/mobile/v1/',
                    first: true,
                    contactName: 'Nikunj',
                    businessName: 'Renav Business',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await saveReviewImage(
      tester,
      boundary,
      'build/review/location-messages.png',
    );
    expect(tester.takeException(), isNull);

    // The call request: its message, then the card the customer answers.
    expect(find.text('Can we call you about your order?'), findsOneWidget);
    expect(find.text('Can Renav Business call you?'), findsOneWidget);
    expect(find.text('Choose preference'), findsOneWidget);

    // The location request shows the customer's "Send location" button.
    expect(find.text('Send location'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);

    // A named place, and the customer's bare pin read by its coordinates.
    expect(find.text('Head office'), findsOneWidget);
    expect(find.text('Ashram Road, Ahmedabad, Gujarat 380009'), findsOneWidget);
    // The customer's bare pin is the map alone, its time over the map, as
    // WhatsApp shows one; tapping either opens Google Maps.
    expect(find.text('Shared location'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Open Location in Google Maps',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Open Head office in Google Maps',
      ),
      findsOneWidget,
    );
    expect(find.byType(OverlayStamp), findsOneWidget);
    // Buttons hang under the time, the bubble's full width.
    expect(find.byType(BubbleButtons), findsNWidgets(2));
    // The pin answers the request, quoted above it as on the web.
    expect(
      find.textContaining('Please share your location.', findRichText: true),
      findsNWidgets(2),
    );
  });

  testWidgets('the location picker renders for review', (tester) async {
    await loadUiFonts();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: T.themeFor(TargetPlatform.android),
          home: LocationPickerPage(source: _Here(), lookup: _Places()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ashram Road, Ahmedabad, Gujarat 380009'), findsOneWidget);
    await saveReviewImage(tester, boundary, 'build/review/location-picker.png');
  });
}

class _Here implements LocationSource {
  @override
  Future<({double latitude, double longitude})> current() async =>
      (latitude: 23.0225, longitude: 72.5714);
}

class _Places implements PlaceLookup {
  @override
  Future<Place?> at(double latitude, double longitude) async => (
    latitude: latitude,
    longitude: longitude,
    name: null,
    address: 'Ashram Road, Ahmedabad, Gujarat 380009',
  );

  @override
  Future<List<Place>> search(String query) async => const [];
}
