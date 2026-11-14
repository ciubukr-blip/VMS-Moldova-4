import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dataset.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/rate_chart.dart';
import 'bond_rates_section.dart';

const _billsNote = 'Bonuri de trezorerie: rate nominale anuale (Regulament VMS, pct. 72). Datele sunt indexate după data emiterii. '
    'Istoricul 2009–2026 (fără bonurile de 21 de zile) a fost importat din arhiva MF și se completează automat după fiecare licitație. '
    'Volumele (plasat, cerere, anunțat) provin din rezultatele licitațiilor, în milioane lei.';

class RatesScreen extends StatefulWidget {
  final VmsDataset data;
  const RatesScreen({super.key, required this.data});

  @override
  State<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends State<RatesScreen> {
  static const _prefKey = 'rates_section';
  bool bonds = false; // false = BT, true = OS

  @override
  void initState() {
    super.initState();
    _restoreSection();
  }

  Future<void> _restoreSection() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getString(_prefKey) == 'OS';
      if (mounted && v != bonds) setState(() => bonds = v);
    } catch (_) {}
  }

  Future<void> _setSection(bool v) async {
    if (v == bonds) return;
    setState(() => bonds = v);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, v ? 'OS' : 'BT');
    } catch (_) {}
  }

  void _showInfo() => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Despre date', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 12),
              InfoNote(_billsNote),
              SizedBox(height: 10),
              InfoNote(kBondsNote),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      PageHeader(
        'Dobânzi',
        subtitle: 'Licitațiile MF 2009–2026',
        trailing: IconButton(
          onPressed: _showInfo,
          tooltip: 'Despre date',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.info_outline, size: 20, color: AppColors.textMuted),
        ),
      ),
      SectionSwitch(bonds: bonds, onChanged: _setSection),
      const SizedBox(height: 10),
      // Ambele secțiuni își păstrează selecțiile când comuți între ele.
      Visibility(visible: !bonds, maintainState: true, child: BillRatesSection(data: widget.data)),
      Visibility(visible: bonds, maintainState: true, child: BondRatesSection(data: widget.data)),
    ]);
  }
}

/// Secțiunea bonurilor de trezorerie: ultimele rate, grafic și statistici.
class BillRatesSection extends StatefulWidget {
  final VmsDataset data;
  const BillRatesSection({super.key, required this.data});

  @override
  State<BillRatesSection> createState() => _BillRatesSectionState();
}

class _BillRatesSectionState extends State<BillRatesSection> {
  static const _p = SectionPalette.bills;
  static const _metricNames = {'max': 'Maximă', 'avg': 'Medie', 'min': 'Minimă'};

  int term = 182; // 0 = toate
  String metric = 'avg';
  int? year; // implicit toți anii: graficul se mărește cu zoom

  List<RateRecord> _series(int d) => widget.data.rates.where((r) => r.days == d && (year == null || r.date.year == year)).toList();

  /// Termenul standard (91 / 182 / 364) al unei licitații BT, din eticheta „178 zile” etc.
  static int? _bucket(String label) {
    final m = RegExp(r'(\d+)').firstMatch(label);
    if (m == null) return null;
    final d = int.parse(m.group(1)!);
    return d <= 120 ? 91 : d <= 250 ? 182 : 364;
  }

