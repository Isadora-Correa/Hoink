import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoink/core/money.dart';
import 'package:hoink/core/money_input.dart';

/// Simula a digitação: cada tecla é inserida na posição do cursor (ou apaga com '<').
TextEditingValue type(String keys, {TextEditingValue? start, bool negative = false}) {
  final f = BrlInputFormatter(allowNegative: negative);
  var v = start ?? TextEditingValue.empty;
  for (final k in keys.split('')) {
    final c = v.selection.baseOffset < 0 ? v.text.length : v.selection.baseOffset;
    final TextEditingValue next;
    if (k == '<') {
      if (c == 0) continue;
      next = TextEditingValue(
        text: v.text.substring(0, c - 1) + v.text.substring(c),
        selection: TextSelection.collapsed(offset: c - 1),
      );
    } else {
      next = TextEditingValue(
        text: v.text.substring(0, c) + k + v.text.substring(c),
        selection: TextSelection.collapsed(offset: c + 1),
      );
    }
    v = f.formatEditUpdate(v, next);
  }
  return v;
}

void main() {
  test('digitar 1 mostra 1,00 e o cursor fica antes da vírgula', () {
    final v = type('1');
    expect(v.text, '1,00');
    expect(v.selection.baseOffset, 1);
  });

  test('números vão compondo os reais com separador de milhar', () {
    expect(type('1112').text, '1.112,00');
    expect(type('1234567').text, '1.234.567,00');
    expect(parseBRLToCents(type('1112').text), 111200);
  });

  test('vírgula leva aos centavos, que substituem o 00', () {
    expect(type('350,5').text, '350,50');
    expect(type('350,57').text, '350,57');
    expect(type('350,579').text, '350,57');
    expect(parseBRLToCents(type('350,57').text), 35057);
    expect(type(',5').text, '0,50');
  });

  test('apagar: centavos, vírgula (só move o cursor) e reais', () {
    expect(type('12,34<').text, '12,30');
    final noComma = type('12,34<<<');
    expect(noComma.text, '12,00');
    expect(noComma.selection.baseOffset, 2);
    expect(type('1234<').text, '123,00');
    expect(type('1<').text, '');
  });

  test('valor negativo quando permitido (saldo de conta)', () {
    expect(type('-25', negative: true).text, '-25,00');
    expect(type('-25').text, '25,00');
  });
}
