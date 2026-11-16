import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';
import 'package:telvox_chat_mobile_app/ui/whatsapp_text.dart';

import 'support/ui.dart';

/// Messages drawn as the web inbox draws them, from the shapes the server
/// stores: WhatsApp's text formatting, a template's text or location header,
/// a carousel, a product list whose catalogue is not synced, a file never
/// saved, what WhatsApp will not pass on, and shared contacts.
void main() {
  group('WhatsApp formatting', () {
    TextStyle? styleOf(List<InlineSpan> spans, String text) {
      TextStyle? found;
      void visit(InlineSpan span, TextStyle? inherited) {
        if (span is! TextSpan) return;
        final style = inherited?.merge(span.style) ?? span.style;
        if (span.text == text) found = style;
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }

      for (final s in spans) {
        visit(s, null);
      }
      return found;
    }

    test('bold, italic, strikethrough, monospace and code', () {
      final spans = whatsappSpans(
        'Your *loan* is _approved_, ~maybe~ ```CODE1``` and `x=1`',
      );
      expect(styleOf(spans, 'loan')!.fontWeight, FontWeight.w700);
      expect(styleOf(spans, 'approved')!.fontStyle, FontStyle.italic);
      expect(styleOf(spans, 'maybe')!.decoration, TextDecoration.lineThrough);
      expect(styleOf(spans, 'CODE1')!.fontFamily, 'monospace');
      expect(styleOf(spans, 'x=1')!.fontFamily, 'monospace');
      expect(
        whatsappPlain('Your *loan* is _approved_'),
        'Your loan is approved',
      );
    });

    test('nested, as "*_Welcome_*"', () {
      final style = styleOf(whatsappSpans('*_Welcome_*'), 'Welcome')!;
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontStyle, FontStyle.italic);
    });

    test('markers inside words, sums and lone stars stay as typed', () {
      for (final text in [
        'Savanna_Fibre and snake_case_name',
        '2*3*4 = 24',
        'Rate us * 5',
        'a * b * c',
        'price_list.pdf',
      ]) {
        expect(whatsappPlain(text), text, reason: text);
      }
    });

    test('bullets and quotes', () {
      expect(
        whatsappPlain('Plans:\n* Basic\n- Pro\n> Terms apply'),
        'Plans:\n•  Basic\n•  Pro\nTerms apply',
      );
    });
  });

  ApiMessage row(String type, Object? body, {int direction = 1}) => ApiMessage({
    'id': 1,
    'type': direction,
    'message_type': type,
    'message_body': body is String ? body : '',
    'message_body_json': body is String ? null : body,
    'message_status': 3,
    'created_at': '2026-11-16T10:00:00Z',
  });

  Future<void> show(WidgetTester tester, List<ApiMessage> messages) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(
          body: ListView(
            children: [
              for (final m in messages)
                LiveMessageView(
                  message: m,
                  apiBase: 'https://chat.example.test/api/mobile/v1/',
                  first: true,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // A carousel template as stored: each card a list of its components.
  final carousel = {
    'preview': [
      {'type': 'BODY', 'text': 'Hello, see our *new* plans'},
      {
        'type': 'CAROUSEL',
        'cards': [
          [
            {
              'type': 'HEADER',
              'format': 'IMAGE',
              'image': {'link': 'https://img.test/a.jpg'},
            },
            {'type': 'BODY', 'text': 'Fibre 100'},
            {
              'type': 'BUTTONS',
              'buttons': [
                {'type': 'QUICK_REPLY', 'text': 'Choose 100'},
              ],
            },
          ],
          [
            {
              'type': 'HEADER',
              'format': 'IMAGE',
              'image': {'link': 'https://img.test/b.jpg'},
            },
            {'type': 'BODY', 'text': 'Fibre 300'},
            {
              'type': 'BUTTONS',
              'buttons': [
                {'type': 'URL', 'text': 'Details'},
              ],
            },
          ],
        ],
      },
    ],
  };

  test('a carousel keeps its cards', () {
    final cards = row('template', carousel).content.carousel;
    expect(cards.map((c) => c.text), ['Fibre 100', 'Fibre 300']);
    expect(cards.first.image, 'https://img.test/a.jpg');
    expect(cards.last.buttons.single, ('Details', 'url'));
  });

  test('a text header is bold above the body; previews stay plain', () {
    final m = row('template', {
      'preview': [
        {'type': 'HEADER', 'format': 'TEXT', 'text': 'Finalize account'},
        {'type': 'BODY', 'text': 'Hi test, verify your profile.'},
      ],
    });
    expect(m.content.heading, 'Finalize account');
    expect(m.content.text, 'Hi test, verify your profile.');
    expect(
      messagePresentation(m).text,
      '*Finalize account*\nHi test, verify your profile.',
    );
  });

  test('a location header off the globe is words, not a map', () {
    final m = row('template', {
      'preview': [
        {
          'type': 'HEADER',
          'format': 'LOCATION',
          'location': {
            'name': 'aasd',
            'address': 'nikol',
            'latitude': '12312',
            'longitude': '123123',
          },
        },
        {'type': 'BODY', 'text': 'See you there'},
      ],
    });
    expect(m.content.headerLocation, isNull);
    expect(m.content.text, contains('aasd'));
  });

  testWidgets('every kind the web shows, in the chat', (tester) async {
    await show(tester, [
      row('text', 'Your *loan* is approved'),
      row('template', carousel),
      row('template', {
        'preview': [
          {
            'type': 'HEADER',
            'format': 'LOCATION',
            'location': {
              'name': 'Renav office',
              'address': 'Rajkot',
              'latitude': '22.30',
              'longitude': '70.80',
            },
          },
          {'type': 'BODY', 'text': 'We cannot wait to see you there!'},
        ],
      }),
      row('interactiveMultipleProduct', {
        'type': 'interactiveMultipleProduct',
        'component': {
          'type': 'product_list',
          'header': {'type': 'text', 'text': 'Featured products'},
          'body': {'text': 'Hi, have a look'},
          'action': {
            'catalog_id': '41',
            'sections': [
              {
                'title': 'Products',
                'product_items': [
                  {'product_retailer_id': 'a'},
                  {'product_retailer_id': 'b'},
                  {'product_retailer_id': 'c'},
                ],
              },
            ],
          },
        },
      }),
    ]);
    // Bold, without its stars.
    expect(find.textContaining('*loan*'), findsNothing);
    expect(find.textContaining('loan', findRichText: true), findsWidgets);
    // Formatted above a carousel too.
    expect(find.textContaining('*new*'), findsNothing);
    // The carousel's cards and their buttons.
    expect(find.byKey(const ValueKey('carousel-card-1')), findsOneWidget);
    expect(find.text('Choose 100'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    // The location header's map card.
    expect(find.text('Renav office'), findsOneWidget);
    // The product list counts its items without the catalogue.
    expect(find.text('3 Items'), findsOneWidget);
    expect(find.text('View items'), findsOneWidget);
  });

  testWidgets('files never saved, deleted messages and shared contacts', (
    tester,
  ) async {
    await show(tester, [
      row('image', {'media_name': null, 'media_path': null}, direction: 2),
      row('audio', {
        'type': 'audio',
        'audio': {'id': '1493', 'voice': true},
      }, direction: 2),
      row('unsupported', {
        'type': 'unsupported',
        'unsupported': {'type': 'revoke'},
      }, direction: 2),
      row('unsupported', {
        'type': 'unsupported',
        'unsupported': {'type': 'album'},
      }, direction: 2),
      row('contacts', {
        'contacts': [
          {
            'name': {'first_name': 'Asha', 'formatted_name': 'Asha Patel'},
            'phones': [
              {'phone': '+91 98000 00001'},
            ],
          },
        ],
      }, direction: 2),
    ]);
    expect(find.byKey(const ValueKey('media-unavailable')), findsNWidgets(2));
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Voice message'), findsOneWidget);
    expect(find.text('This message was deleted'), findsOneWidget);
    expect(find.text('Photo album'), findsOneWidget);
    expect(find.text('Unsupported message'), findsNothing);
    expect(find.text('Asha Patel'), findsOneWidget);
    expect(find.text('+91 98000 00001'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('review image', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(412, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Scaffold(
              backgroundColor: const Color(0xFFEFE7DE),
              body: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final m in [
                    row('template', {
                      'preview': [
                        {
                          'type': 'HEADER',
                          'format': 'TEXT',
                          'text': 'Loan update',
                        },
                        {
                          'type': 'BODY',
                          'text':
                              'Hello BEGAM 👋\n\n🎉 *Your loan application '
                              'has been approved.*\n\n_Only 2 steps are '
                              'pending._ ~Old offer~\n* Open the app\n* '
                              'Finish the steps',
                        },
                      ],
                    }),
                    row('template', carousel),
                    row('image', {'media_path': null}, direction: 2),
                    row('unsupported', {
                      'unsupported': {'type': 'revoke'},
                    }, direction: 2),
                    row('contacts', {
                      'contacts': [
                        {
                          'name': {'formatted_name': 'Asha Patel'},
                          'phones': [
                            {'phone': '+91 98000 00001'},
                          ],
                        },
                      ],
                    }, direction: 2),
                  ])
                    LiveMessageView(
                      message: m,
                      apiBase: 'https://chat.example.test/api/mobile/v1/',
                      first: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await saveReviewImage(tester, key, 'build/review/message-previews.png');
    });
    await tester.pumpWidget(const SizedBox());
  });
}
