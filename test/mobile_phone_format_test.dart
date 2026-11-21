import 'package:flutter_test/flutter_test.dart';
import 'package:telvox_chat_mobile_app/mobile/models.dart';

void main() {
  test('a real number is laid out for reading', () {
    expect(formatPhone('919876543210'), '+91 98765 43210');
    expect(formatPhone('14155550123'), '+14155550123');
  });

  test(
    'a masked number keeps its mask, never shrinking to its last digits',
    () {
      expect(formatPhone('••••••••3210'), '••••••••3210');
      expect(formatPhone('91••••••3210'), '91••••••3210');
      expect(formatPhone('9198••••••••'), '9198••••••••');
      expect(formatPhone('******3210'), '******3210');
    },
  );

  test('nothing to show stays empty', () {
    expect(formatPhone(null), '');
    expect(formatPhone(''), '');
  });

  test('a call\'s raw number is masked by the viewer\'s rule', () {
    const last = {'enabled': true, 'position': 2, 'count': 4, 'mask_char': '•'};
    expect(maskNumber('9876543210', last), '••••••3210');
    expect(maskNumber('9876543210', {...last, 'position': 1}), '9876••••••');
    expect(maskNumber('9876543210', {...last, 'position': 3}), '98••••••10');
    // Masking an already masked number changes nothing.
    expect(maskNumber('••••••3210', last), '••••••3210');
  });

  test('a viewer allowed the full number sees it whole', () {
    expect(
      maskNumber('9876543210', {'enabled': false, 'count': 4}),
      '9876543210',
    );
    expect(maskNumber('9876543210', null), '9876543210');
  });
}
