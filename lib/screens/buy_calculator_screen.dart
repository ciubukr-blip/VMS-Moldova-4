import 'package:flutter/material.dart';

import '../models/dataset.dart';
import '../models/holding.dart';
import '../services/finance.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'calculator_common.dart';
import 'holding_form.dart';

/// Deschide calculatorul de cumpărare. [planned] = titlurile unei licitații planificate
/// (termenele lor sunt marcate și au datele reale din calendarul MF).
Future<void> openBuyCalculator(
  BuildContext context,
  VmsDataset data, {
  DateTime? auctionDay,
  List<CalendarEntry> planned = const [],
  TermOption? initial,
  ValueChanged<Holding>? onAddHolding,
}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BuyCalculatorScreen(data: data, auctionDay: auctionDay, planned: planned, initial: initial, onAddHolding: onAddHolding),
    ));

class BuyCalculatorScreen extends StatefulWidget {
  final VmsDataset data;
  final DateTime? auctionDay;
  final List<CalendarEntry> planned;
  final TermOption? initial;
  final ValueChanged<Holding>? onAddHolding;
  const BuyCalculatorScreen({super.key, required this.data, this.auctionDay, this.planned = const [], this.initial, this.onAddHolding});

  @override
  State<BuyCalculatorScreen> createState() => _BuyCalculatorScreenState();
}

class _BuyCalculatorScreenState extends State<BuyCalculatorScreen> {
  late final Map<TermOption, RateRef> latest = latestRates(widget.data);
  late final Map<TermOption, CalendarEntry> auctionTerms = {
    for (final e in widget.planned)
      if (TermOption.fromLabel(e.type, e.term) case final t?) t: e,
  };
  final _sum = TextEditingController(text: '50.000');
  final _rate = TextEditingController();
  final _osPrice = TextEditingController(text: '100,00');
  late TermOption term;
  String? rateKind = 'avg'; // avg / max / min; null = rata scrisă de utilizator

  @override
  void initState() {
    super.initState();
    term = widget.initial ?? TermOption.all.where(auctionTerms.containsKey).firstOrNull ?? const TermOption.bill(364);
    _proposeRate();
  }

  @override
  void dispose() {
    _sum.dispose();
    _rate.dispose();
    _osPrice.dispose();
    super.dispose();
  }

  void _proposeRate() {
    final ref = latest[term];
    rateKind = ref == null ? null : 'avg';
    _rate.text = ref == null ? '' : priceFmt(ref.avg);
    _osPrice.text = '100,00';
  }

  void _pickKind(String k) {
    final ref = latest[term];
    if (ref == null) return;
    final v = k == 'max' ? ref.max : k == 'min' ? ref.min : ref.avg;
    if (v == null) return;
    setState(() {
      rateKind = k;
      _rate.text = priceFmt(v);
    });
  }

  /// Datele de emitere și scadență: din calendarul MF dacă termenul e la licitația planificată.
  ({DateTime issue, DateTime maturity, bool real}) _dates() {
    final e = auctionTerms[term];
    final today = dayOnly(DateTime.now());
    final issue = e?.settlementDate ?? today;
    final mat = e?.maturity ??
        (term.isBill ? issue.add(Duration(days: term.days!)) : DateTime(issue.year + term.years!, issue.month, issue.day));
    return (issue: dayOnly(issue), maturity: dayOnly(mat), real: e != null && e.maturity != null);
  }

