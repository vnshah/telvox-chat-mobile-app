import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/ui/whatsapp_text.dart';

void main() {
  test('links starting with a scheme or www are found', () {
    expect(findLinks('Track it at https://telvox.in/t/42?ref=wa now'), [
      'https://telvox.in/t/42?ref=wa',
    ]);
    expect(findLinks('see http://a.example.com and www.example.org/x'), [
      'http://a.example.com',
      'www.example.org/x',
    ]);
  });

  test('bare domains with a common ending are found', () {
    expect(findLinks('Order on shop.example.com/offer today'), [
      'shop.example.com/offer',
    ]);
    expect(findLinks('Visit telvox.in.'), ['telvox.in']);
  });

  test('emails, versions and look-alike words are not links', () {
    expect(findLinks('Mail sales@telvox.in please'), isEmpty);
    expect(findLinks('Update to 1.0.0 and read index.js'), isEmpty);
    expect(findLinks('example.community is not .com'), isEmpty);
    expect(findLinks('https:// alone'), isEmpty);
  });

  test('the punctuation ending a sentence stays out of the link', () {
    expect(findLinks('Go to https://x.com/a, then https://y.com/b!'), [
      'https://x.com/a',
      'https://y.com/b',
    ]);
    expect(findLinks('(see https://x.com/a)'), ['https://x.com/a']);
    expect(findLinks('https://en.wikipedia.org/wiki/Foo_(bar)'), [
      'https://en.wikipedia.org/wiki/Foo_(bar)',
    ]);
  });

  test('a link left without a scheme goes to https', () {
    expect(linkUri('www.example.com').toString(), 'https://www.example.com');
    expect(linkUri('http://example.com').toString(), 'http://example.com');
  });

  test('a preview keeps the link as plain words', () {
    expect(
      whatsappPlain('*Sale* at https://x.com/a_b_c'),
      'Sale at https://x.com/a_b_c',
    );
  });

  testWidgets('a link in a message opens when tapped, formatting untouched', (
    tester,
  ) async {
    final opened = <Uri>[];
    final before = openMessageLink;
    openMessageLink = (uri) async => opened.add(uri);
    addTearDown(() => openMessageLink = before);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text.rich(
            TextSpan(
              children: whatsappSpans(
                '*Pay now* at https://pay.example.com/a_b_c?x=1 or www.telvox.in',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapOnText(
      find.textRange.ofSubstring('https://pay.example.com/a_b_c?x=1'),
    );
    await tester.tapOnText(find.textRange.ofSubstring('www.telvox.in'));
    expect(opened, [
      Uri.parse('https://pay.example.com/a_b_c?x=1'),
      Uri.parse('https://www.telvox.in'),
    ]);

    // Bold still bold; the underscores in the link were not read as italics.
    final rich = tester.widget<RichText>(find.byType(RichText)).text;
    expect(
      rich.toPlainText(),
      'Pay now at https://pay.example.com/a_b_c?x=1 or www.telvox.in',
    );
  });
}
