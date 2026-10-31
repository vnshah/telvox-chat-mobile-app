import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/editors.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';
import 'package:telvox_chat_mobile_app/mobile/template_plan.dart';
import 'package:telvox_chat_mobile_app/mobile/tickets.dart';
import 'package:telvox_chat_mobile_app/mobile/contact_actions.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;

TemplatePlan template(List<Json> parts, {String category = 'UTILITY'}) =>
    TemplatePlan({'category': category, 'rowdata': parts});

void main() {
  test(
    'attachments validate type, size and empty files before upload',
    () async {
      for (final file in [
        XFile.fromData(Uint8List(3), path: 'voice.wma'),
        XFile.fromData(Uint8List(0), path: 'empty.pdf'),
        XFile.fromData(Uint8List(5 * 1024 * 1024 + 1), path: 'large.png'),
      ]) {
        await expectLater(
          Attachment.fromFile(file),
          throwsA(isA<ApiFailure>()),
        );
      }
      await expectLater(
        Attachment.fromFile(
          XFile.fromData(Uint8List(2), path: 'file.pdf'),
          requiredKind: 'image',
        ),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test(
    'multipart retry keeps key and fields but creates a fresh readable upload',
    () async {
      final attachment = await Attachment.fromFile(
        XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'photo.PNG'),
      );
      final forms = <FormData>[];
      final keys = <Object?>[];
      final api = fakeApi((r, h) {
        forms.add(r.data as FormData);
        keys.add(r.headers['Idempotency-Key']);
        if (forms.length == 1) {
          h.reject(
            DioException(
              requestOptions: r,
              type: DioExceptionType.receiveTimeout,
            ),
          );
        } else {
          answer(r, h, {'success': true});
        }
      });
      final message = PendingSend({
        'contact_id': 12,
        'message_type': 'text',
        'body': 'Caption',
      }, attachment: attachment);
      final repo = InboxRepository(api);
      await expectLater(repo.send(message), throwsA(isA<ApiFailure>()));
      await repo.send(message);
      expect(keys[0], keys[1]);
      expect(identical(forms[0], forms[1]), false);
      for (final form in forms) {
        final fields = Map.fromEntries(form.fields);
        expect(fields['message_type'], 'image');
        expect(fields['body'], 'Caption');
        expect(fields['temp_message_id'], keys[0]);
        expect(form.files.single.key, 'media');
        expect(form.files.single.value.contentType.toString(), 'image/png');
        expect(
          await form.files.single.value
              .finalize()
              .expand((bytes) => bytes)
              .toList(),
          [1, 2, 3],
        );
      }
    },
  );

  test('media URLs reject unsafe schemes and credentials', () {
    for (final url in [
      'file:///etc/passwd',
      'javascript:alert(1)',
      'http://example.test/a',
      'https://user:secret@example.test/a',
    ]) {
      expect(mediaUri(url, 'https://dev.example.test/api/mobile/v1/'), isNull);
    }
    expect(
      mediaUri(
        'inbox/a.png',
        'https://dev.example.test/api/mobile/v1/',
      ).toString(),
      'https://dev.example.test/storage/inbox/a.png',
    );
    expect(
      MessageMedia.fromMessage({
        'message_type': 'image',
        'message_body_json':
            '{"image":{"link":"https://cdn.example.test/a.png"}}',
      }, 'https://dev.example.test')?.type,
      'image',
    );
  });

  test(
    'template text, media, button and offer values follow the API contract',
    () {
      final plan = template([
        {'type': 'HEADER', 'format': 'DOCUMENT'},
        {'type': 'BODY', 'text': 'Hi {{1}}, order {{2}}'},
        {
          'type': 'BUTTONS',
          'buttons': [
            {'type': 'URL', 'url': 'https://example.test/{{1}}'},
          ],
        },
        {'type': 'LIMITED_TIME_OFFER'},
      ]);
      expect(
        plan.variables({
          'header.media': {
            'file_url': 'https://example.test/a.pdf',
            'new_file_name': 'a.pdf',
          },
          'body.0': 'Priya',
          'body.1': '123',
          'button.url': 'order-123',
          'lto': '2030-01-01T12:00:00+05:30',
        }),
        {
          'mediaTemplate': {
            'header_media': {
              'file_url': 'https://example.test/a.pdf',
              'new_file_name': 'a.pdf',
            },
          },
          'bodyText': ['Priya', '123'],
          'button_url_text': 'order-123',
          'limited_time_offer': '2030-01-01T12:00:00+05:30',
        },
      );
      expect(
        plan.requirements,
        containsAll([
          'header_media',
          'body_text',
          'button_url_text',
          'limited_time_offer',
        ]),
      );
      expect(() => plan.variables({}), throwsA(isA<ApiFailure>()));
    },
  );

  test('location headers validate coordinates and auth templates use OTP', () {
    final location = template([
      {'type': 'HEADER', 'format': 'LOCATION'},
    ]);
    final values = {
      'location.latitude': '23.02',
      'location.longitude': '72.57',
      'location.name': 'Office',
      'location.address': 'Ahmedabad',
    };
    expect(
      object(location.variables(values)['headerLocation'])['latitude'],
      23.02,
    );
    expect(
      () => location.variables({...values, 'location.latitude': '91'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => location.variables({...values, 'location.longitude': 'NaN'}),
      throwsA(isA<ApiFailure>()),
    );
    final auth = template([
      {'type': 'BODY', 'text': '{{1}} is your code'},
      {
        'type': 'BUTTONS',
        'buttons': [
          {'type': 'OTP'},
        ],
      },
    ], category: 'AUTHENTICATION');
    expect(auth.variables({'otp': '123456'}), {'otp': '123456'});
  });

  test('carousel uses one-based media keys, zero-based body arrays and shared button', () {
    final plan = template([
      {
        'type': 'CAROUSEL',
        'cards': [
          for (var i = 0; i < 2; i++)
            {
              'components': [
                {'type': 'HEADER', 'format': 'IMAGE'},
                {'type': 'BODY', 'text': 'Product {{1}}'},
                {
                  'type': 'BUTTONS',
                  'buttons': [
                    {'type': 'URL', 'url': 'https://example.test/{{1}}'},
                  ],
                },
              ],
            },
        ],
      },
    ]);
    final result = plan.variables({
      'card.0.media': {'file_url': 'https://example.test/1.png'},
      'card.1.media': {'file_url': 'https://example.test/2.png'},
      'card.0.body.0': 'One',
      'card.1.body.0': 'Two',
      'card.button': 'sale',
    });
    expect(object(object(result['mediaTemplate'])['carousel']).keys, [
      '1',
      '2',
    ]);
    expect(result['carousel_body_text'], [
      ['One'],
      ['Two'],
    ]);
    expect(result['card_button'], 'sale');
  });

  testWidgets(
    'editor retains values and displays server rejection before retry',
    (tester) async {
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: ActionEditor(
            title: 'Edit subject',
            fields: const [EditField('subject', 'Subject', required: true)],
            save: (v) async {
              saves++;
              expect(v['subject'], 'Delivery issue');
              throw const ApiFailure('Not permitted');
            },
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await tester.enterText(find.byType(TextFormField), 'Delivery issue');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(find.text('Not permitted'), findsOneWidget);
      expect(find.text('Delivery issue'), findsOneWidget);
    },
  );

  testWidgets(
    'ticket displays ticket-specific notes and tags and posts a subject update',
    (tester) async {
      final requests = <RequestOptions>[];
      final api = fakeApi((r, h) {
        requests.add(r);
        answer(
          r,
          h,
          r.path == 'inbox/ticket_details'
              ? {
                  'success': true,
                  'data': {
                    'ticket': {
                      'id': 7,
                      'subject': 'Old subject',
                      'ticket_number': 'TKT-7',
                    },
                    'contact': {'id': 12},
                    'ticket_tags': [
                      {'id': 9, 'name': 'VIP'},
                    ],
                    'ticket_notes': [
                      {
                        'id': 51,
                        'content': 'Call after six',
                        'author': {'name': 'Agent'},
                      },
                    ],
                  },
                }
              : {'success': true},
        );
      });
      final session = MobileSession(api, MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: TicketPage(session, 7),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Call after six'), 200);
      expect(find.text('Call after six'), findsOneWidget);
      expect(find.text('VIP'), findsOneWidget);
      // The subject is edited by tapping it in the ticket header.
      await tester.scrollUntilVisible(find.text('Old subject'), -300);
      await tester.tap(find.text('Old subject'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Changed subject');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final mutation = requests.singleWhere(
        (r) => r.path == 'inbox/tickets/7/subject',
      );
      expect(mutation.method, 'POST');
      expect(mutation.data, {'subject': 'Changed subject'});
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'contact name editor saves profile_name to scoped contact route',
    (tester) async {
      final requests = <RequestOptions>[];
      final api = fakeApi((r, h) {
        requests.add(r);
        answer(
          r,
          h,
          r.path == 'inbox/getContactDetails'
              ? {
                  'success': true,
                  'data': {
                    'contact': {'id': 12, 'profile_name': 'Priya'},
                    'tags': [],
                    'notes': [],
                  },
                }
              : {'success': true},
        );
      });
      final session = MobileSession(api, MemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          theme: T.themeFor(TargetPlatform.android),
          home: ContactActionsPage(session, 12),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Priya Sharma');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        requests.singleWhere((r) => r.path == 'inbox/contacts/12/profile').data,
        {'profile_name': 'Priya Sharma'},
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