  @override
  Widget build(BuildContext context) {
    final d = _dates();
    final days = daysBetween(d.issue, d.maturity);
    final sum = parseAmount(_sum.text);
    final rate = parseNum(_rate.text);
    final ref = latest[term];
    return Scaffold(
      appBar: AppBar(title: const Text('Calculator')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            editableLabel('Suma'),
            const SizedBox(height: 6),
            EditableField(controller: _sum, suffix: 'lei', decimal: false, onChanged: (_) => setState(() {})),
            const SizedBox(height: 14),
            const Text('Termenul', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final t in TermOption.all) _termChip(t)]),
            if (auctionTerms.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'la licitația din ${date(widget.auctionDay ?? widget.planned.first.auctionDate)}'
                    '${auctionTerms.containsKey(term) ? '' : ' · ${term.fullLabel} nu e planificat acum'}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _dateBox('Emitere', d.issue, d.real)),
              const SizedBox(width: 6),
              Expanded(child: _dateBox('Scadență', d.maturity, d.real)),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            editableLabel(term.isBill ? 'Rata dorită (anuală)' : 'Cuponul (rata anuală)', feminine: term.isBill),
            const SizedBox(height: 6),
            EditableField(
              controller: _rate,
              suffix: '%',
              hint: ref == null ? 'introdu rata' : null,
              borderColor: ref == null && rate == null ? const Color(0xFFE2A97C) : null,
              onChanged: (_) => setState(() => rateKind = null),
            ),
            const SizedBox(height: 5),
            if (ref != null)
              Text('Propusă: rata medie la ${term.fullLabel}, licitația din ${date(ref.auctionDate)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted))
            else
              const InfoNote('Nu există licitații anterioare pe acest termen în datele aplicației. Introdu rata pe care o iei în calcul.',
                  color: AppColors.amber, bg: AppColors.amberSoft),
            if (ref != null && term.isBill) ...[
              const SizedBox(height: 8),
              Row(children: [
                for (final (k, l, v) in [('max', 'Maximă', ref.max), ('avg', 'Medie', ref.avg), ('min', 'Minimă', ref.min)])
                  if (v != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _kindChip(k, l, v),
                      ),
                    ),
              ]),
            ],
            const SizedBox(height: 10),
            if (term.isBill) _billPrice(rate, days) else _bondPrice(),
          ]),
        ),
        const SizedBox(height: 10),
        AppCard(child: term.isBill ? _billResult(sum, rate, days, d.maturity, d.real) : _bondResult(sum, rate, d.issue, d.maturity, d.real)),
        const SizedBox(height: 10),
        InfoNote(
          'Calcul informativ, după Regulamentul VMS (pct. 72–76), fără comisioane. Rata și prețul final se stabilesc la licitație '
          'și pot diferi de cele din calcul.${d.real ? '' : ' Datele de emitere și scadență sunt estimate de azi; cele reale apar în comunicatul MF.'}',
        ),
      ]),
    );
  }

  Widget _termChip(TermOption t) {
    final on = t == term;
    final p = t.isBill ? SectionPalette.bills : SectionPalette.bonds;
    final inAuction = auctionTerms.containsKey(t);
    return GestureDetector(
      onTap: () => setState(() {
        term = t;
        _proposeRate();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: on ? p.soft : AppColors.surface,
          border: Border.all(color: on ? p.line : const Color(0xFFDCE1E8)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(t.fullLabel, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? p.text : AppColors.text)),
          if (inAuction) ...[
            const SizedBox(width: 5),
            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
          ],
        ]),
      ),
    );
  }

  Widget _kindChip(String k, String label, double v) {
    final on = rateKind == k;
    return GestureDetector(
      onTap: () => _pickKind(k),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.primarySoft : const Color(0xFFF5F7FA),
          border: Border.all(color: on ? AppColors.primary : const Color(0xFFE7EAF0)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          Text(pct(v), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _dateBox(String label, DateTime d, bool real) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          border: Border.all(color: const Color(0xFFE7EAF0)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Row(children: [
            Text(date(d), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: real ? AppColors.primarySoft : AppColors.background, borderRadius: BorderRadius.circular(4)),
              child: Text(real ? 'MF' : 'estimată',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: real ? AppColors.primary : AppColors.textMuted)),
            ),
          ]),
        ]),
      );

  // ------------------------------------------------------------ BT
  Widget _billPrice(double? rate, int days) {
    final p = (rate == null || rate <= 0) ? null : billPriceRounded(rate, days);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        border: Border.all(color: const Color(0xFFC7CCD3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Preț pentru 100 lei (calculat)', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text(p == null ? '—' : '${priceFmt(p)} lei', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ]),
        ),
        Flexible(
          child: Text('100 / (1 + rata × $days / 365), rotunjit',
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ),
      ]),
    );
  }

  Widget _billResult(double sum, double? rate, int days, DateTime maturity, bool real) {
    if (rate == null || rate <= 0) return const Text('Introdu rata ca să vezi rezultatul.', style: TextStyle(color: AppColors.textMuted));
    final p = billPriceRounded(rate, days);
    final units = (sum / p).floor();
    if (units <= 0) return Text('Suma e prea mică pentru un bon (minimum ${priceFmt(p)} lei).', style: const TextStyle(color: AppColors.textMuted));
    final cost = units * p, get = units * 100.0, gain = get - cost;
    final exact = billRate(p, days);
    return Column(children: [
      answerBox(
        top: 'La scadență (${date(maturity)}${real ? '' : ', estimat'}) primești',
        big: lei(get),
        bottom: (exact - rate).abs() >= 0.005 ? 'La prețul rotunjit ${priceFmt(p)} rata exactă este ${pct(exact)}.' : null,
      ),
      const SizedBox(height: 8),
      resultRow([
        ResultBox('Titluri', intFmt(units)),
        ResultBox('Investești', intFmt(cost.round())),
        ResultBox('Câștig', '+${intFmt(gain.round())}', color: AppColors.green),
      ]),
      const SizedBox(height: 6),
      Text('Rest neinvestit: ${lei(sum - cost)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      _addButton(p, units),
    ]);
  }

  // ------------------------------------------------------------ OS
  Widget _bondPrice() {
    final p = parseNum(_osPrice.text);
    final d = p == null ? null : 100 - p;
    final (String text, Color fg, Color bg, String expl) = d == null
        ? ('—', AppColors.textMuted, AppColors.background, '')
        : d.abs() < 0.005
            ? ('la nominal', AppColors.primary, AppColors.primarySoft, 'prețul = valoarea nominală')
            : d > 0
                ? ('cu scont', AppColors.green, AppColors.greenSoft, 'plătești cu ${priceFmt(d)} lei mai puțin; la scadență primești 100')
                : ('cu primă', AppColors.red, AppColors.redSoft, 'plătești cu ${priceFmt(-d)} lei în plus; la scadență primești 100');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      editableLabel('Prețul pentru 100 lei', feminine: false),
      const SizedBox(height: 6),
      EditableField(controller: _osPrice, suffix: 'lei', onChanged: (_) => setState(() {})),
      const SizedBox(height: 6),
      Row(children: [
        Pill(text, fg: fg, bg: bg, fontSize: 10.5),
        const SizedBox(width: 8),
        Expanded(child: Text(expl, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
      ]),
    ]);
  }

  Widget _bondResult(double sum, double? rate, DateTime issue, DateTime maturity, bool real) {
    final p = parseNum(_osPrice.text);
    if (p == null || p <= 0) return const Text('Introdu prețul.', style: TextStyle(color: AppColors.textMuted));
    final units = (sum / p).floor();
    if (rate == null || rate <= 0) {
      return Column(children: [
        answerBox(top: 'Rezultatul apare după ce introduci rata', big: '— lei'),
        const SizedBox(height: 8),
        resultRow([ResultBox('Titluri', intFmt(units)), ResultBox('Investești', intFmt((units * p).round())), const ResultBox('Câștig', '—')]),
      ]);
    }
    if (units <= 0) return Text('Suma e prea mică pentru o obligațiune (minimum ${priceFmt(p)} lei).', style: const TextStyle(color: AppColors.textMuted));
    final coupons = bondCoupons(issue, maturity, rate, const []);
    final perUnit = coupons.fold<double>(0, (t, c) => t + c.amount);
    final cost = units * p, couponsTotal = units * perUnit, diff = units * (100 - p);
    final gain = couponsTotal + diff;
    final y = bondYield(p, [...coupons, CashFlow(maturity, 100, isCoupon: false)], issue);
    return Column(children: [
      answerBox(
        top: 'Până la scadență (${real ? '' : 'estimat '}${date(maturity)}) primești',
        big: lei(units * 100 + couponsTotal),
        bottom: 'nominal ${intFmt(units * 100)} + cupoane ${intFmt(couponsTotal.round())} · ${coupons.length} cupoane',
      ),
      const SizedBox(height: 8),
      resultRow([
        ResultBox('Titluri', intFmt(units)),
        ResultBox('Investești', intFmt(cost.round())),
        ResultBox('Câștig', '${gain >= 0 ? '+' : '−'}${intFmt(gain.abs().round())}', color: gain >= 0 ? AppColors.green : AppColors.red),
      ]),
      const SizedBox(height: 6),
      resultRow([
        ResultBox('Cupoane', intFmt(couponsTotal.round())),
        ResultBox(diff >= 0 ? 'Scont' : 'Primă', '${diff >= 0 ? '+' : '−'}${intFmt(diff.abs().round())}', color: diff >= 0 ? AppColors.green : AppColors.red),
        ResultBox('Randament', pct(y), color: AppColors.primary),
      ]),
      const SizedBox(height: 6),
      Text(
        'Cupon ~${lei(units * 100 * rate / 100 / 2)} la 6 luni. Randamentul (pct. 74) ține cont de preț'
        '${(100 - p).abs() < 0.005 ? '.' : (100 - p) > 0 ? ': mai mare decât cuponul.' : ': mai mic decât cuponul.'}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      ),
      _addButton(p, units),
    ]);
  }

  Widget _addButton(double price, int units) {
    final cb = widget.onAddHolding;
    if (cb == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton.icon(
        onPressed: () async {
          final h = await showHoldingForm(context, widget.data, prefillPrice: price, prefillQuantity: units);
          if (h != null) {
            cb(h);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Investiția a fost adăugată în portofoliu.')));
          }
        },
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Adaugă în portofoliu'),
      ),
    );
  }
}