  List<AuctionResult> _auctions(List<int> terms) => widget.data.auctions.where((a) {
        if (a.type != 'BT') return false;
        final b = _bucket(a.termLabel);
        if (b == null || !terms.contains(b)) return false;
        return year == null || (a.settlementDate ?? a.auctionDate).year == year;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final rates = widget.data.rates;
    if (rates.isEmpty) return const AppCard(child: InfoNote('Nu există încă rate pentru bonurile de trezorerie.'));
    final years = rates.map((e) => e.date.year).toSet().toList()..sort();
    final terms = term == 0 ? const [91, 182, 364] : [term];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _latestCard(),
      const SizedBox(height: 10),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Segmented<int>(
            values: const [91, 182, 364, 0],
            selected: term,
            label: (v) => v == 0 ? 'Toate' : '$v zile',
            onChanged: (v) => setState(() => term = v),
            palette: _p,
          ),
          const SizedBox(height: 4),
          UnderlineTabs<String>(
            values: const ['max', 'avg', 'min'],
            selected: metric,
            label: (v) => _metricNames[v]!,
            onChanged: (v) => setState(() => metric = v),
            palette: _p,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              YearChip('Toți anii', selected: year == null, onTap: () => setState(() => year = null), palette: _p),
              for (final y in years.reversed) YearChip('$y', selected: year == y, onTap: () => setState(() => year = y), palette: _p),
            ]),
          ),
          const SizedBox(height: 10),
          _chart(terms),
          if (term == 0) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 14, children: [for (final d in const [91, 182, 364]) _legend(d)]),
          ],
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _periodStats(terms.expand(_series).toList(), _auctions(terms)),
        ]),
      ),
    ]);
  }

  Widget _legend(int d) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 3, decoration: BoxDecoration(color: AppColors.forTerm(d), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text('$d zile', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ]);

  Widget _latestCard() {
    final lastDate = widget.data.rates.last.date;
    return BandCard(
      palette: _p,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ultima licitație · emitere ${date(lastDate)} · ${_metricNames[metric]!.toLowerCase()}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Row(children: [for (final d in const [91, 182, 364]) Expanded(child: _latestTile(d))]),
      ]),
    );
  }

  Widget _latestTile(int d) {
    final s = widget.data.rates.where((r) => r.days == d).toList();
    if (s.isEmpty) return const SizedBox.shrink();
    final last = s.last.rate(metric);
    final prev = s.length > 1 ? s[s.length - 2].rate(metric) : last;
    final diff = last - prev;
    final up = diff > 0.004, down = diff < -0.004;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.forTerm(d), shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$d zile', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 2),
      Text(pct(last), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
      const SizedBox(height: 3),
      Pill(
        '${up ? '▲' : down ? '▼' : '='} ${NumberFormat('0.00', 'ro').format(diff.abs())} p.p.',
        fg: up ? AppColors.green : down ? AppColors.red : AppColors.textMuted,
        bg: up ? AppColors.greenSoft : down ? AppColors.redSoft : AppColors.background,
        fontSize: 10,
      ),
    ]);
  }

  Widget _periodStats(List<RateRecord> s, List<AuctionResult> auctions) {
    if (s.isEmpty) return const SizedBox.shrink();
    final v = s.map((r) => r.rate(metric)).toList();
    final avg = v.reduce((a, b) => a + b) / v.length;
    final withVol = auctions.where((a) => (a.placedNominal ?? 0) > 0 && a.rateAvg != null).toList();
    final placed = withVol.fold<double>(0, (t, a) => t + a.placedNominal!);
    final weighted = placed > 0 ? withVol.fold<double>(0, (t, a) => t + a.rateAvg! * a.placedNominal!) / placed : null;
    final withAnn = auctions.where((a) => (a.announced ?? 0) > 0 && a.demand != null).toList();
    final ann = withAnn.fold<double>(0, (t, a) => t + a.announced!);
    final dem = withAnn.fold<double>(0, (t, a) => t + a.demand!);
    final cover = ann > 0 ? dem / ann : null;
    return Column(children: [
      Row(children: [
        Expanded(child: Stat('Minim', pct(v.reduce(math.min)), valueSize: 14)),
        Expanded(child: Stat('Medie', pct(avg), valueSize: 14)),
        Expanded(child: Stat('Maxim', pct(v.reduce(math.max)), valueSize: 14)),
        Expanded(child: Stat('Licitații', '${s.length}', valueSize: 14)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Stat('Medie ponderată', weighted == null ? '–' : pct(weighted), valueSize: 14)),
        Expanded(child: Stat('Plasat', placed > 0 ? milLei(placed) : '–', valueSize: 14)),
        Expanded(child: Stat('Cerere / anunțat', cover == null ? '–' : '${NumberFormat('0', 'ro').format(cover * 100)}%', valueSize: 14)),
        const Expanded(child: SizedBox.shrink()),
      ]),
    ]);
  }

  Widget _chart(List<int> terms) => ZoomableRateChart(
        key: ValueKey('bt-$term-$year'),
        height: kRatesChartHeight,
        series: [
          for (final d in terms) RateSeries(AppColors.forTerm(d), [for (final r in _series(d)) RatePoint(r.date, r.rate(metric))]),
        ],
      );
}
