import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.00', 'ro');
final _int = NumberFormat('#,##0', 'ro');
final _pct = NumberFormat('0.00', 'ro');
final _price = NumberFormat('0.00##', 'ro');
final dateFmt = DateFormat('dd.MM.yyyy');
final shortDate = DateFormat('dd.MM.yy');

String money(double v) => _money.format(v);
String lei(double v) => '${_money.format(v)} lei';
String intFmt(num v) => _int.format(v);
String pct(double v) => '${_pct.format(v)}%';
String priceFmt(double v) => _price.format(v);
String date(DateTime d) => dateFmt.format(d);

/// Volume MF sunt publicate în mii lei; le afișăm în milioane.
String milLei(double miiLei) => '${NumberFormat('#,##0.0', 'ro').format(miiLei / 1000)} mil.';

/// Acceptă atât 97,52 cât și 97.52 (și separatoare de mii cu spațiu).
double? parseDecimal(String? s) {
  if (s == null) return null;
  var t = s.trim().replaceAll(' ', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',') && t.contains('.')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', '.');
  }
  return double.tryParse(t);
}

String monthYear(DateTime d) {
  const m = ['ianuarie', 'februarie', 'martie', 'aprilie', 'mai', 'iunie', 'iulie', 'august', 'septembrie', 'octombrie', 'noiembrie', 'decembrie'];
  return '${m[d.month - 1][0].toUpperCase()}${m[d.month - 1].substring(1)} ${d.year}';
}

String shortMonth(DateTime d) {
  const m = ['ian', 'feb', 'mar', 'apr', 'mai', 'iun', 'iul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  return m[d.month - 1];
}

String weekdayName(DateTime d) {
  const w = ['luni', 'marți', 'miercuri', 'joi', 'vineri', 'sâmbătă', 'duminică'];
  return w[d.weekday - 1];
}
