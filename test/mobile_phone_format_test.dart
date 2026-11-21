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

  group('a name that is only the number', () {
    const masked = {'wa_id': '919724105194', 'display_wa_id': '••••••••5194'};

    test('is masked as the number is, however it is written', () {
      for (final name in [
        '919724105194',
        '+91 97241 05194',
        '9724105194',
        '+91-97241-05194',
        '(91) 9724105194',
      ]) {
        expect(customerName(name, masked), '••••••••5194', reason: name);
      }
    });

    test('a real name, or another number, is left alone', () {
      expect(customerName('Priya', masked), 'Priya');
      expect(customerName('Room 12', masked), 'Room 12');
      expect(customerName('9123456789', masked), '9123456789');
    });

    test('a viewer allowed the full number sees the name as saved', () {
      const whole = {'wa_id': '919724105194', 'display_wa_id': '919724105194'};
      expect(customerName('919724105194', whole), '919724105194');
    });

    test('a call masks it by the viewer\'s rule', () {
      const call = {'phone': '9724105194', 'profile_name': '9724105194'};
      String rule(Object? raw) => maskNumber(raw, {
        'enabled': true,
        'position': 2,
        'count': 4,
        'mask_char': '•',
      });
      expect(customerName(call['profile_name'], call, rule), '••••••5194');
      expect(customerLabel(call, rule), '••••••5194');
    });

    test('a customer with no name is titled by the masked number', () {
      expect(customerLabel({...masked, 'profile_name': ''}), '••••••••5194');
      expect(customerLabel({...masked, 'profile_name': 'Priya'}), 'Priya');
    });
  });
}
