import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/media.dart';
import 'package:telvox_chat_mobile_app/mobile/message_view.dart';
import 'package:telvox_chat_mobile_app/ui/file_type.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

/// Documents show their kind as WhatsApp's page, in its colour.
void main() {
  test('each kind is named as the details line names it', () {
    expect(FileType.nameOf('Project Details.docx'), 'Microsoft Word');
    expect(FileType.nameOf('stock.XLSX'), 'Microsoft Excel');
    expect(FileType.nameOf('pitch.ppt'), 'Microsoft PowerPoint');
    expect(FileType.nameOf('Quote.pdf'), 'PDF');
    expect(FileType.nameOf('leads.csv'), 'CSV');
    expect(FileType.nameOf('README'), 'File');
  });

  test('each kind of file has its colour', () {
    expect(FileType.of('Quote.PDF'), FileType.pdf);
    expect(FileType.of('brief.docx'), FileType.word);
    expect(FileType.of('stock.xlsx'), FileType.sheet);
    expect(FileType.of('leads.csv'), FileType.sheet);
    expect(FileType.of('pitch.pptx'), FileType.slides);
    expect(FileType.of('notes.txt'), FileType.text);
    expect(FileType.of('photos.zip'), FileType.archive);
    expect(FileType.of('contact.vcf'), FileType.contact);
    // Unknown, or no extension at all: a plain file.
    expect(FileType.of('drawing.dwg'), FileType.file);
    expect(FileType.of('README'), FileType.file);
    expect(FileType.of('.hidden'), FileType.file);
  });

  testWidgets('a document bubble shows its icon, not a text badge', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: T.themeFor(TargetPlatform.android),
        home: Scaffold(
          body: Center(
            child: DocumentCard(
              MessageMedia(
                'document',
                Uri.parse('https://chat.example.test/storage/7/Quote.pdf'),
                'Quote.pdf',
              ),
              outgoing: false,
              size: '245 KB',
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('file-type-icon')), findsOneWidget);
    // A red page with no letters on it; the details line names the kind.
    expect(find.text('PDF'), findsNothing);
    expect(find.text('245 KB • PDF'), findsOneWidget);
    // Read aloud as what it is.
    expect(find.bySemanticsLabel(RegExp('PDF')), findsWidgets);
    semantics.dispose();
  });
}
