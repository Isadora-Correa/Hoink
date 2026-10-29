import 'package:intl/intl.dart';

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String isoMonth(DateTime d) => DateFormat('yyyy-MM').format(d);
DateTime parseIso(String s) => DateTime.parse(s);

String formatShortDate(String iso) => DateFormat("dd MMM yyyy", 'pt_BR').format(parseIso(iso));
String formatDayMonth(String iso) => DateFormat("dd 'de' MMMM", 'pt_BR').format(parseIso(iso));
String formatBrDate(String iso) => DateFormat('dd/MM/yyyy').format(parseIso(iso));

String monthLabel(String month) {
  final s = DateFormat('MMMM yyyy', 'pt_BR').format(DateTime.parse('$month-01'));
  return s[0].toUpperCase() + s.substring(1);
}

String monthShort(String month) {
  final s = DateFormat('MMM', 'pt_BR').format(DateTime.parse('$month-01')).replaceAll('.', '');
  return s[0].toUpperCase() + s.substring(1);
}

String shiftMonth(String month, int delta) {
  final d = DateTime.parse('$month-01');
  return isoMonth(DateTime(d.year, d.month + delta, 1));
}
