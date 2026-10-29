import 'package:flutter_test/flutter_test.dart';
import 'package:hoink/core/money.dart';

void main() {
  group('parseBRLToCents', () {
    final cases = {
      '350': 35000,
      '350,00': 35000,
      '1.234,56': 123456,
      'R\$ 287,5': 28750,
      '1234.56': 123456,
      '-10,01': -1001,
    };
    cases.forEach((input, expected) => test('$input → $expected', () => expect(parseBRLToCents(input), expected)));
    for (final bad in ['', 'abc', '1,234', '1.2.3']) {
      test('rejeita "$bad"', () => expect(parseBRLToCents(bad), isNull));
    }
  });

  test('formatBRL usa padrão brasileiro e sinal', () {
    expect(formatBRL(35000), 'R\$ 350,00');
    expect(formatBRL(123456789), 'R\$ 1.234.567,89');
    expect(formatBRL(-28750), '-R\$ 287,50');
    expect(formatBRL(100, signed: true), '+R\$ 1,00');
  });
}
