import 'package:flutter/material.dart';

import '../models/dataset.dart';
import '../models/holding.dart';
import '../services/finance.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'calculator_common.dart';

/// Deschide calculatorul de vânzare pentru [holding]. Cu [editing], modifică o vânzare existentă.
/// Returnează poziția actualizată (cu vânzarea înregistrată) sau null.
Future<Holding?> openSaleScreen(BuildContext context, VmsDataset data, Holding holding, {Sale? editing}) =>
    Navigator.of(context).push<Holding>(MaterialPageRoute(builder: (_) => SaleScreen(data: data, holding: holding, editing: editing)));

class SaleScreen extends StatefulWidget {
  final VmsDataset data;
  final Holding holding;
  final Sale? editing;
  const SaleScreen({super.key, required this.data, required this.holding, this.editing});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  late final Map<TermOption, RateRef> latest = latestRates(widget.data);
  late final Holding base = widget.editing == null
      ? widget.holding
      : widget.holding.withSales(widget.holding.sales.where((x) => x.id != widget.editing!.id).toList());
  late final int available = base.remaining;
  late final double keep = holdToMaturityRate(widget.holding);
  final _qty = TextEditingController();
  final _val = TextEditingController();
  late DateTime saleDate;
  String mode = 'rate'; // rate / price

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _qty.text = '${e?.quantity ?? available}';
    saleDate = e?.date ?? _clampDate(dayOnly(DateTime.now()));
    if (e != null) {
      mode = 'price';
      _val.text = priceFmt(e.price);
    } else {
      _val.text = priceFmt(double.parse(keep.toStringAsFixed(2)));
    }
  }

  DateTime _clampDate(DateTime d) {
    final first = dayOnly(widget.holding.purchaseDate).add(const Duration(days: 1));
    final last = dayOnly(widget.holding.maturity).subtract(const Duration(days: 1));
    if (d.isBefore(first)) return first;
    if (d.isAfter(last)) return last;
    return d;
  }

  @override
  void dispose() {
    _qty.dispose();
    _val.dispose();
    super.dispose();
  }

  void _setMode(String m) {
    if (m == mode) return;
    final q = _quote();
    setState(() {
      mode = m;
      if (q != null) {
        _val.text = m == 'rate' ? priceFmt(double.parse(q.sellerRate.toStringAsFixed(2))) : priceFmt(q.price);
      }
    });
  }

  Future<void> _pickDate() async {
    final first = dayOnly(widget.holding.purchaseDate).add(const Duration(days: 1));
    final last = dayOnly(widget.holding.maturity).subtract(const Duration(days: 1));
    if (last.isBefore(first)) return;
    final d = await showDatePicker(context: context, initialDate: _clampDate(saleDate), firstDate: first, lastDate: last);
    if (d != null) setState(() => saleDate = d);
  }

  int get _quantity => int.tryParse(_qty.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// Prețul folosit: din rata dorită (rotunjit la 2 zecimale) sau scris direct.
  double? get _price {
    final v = parseNum(_val.text);
    if (v == null) return null;
    final p = mode == 'rate' ? priceForSellerRate(widget.holding, saleDate, v) : (v * 100).round() / 100;
    return p > 0 ? p : null;
  }

  SaleQuote? _quote() {
    final p = _price;
    final q = _quantity;
    if (p == null || q <= 0 || q > available) return null;
    return saleQuote(widget.holding, date: saleDate, quantity: q, price: p);
  }

  Future<void> _confirm(SaleQuote q) async {
    final h = widget.holding;
    final remainingAfter = available - _quantity;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.editing == null ? 'Confirmi vânzarea?' : 'Salvezi modificările vânzării?',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            KV('Titluri vândute', '${intFmt(_quantity)} din ${intFmt(available)}'),
            KV('Preț · data', '${priceFmt(q.price)} lei · ${date(saleDate)}'),
            if (q.accruedPerUnit > 0) KV('Dobânda acumulată', '${priceFmt(q.accruedPerUnit)} lei / titlu'),
            KV('Primești', lei(q.proceeds), strong: true),
            KV('Câștig (în venitul anului ${saleDate.year})', '${q.profit >= 0 ? '+' : '−'}${lei(q.profit.abs())}'),
            KV('Rămân în portofoliu', '${intFmt(remainingAfter)} titluri'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anulează'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmă'))),
            ]),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final sale = Sale(
      id: widget.editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      date: saleDate,
      quantity: _quantity,
      price: q.price,
    );
    Navigator.pop(context, h.withSales([...base.sales, sale]));
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.holding;
    final pal = h.isBill ? SectionPalette.bills : SectionPalette.bonds;
    final q = _quote();
    final qty = _quantity;
    final qtyError = qty <= 0 ? 'Introdu numărul de titluri' : qty > available ? 'Ai doar ${intFmt(available)} titluri' : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing == null ? 'Vinde' : 'Editează vânzarea')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TypePill(h.type),
              const SizedBox(width: 8),
              Expanded(child: Text(h.isin, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 3),
            Text(
              '${h.termLabel.isNotEmpty ? '${h.termLabel} · ' : ''}scadență ${date(h.maturity)} · '
              '${intFmt(available)} titluri · cumpărat ${date(h.purchaseDate)} la ${priceFmt(h.price)}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  editableLabel('Câte titluri vinzi', feminine: false),
                  const SizedBox(height: 6),
                  EditableField(controller: _qty, suffix: '', decimal: false, onChanged: (_) => setState(() {})),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  editableLabel('Data'),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(border: Border.all(color: AppColors.primary, width: 1.4), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Expanded(child: Text(date(saleDate), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                        const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(
                  qtyError ??
                      'din ${intFmt(available)} · îți rămân ${intFmt(available - qty)} · '
                          '${daysBetween(h.purchaseDate, saleDate)} zile deținut, ${daysBetween(saleDate, h.maturity)} rămase',
                  style: TextStyle(fontSize: 11, color: qtyError == null ? AppColors.textMuted : AppColors.red),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _qty.text = '$available'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                child: const Text('Toate'),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Segmented<String>(
              values: const ['rate', 'price'],
              selected: mode,
              label: (v) => v == 'rate' ? 'Vreau o rată' : 'Am un preț',
              onChanged: _setMode,
              palette: pal,
            ),
            const SizedBox(height: 12),
            editableLabel(mode == 'rate' ? 'Câștigul anual pe care îl vrei' : 'Prețul la care vinzi un titlu', feminine: false),
            const SizedBox(height: 6),
            EditableField(controller: _val, suffix: mode == 'rate' ? '% pe an' : 'lei', onChanged: (_) => setState(() {})),
            const SizedBox(height: 5),
            Text(
              mode == 'rate'
                  ? 'Dacă păstrezi titlul până la scadență (${date(h.maturity)}), câștigi ${pct(keep)} pe an.'
                  : 'Ai cumpărat la ${priceFmt(h.price)} lei. Valoarea nominală e 100 lei.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            if (q == null)
              const Text('Completează câmpurile ca să vezi rezultatul.', style: TextStyle(color: AppColors.textMuted))
            else
              ..._results(q),
          ]),
        ),
        if (q != null) ...[
          const SizedBox(height: 10),
          AppCard(child: _ratesCard(q)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _confirm(q),
            child: Text(widget.editing == null ? 'Marchează ca vândut' : 'Salvează modificările'),
          ),
        ],
        const SizedBox(height: 12),
        const InfoNote('$kCalcDisclaimer Tranzacțiile pe piața secundară se fac prin dealeri primari sau prin bursă.'),
      ]),
    );
  }

  List<Widget> _results(SaleQuote q) {
    final wanted = parseNum(_val.text);
    return [
      if (mode == 'rate')
        answerBox(
          top: 'Pentru un câștig de ${wanted == null ? '—' : pct(wanted)} pe an, prețul de vânzare corespunzător este',
          big: '${priceFmt(q.price)} lei',
          bottom: wanted != null && (q.sellerRate - wanted).abs() >= 0.005
              ? 'pentru fiecare titlu de 100 lei · la prețul rotunjit, rata ta este ${pct(q.sellerRate)}'
              : 'pentru fiecare titlu de 100 lei',
        )
      else
        answerBox(
          top: 'Vânzând la ${priceFmt(q.price)} lei, rata ta este',
          big: '${pct(q.sellerRate)} pe an',
          bottom: 'din ziua cumpărării până la vânzare',
          bigColor: q.sellerRate < 0 ? AppColors.red : null,
        ),
      if (q.accruedPerUnit > 0) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ResultBox('Prețul titlului', priceFmt(q.price))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('+', style: TextStyle(color: AppColors.textFaint))),
          Expanded(child: ResultBox('Dobânda acumulată', priceFmt(q.accruedPerUnit))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('=', style: TextStyle(color: AppColors.textFaint))),
          Expanded(child: ResultBox('Primești pe titlu', priceFmt(q.price + q.accruedPerUnit), color: AppColors.primary)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Dobânda acumulată = partea ta din cuponul următor, pentru zilele deja trecute. O plătește cumpărătorul, peste preț.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
      if (q.profit < 0) ...[
        const SizedBox(height: 8),
        InfoNote(
          'La acest preț, suma primită este mai mică decât suma plătită la cumpărare cu ${lei(-q.profit)}.',
          icon: Icons.warning_amber_rounded,
          color: AppColors.red,
          bg: AppColors.redSoft,
        ),
      ],
      const SizedBox(height: 8),
      resultRow([
        ResultBox('Primești în total', lei(q.proceeds)),
        ResultBox('Câștigul tău', '${q.profit >= 0 ? '+' : '−'}${lei(q.profit.abs())}', color: q.profit >= 0 ? AppColors.green : AppColors.red),
      ]),
      if (q.couponsReceived > 0) ...[
        const SizedBox(height: 4),
        Text('Include cupoanele deja încasate pentru aceste titluri: ${lei(q.couponsReceived)}.',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    ];
  }

  Widget _ratesCard(SaleQuote q) {
    final refs = comparableRates(latest, widget.holding.isBill ? 'BT' : 'OS', q.daysLeft);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      resultRow([
        _rateTile('Rata ta', q.sellerRate, '${intFmt(q.daysHeld)} zile', AppColors.primarySoft, AppColors.primary),
        _rateTile('Rata cumpărătorului', q.buyerRate, '${intFmt(q.daysLeft)} zile', SectionPalette.bonds.wash, SectionPalette.bonds.text),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rate de la licitații (informativ)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'La acest preț, rata pentru cumpărător este '),
              TextSpan(text: '${pct(q.buyerRate)} pe an', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
              TextSpan(text: ', pentru cele ${intFmt(q.daysLeft)} zile rămase.'),
            ]),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text.rich(ratesSentence(refs), style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
        ]),
      ),
    ]);
  }

  Widget _rateTile(String label, double v, String period, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(pct(v), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
          Text('pe an · $period', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ]),
      );
}
