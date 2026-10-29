import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _thousands = NumberFormat.decimalPattern('pt_BR');

/// Máscara de valor em reais enquanto se digita: "1" → "1,00", "1112" → "1.112,00".
///
/// Os números digitados formam a parte inteira e o ",00" já aparece preenchido. Para os centavos,
/// digita-se a vírgula: o cursor passa para depois dela e cada dígito substitui o "00" da esquerda
/// para a direita ("1.112," + "5" → "1.112,50"). Apagar a vírgula só move o cursor de volta.
/// O texto resultante é lido por `parseBRLToCents`.
class BrlInputFormatter extends TextInputFormatter {
  BrlInputFormatter({this.allowNegative = false, this.maxIntegerDigits = 13});
  final bool allowNegative;
  final int maxIntegerDigits;

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String formatInteger(String digits) {
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return trimmed.isEmpty ? '' : _thousands.format(int.parse(trimmed));
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    var cursor = newValue.selection.baseOffset.clamp(0, text.length);
    final negative = allowNegative && text.trimLeft().startsWith('-');

    // Apagou a vírgula (backspace logo depois dela): mantém o valor e só recua o cursor.
    if (oldValue.text.contains(',') && !text.contains(',') && text.length == oldValue.text.length - 1) {
      final comma = oldValue.text.indexOf(',');
      return oldValue.copyWith(selection: TextSelection.collapsed(offset: comma));
    }

    final comma = text.indexOf(',');
    final intRaw = comma < 0 ? text : text.substring(0, comma);
    final decRaw = comma < 0 ? '' : text.substring(comma + 1);
    var intDigits = _digits(intRaw);
    if (intDigits.length > maxIntegerDigits) intDigits = intDigits.substring(0, maxIntegerDigits);
    final decDigits = _digits(decRaw);

    // Começou pela vírgula: "0,00" com o cursor nos centavos.
    if (intDigits.isEmpty && decDigits.isEmpty && comma >= 0 && _digits(oldValue.text).isEmpty) {
      final prefix = negative ? '-' : '';
      return TextEditingValue(
        text: '${prefix}0,00',
        selection: TextSelection.collapsed(offset: prefix.length + 2),
      );
    }

    if (intDigits.isEmpty && (decDigits.isEmpty || int.parse(decDigits.padRight(1, '0')) == 0)) {
      // Campo vazio (ou só "-"): deixa limpar o valor.
      final empty = negative && text.trim() == '-' ? '-' : '';
      return TextEditingValue(
        text: empty,
        selection: TextSelection.collapsed(offset: empty.length),
      );
    }

    final intPart = formatInteger(intDigits.isEmpty ? '0' : intDigits);
    final dec = (decDigits.length >= 2 ? decDigits.substring(0, 2) : decDigits.padRight(2, '0'));
    final prefix = negative ? '-' : '';
    final result = '$prefix$intPart,$dec';
    final newComma = prefix.length + intPart.length;

    int offset;
    if (comma >= 0 && cursor > comma) {
      // Editando os centavos: mantém o cursor depois dos dígitos já digitados (máx. 2).
      final typed = _digits(text.substring(comma + 1, cursor)).length.clamp(0, 2);
      offset = newComma + 1 + typed;
    } else {
      // Editando a parte inteira: preserva quantos dígitos ficam à direita do cursor.
      final digitsAfter = _digits(intRaw.substring(cursor.clamp(0, intRaw.length))).length;
      offset = newComma;
      var remaining = digitsAfter;
      while (remaining > 0 && offset > prefix.length) {
        offset--;
        if (RegExp(r'\d').hasMatch(result[offset])) remaining--;
      }
    }
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: offset.clamp(0, result.length)),
    );
  }
}
