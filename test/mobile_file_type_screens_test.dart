import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/ui/chat_message.dart';
import 'package:telvox_chat_mobile_app/ui/data.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

import 'support/ui.dart';

/// A review image of documents in a chat, each showing its kind's icon.
void main() {
  testWidgets('document icons render for review', (tester) async {
    await loadUiFonts();
    Directory('build/review').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    Widget document(String name, String size, {bool out = false}) => Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: MessageBubble(
          message: Message('', out: out, time: '11:26'),
          maxWidth: 267,
          contentBefore: DocumentCard(
            MessageMedia(
              'document',
              Uri.parse('https://chat.example.test/storage/7/$name'),
              name,
            ),
            outgoing: out,
            size: size,
          ),
        ),
      ),
    );
    await renderWithRealShadows(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: T.themeFor(TargetPlatform.android),
            home: Scaffold(
              backgroundColor: const Color(0xFFEFE7DE),
              body: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  document('Quotation-November.pdf', '245 KB'),
                  document('Project Details.docx', '2.4 MB', out: true),
                  document('Stock list.xlsx', '1.2 MB'),
                  document('Leads export.csv', '64 KB', out: true),
                  document('Pitch deck.pptx', '3.4 MB'),
                  document('Photos.zip', '12 MB', out: true),
                  document('Notes.txt', '2 KB'),
                  document('Drawing.dwg', '540 KB', out: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saveReviewImage(tester, boundary, 'build/review/documents.png');
    });
  });
}
