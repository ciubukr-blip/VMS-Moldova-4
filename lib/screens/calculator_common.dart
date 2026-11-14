import 'package:flutter/material.dart';

import '../models/dataset.dart';
import '../services/finance.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';

/// Un termen standard din calculator (BT în zile, OS în ani).
class TermOption {
  final String type; // BT / OS
  final int? days; // BT
  final int? years; // OS
  const TermOption.bill(int d)
      : type = 'BT',
        days = d,
        years = null;
  const TermOption.bond(int y)
      : type = 'OS',
        days = null,
        years = y;

  bool get isBill => type == 'BT';
  String get label => isBill ? '$days zile' : '$years ani';
  String get fullLabel => '$type $label';

  @override
  bool operator ==(Object other) => other is TermOption && other.type == type && other.days == days && other.years == years;

  @override
  int get hashCode => Object.hash(type, days, years);

  static const all = [
    TermOption.bill(91),
    TermOption.bill(182),
    TermOption.bill(364),
    TermOption.bond(2),
    TermOption.bond(3),
    TermOption.bond(5),
    TermOption.bond(7),
    TermOption.bond(10),
  ];

  /// Termenul standard al unei etichete („178 zile” → BT 182 zile, „4,93 ani” → OS 5 ani).
  static TermOption? fromLabel(String type, String label) {
    final m = RegExp(r'(\d+)(?:[.,](\d+))?').firstMatch(label);
    if (m == null) return null;
    final v = double.parse('${m.group(1)}.${m.group(2) ?? '0'}');
    if (type == 'BT') {
      final d = v.round();
      return TermOption.bill(d <= 120 ? 91 : d <= 250 ? 182 : 364);
    }
    const std = [2, 3, 5, 7, 10];
    return TermOption.bond(std.firstWhere((y) => y >= v - 0.25, orElse: () => v.round()));
  }
}

/// Rata de la ultima licitație pentru un termen (rate medii, minime și maxime acceptate).
class RateRef {
  final TermOption term;
  final DateTime auctionDate;
  final double avg;
  final double? min, max;
  const RateRef(this.term, this.auctionDate, this.avg, this.min, this.max);
}

/// Ultima licitație cu rezultate pentru fiecare termen standard.
Map<TermOption, RateRef> latestRates(VmsDataset data) {
  final out = <TermOption, RateRef>{};
  for (final a in data.auctions) {
    if (a.rateAvg == null) continue;
    final t = TermOption.fromLabel(a.type, a.type == 'OS' ? (data.byIsin[a.isin]?.termLabel ?? a.termLabel) : a.termLabel);
    if (t == null || !TermOption.all.contains(t)) continue;
    final prev = out[t];
    if (prev == null || !a.auctionDate.isBefore(prev.auctionDate)) {
      out[t] = RateRef(t, a.auctionDate, a.rateAvg!, a.rateMin, a.rateMax);
    }
  }
  return out;
}

/// Ratele de la licitații cu care se compară rata cumpărătorului: termenul potrivit
/// zilelor rămase sau, dacă rămân între două termene, cele două termene vecine.
List<RateRef> comparableRates(Map<TermOption, RateRef> latest, String type, int daysLeft) {
  final list = latest.values.where((r) => r.term.type == type).toList()
    ..sort((a, b) => _termDays(a.term).compareTo(_termDays(b.term)));
  if (list.isEmpty) return const [];
  final tol = type == 'BT' ? 10 : 90;
  for (final r in list) {
    if ((_termDays(r.term) - daysLeft).abs() <= tol) return [r];
  }
  if (daysLeft < _termDays(list.first.term)) return [list.first];
  if (daysLeft > _termDays(list.last.term)) return [list.last];
  for (var i = 0; i + 1 < list.length; i++) {
    if (_termDays(list[i].term) < daysLeft && daysLeft < _termDays(list[i + 1].term)) return [list[i], list[i + 1]];
  }
  return [list.last];
}

int _termDays(TermOption t) => t.isBill ? t.days! : t.years! * 365;

/// Textul „Ultima licitație, 03.11.2026, rate medii: BT 91 zile 3,15% · BT 182 zile 11,63%.”
InlineSpan ratesSentence(List<RateRef> refs) {
  if (refs.isEmpty) return const TextSpan(text: 'Nu există rezultate de licitații pentru termene comparabile.');
  final sameDay = refs.every((r) => r.auctionDate == refs.first.auctionDate);
  return TextSpan(children: [
    TextSpan(text: sameDay ? 'Ultima licitație, ${date(refs.first.auctionDate)}, rate medii: ' : 'Ultimele licitații, rate medii: '),
    for (final (i, r) in refs.indexed) ...[
      if (i > 0) const TextSpan(text: ' · '),
      TextSpan(text: '${r.term.fullLabel} '),
      TextSpan(text: pct(r.avg), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
      if (!sameDay) TextSpan(text: ' (${date(r.auctionDate)})'),
    ],
    const TextSpan(text: '.'),
  ]);
}

/// Eticheta unui câmp editabil: „Rata dorită (anuală) · editabilă”.
Widget editableLabel(String text, {bool feminine = true}) => Text.rich(
      TextSpan(children: [
        TextSpan(text: '$text · '),
        TextSpan(text: feminine ? 'editabilă' : 'editabil', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
      ]),
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
    );

/// Câmp numeric editabil, cu chenar albastru și creion.
class EditableField extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;
  final String? hint;
  final ValueChanged<String> onChanged;
  final bool decimal;
  final Color? borderColor;
  const EditableField({
    super.key,
    required this.controller,
    required this.suffix,
    required this.onChanged,
    this.hint,
    this.decimal = true,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: borderColor ?? AppColors.primary, width: 1.4),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textFaint),
        filled: true,
        fillColor: AppColors.surface,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: borderColor ?? AppColors.primary, width: 2)),
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(suffix, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          const SizedBox(width: 6),
          Icon(Icons.edit_outlined, size: 17, color: borderColor ?? AppColors.primary),
          const SizedBox(width: 10),
        ]),
      ),
    );
  }
}

/// O cifră centrată într-o căsuță (rezultatele calculatoarelor).
class ResultBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const ResultBox(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE3E8F0)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? AppColors.text)),
          ),
        ]),
      );
}

Widget resultRow(List<Widget> boxes) => IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, b) in boxes.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: b),
        ],
      ]),
    );

/// Caseta albastră cu răspunsul principal.
Widget answerBox({required String top, required String big, String? bottom, Color? bigColor}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text(top, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(big, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: bigColor ?? AppColors.text)),
        ),
        if (bottom != null) ...[
          const SizedBox(height: 2),
          Text(bottom, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ],
      ]),
    );

/// Nota fixă de la finalul calculatoarelor.
const kCalcDisclaimer = 'Calcul informativ, după formulele din Regulamentul VMS (pct. 72–76), fără comisioane. '
    'Nu este o recomandare și nu garantează prețul sau existența unui cumpărător.';

/// O sumă în lei scrisă cu sau fără separatoare de mii („50.000”, „50 000”); fără zecimale.
double parseAmount(String s) => double.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Parsează un număr scris cu virgulă sau punct; null dacă nu e valid.
double? parseNum(String s) => parseDecimal(s);

/// Diferența în zile, folosită de calculatoare.
int calcDays(DateTime a, DateTime b) => daysBetween(a, b);
