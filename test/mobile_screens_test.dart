import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/api.dart';
import 'package:telvox_chat_mobile_app/mobile/screens.dart';
import 'package:telvox_chat_mobile_app/mobile/tickets.dart';
import 'package:telvox_chat_mobile_app/mobile/contact_actions.dart';
import 'package:telvox_chat_mobile_app/mobile/chat.dart';
import 'package:telvox_chat_mobile_app/mobile/templates.dart';
import 'package:telvox_chat_mobile_app/mobile/editors.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'mobile_api_test.dart' show fakeApi, answer, MemoryStore;
import 'mobile_conversation_test.dart' show details, sampleMessages;
import 'support/ui.dart';

final contact = <String, dynamic>{
  'id': 12,
  'profile_name': 'Alex Morgan',
  'wa_id': '919999999999',
  'last_message': sampleMessages[2],
};
final templateData = <String, dynamic>{
  'id': 4,
  'name': 'order_update',
  'category': 'UTILITY',
  'language': 'en',
  'rowdata': [
    {'type': 'HEADER', 'format': 'IMAGE'},
    {'type': 'BODY', 'text': 'Hello {{1}}, order {{2}} is ready.'},
  ],
};
final ticket = <String, dynamic>{
  'id': 7,
  'ticket_number': 'TKT-7',
  'subject': 'Delivery enquiry',
  'contact_id': 12,
  'assign_user_id': 1,
  'status': {'id': 1, 'name': 'Open'},
  'priority': {'id': 1, 'name': 'Normal'},
};
final metadata = <String, dynamic>{
  'users': [
    {'id': 1, 'name': 'Agent'},
  ],
  'departments': [
    {'id': 1, 'name': 'Support'},
  ],
  'statuses': [
    {'id': 1, 'name': 'Open'},
  ],
  'priorities': [
    {'id': 1, 'name': 'Normal'},
  ],
  'tags': [],
  'defaults': {'assign_user_id': 1},
};
void main() {
  testWidgets(
    'all integrated screen areas fit small phones on both platforms',
    (tester) async {
      await loadUiFonts();
      Directory('build/review').createSync(recursive: true);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final session = MobileSession(
          fakeApi(
            (r, h) => answer(r, h, switch (r.path) {
              'businesses' => {
                'data': [
                  {'id': 1, 'name': 'Example business'},
                ],
              },
              'inbox/contacts' => [contact],
              'inbox/tickets' => {
                'success': true,
                'data': [ticket],
              },
              'inbox/getContactDetails' => {
                'success': true,
                'data': {
                  ...details(),
                  'contact': {...contact, ...object(details()['contact'])},
                  'can_assign_contact': true,
                  'users': [
                    {'id': 1, 'name': 'Agent'},
                  ],
                  'tags': [
                    {'id': 1, 'name': 'Customer'},
                  ],
                  'notes': [
                    {'id': 1, 'content': 'Follow up tomorrow'},
                  ],
                },
              },
              'inbox/ticket_details' => {
                'success': true,
                'data': {
                  'ticket': ticket,
                  'contact': contact,
                  'ticket_tags': [
                    {'id': 1, 'name': 'Customer'},
                  ],
                  'ticket_notes': [
                    {
                      'id': 1,
                      'content': 'Delivery enquiry',
                      'author': {'name': 'Agent'},
                    },
                  ],
                },
              },
              'inbox/ticket_create_metadata' => {
                'success': true,
                'data': metadata,
              },
              'inbox/templates' => {
                'success': true,
                'data': [templateData],
              },
              'inbox/templates/4' => {'success': true, 'data': templateData},
              'inbox/custom-fields' => {
                'success': true,
                'data': {
                  'customFields': [
                    {'id': 1, 'name': 'City', 'type': 1},
                  ],
                  'customFieldValues': {
                    '1': {'value': 'Ahmedabad'},
                  },
                },
              },
              _ => {'success': true, 'data': []},
            }),
          ),
          MemoryStore(),
        )..user = {'id': 1};
        final pages = <String, Widget>{
          'login': LoginScreen(session),
          'businesses': NumberPicker(session),
          'home': LiveHome(session),
          for (var k = 0; k < 3; k++)
            'list-$k': Scaffold(
              body: SafeArea(child: LiveList(session, kind: k)),
            ),
          'contact': ContactActionsPage(session, 12),
          'contact-create': ContactEditor(session),
          'fields': ContactFieldsPage(session, 12),
          'gallery': MediaGalleryPage(session, contactId: 12),
          'ticket': TicketPage(session, 7),
          'ticket-create': CreateTicketPage(session),
          'templates': TemplatePicker(session, contact),
          'template-send': TemplateSend(session, contact, templateData),
          'edit': ActionEditor(
            title: 'Assign conversation',
            fields: [
              EditField(
                'user_id',
                'Agent',
                options: metadata['users'] as List<Json>,
                required: true,
              ),
            ],
            save: (_) async {},
          ),
        };
        for (final page in pages.entries) {
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: T.themeFor(platform),
                home: page.value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${platform.name}/${page.key}',
          );
          if (platform == TargetPlatform.android &&
              [
                'list-0',
                'contact',
                'ticket',
                'template-send',
              ].contains(page.key)) {
            await saveReviewImage(
              tester,
              boundary,
              'build/review/live-${page.key}.png',
            );
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        }
        session.dispose();
      }
    },
  );
  testWidgets('shared media uses the server document/link filter names', (
    tester,
  ) async {
    final types = <String>[];
    final session = MobileSession(
      fakeApi((r, h) {
        types.add('${r.data['type']}');
        answer(r, h, {'success': true, 'data': []});
      }),
      MemoryStore(),
    );
    await tester.pumpWidget(
      MaterialApp(home: MediaGalleryPage(session, contactId: 12)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('link'));
    await tester.pumpAndSettle();
    expect(types, ['media', 'document', 'link']);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
