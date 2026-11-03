import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/ui/theme.dart';

void main() {
  test('one person keeps one colour; neighbours and namesakes differ', () {
    expect(avatarColors('20117'), avatarColors(' 20117 '));
    // Contacts made one after another must not share a few similar hues.
    final run = {for (var id = 20100; id < 20130; id++) avatarColors('$id')};
    expect(run.length, greaterThanOrEqualTo(8));
    // Every pair stays readable: deep letters on soft tints.
    for (final (fill, ink) in avatarPalette) {
      final light = fill.computeLuminance(), dark = ink.computeLuminance();
      expect((light + .05) / (dark + .05), greaterThan(4.5));
    }
  });

  testWidgets('initials are large and coloured per person', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [Avatar('Rahil', seed: 1), Avatar('Urmi Shah', seed: 2)],
        ),
      ),
    );
    final one = tester.widget<Text>(find.text('R')).style!;
    final two = tester.widget<Text>(find.text('US')).style!;
    expect(one.fontSize, greaterThan(two.fontSize!));
    expect(two.fontSize, greaterThanOrEqualTo(17));
    expect(one.color, avatarColors('1').$2);
  });
}
