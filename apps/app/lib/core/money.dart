import 'package:intl/intl.dart';

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$', decimalDigits: 2);
final _number = NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: 2);

/// Todos os valores trafegam em centavos inteiros; nunca usamos double para dinheiro,
/// exceto na exibição final.
/// Modo privacidade ("olhinho"): todo valor formatado para exibição vira "R$ ••••••".
/// Campos de edição usam [formatAmount] e não são afetados.
abstract final class Privacy {
  static bool hidden = false;
  static const mask = 'R\$ ••••••';
}

String formatBRL(int cents, {bool signed = false}) {
  if (Privacy.hidden) return Privacy.mask;
  final abs = _brl.format(cents.abs() / 100).replaceAll(' ', ' ');
  if (cents < 0) return '-$abs';
  if (signed && cents > 0) return '+$abs';
  return abs;
}

/// Somente o número, sem o prefixo "R$" (o prefixo é exibido menor, conforme o design system).
String formatAmount(int cents) => _number.format(cents.abs() / 100);

/// Converte "1.234,56", "350", "287,5" em centavos. Retorna null quando inválido.
int? parseBRLToCents(String input) {
  var s = input.replaceAll(RegExp(r'[R$\s]'), '');
  if (s.isEmpty) return null;
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (match == null) return null;
  final intPart = int.parse(match.group(2)!);
  final frac = int.parse((match.group(3) ?? '').padRight(2, '0'));
  final cents = intPart * 100 + frac;
  return match.group(1) == '-' ? -cents : cents;
}

String formatPercentBps(int bps) =>
    '${NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: 1).format(bps / 100)}%';
