import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dataset.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/rate_chart.dart';
import 'bond_rates_section.dart';

class RatesScreen extends StatefulWidget {
  final VmsDataset data;
  const RatesScreen({super.key, required this.data});

  @override
  State<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends State<RatesScreen> {
  int term = 182; // 0 = toate
  String metric = 'avg';
  int? year;

  static const _metricNames = {'max': 'Maximă', 'avg': 'Medie', 'min': 'Minimă'};

  @override
  void initState() {
    super.initState();
    year = null; // implicit toți anii: graficul se mărește cu zoom
  }

  List<RateRecord> _series(int d) => widget.data.rates.where((r) => r.days == d && (year == null || r.date.year == year)).toList();

  @override
  Widget build(BuildContext context) {
    final rates = widget.data.rates;
    final years = rates.map((e) => e.date.year).toSet().toList()..sort();
    final terms = term == 0 ? const [91, 182, 364] : [term];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      PageHeader('Dobânzi', subtitle: 'Bonuri de trezorerie și obligațiuni · licitațiile MF 2009–2026'),
      _latestCard(),
      const SizedBox(height: 12),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Segmented<int>(
            values: const [91, 182, 364, 0],
            selected: term,
            label: (v) => v == 0 ? 'Toate' : '$v zile',
            onChanged: (v) => setState(() => term = v),
          ),
          const SizedBox(height: 8),
          Segmented<String>(
            values: const ['max', 'avg', 'min'],
            selected: metric,
            label: (v) => _metricNames[v]!,
            onChanged: (v) => setState(() => metric = v),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _yearChip(null, 'Toți anii'),
              for (final y in years.reversed) _yearChip(y, '$y'),
            ]),
          ),
          const SizedBox(height: 14),
          _chart(terms),
          if (term == 0) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 14, children: [for (final d in const [91, 182, 364]) _legend(d)]),
          ],
          if (term != 0) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            _periodStats(_series(term)),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      const InfoNote(
        'Rate nominale anuale (Regulament VMS, pct. 72). Datele sunt indexate după data emiterii. '
        'Istoricul 2009–2026 (fără bonurile de 21 de zile) a fost importat din arhiva MF și se completează automat după fiecare licitație.',
      ),
      const SectionHeader('Obligațiuni de stat'),
      BondRatesSection(data: widget.data),
    ]);
  }

  Widget _yearChip(int? y, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: year == y,
          onSelected: (_) => setState(() => year = y),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  Widget _legend(int d) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 3, decoration: BoxDecoration(color: AppColors.forTerm(d), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text('$d zile', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ]);

  Widget _latestCard() {
    final all = widget.data.rates;
    if (all.isEmpty) return const SizedBox.shrink();
    final lastDate = all.last.date;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Ultima licitație', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('emitere ${date(lastDate)} · ${_metricNames[metric]!.toLowerCase()}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final d in const [91, 182, 364]) Expanded(child: _latestTile(d)),
        ]),
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
      const SizedBox(height: 4),
      Text(pct(last), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
      const SizedBox(height: 4),
      Pill(
        '${up ? '▲' : down ? '▼' : '='} ${NumberFormat('0.00', 'ro').format(diff.abs())} p.p.',
        fg: up ? AppColors.green : down ? AppColors.red : AppColors.textMuted,
        bg: up ? AppColors.greenSoft : down ? AppColors.redSoft : AppColors.background,
        fontSize: 10.5,
      ),
    ]);
  }

  Widget _periodStats(List<RateRecord> s) {
    if (s.isEmpty) return const SizedBox.shrink();
    final v = s.map((r) => r.rate(metric)).toList();
    final avg = v.reduce((a, b) => a + b) / v.length;
    return Row(children: [
      Expanded(child: Stat('Minim perioadă', pct(v.reduce(math.min)), valueSize: 14)),
      Expanded(child: Stat('Medie perioadă', pct(avg), valueSize: 14)),
      Expanded(child: Stat('Maxim perioadă', pct(v.reduce(math.max)), valueSize: 14)),
      Expanded(child: Stat('Licitații', '${s.length}', valueSize: 14)),
    ]);
  }

  Widget _chart(List<int> terms) => ZoomableRateChart(
        key: ValueKey('bt-$term-$year'),
        series: [
          for (final d in terms)
            RateSeries(AppColors.forTerm(d), [for (final r in _series(d)) RatePoint(r.date, r.rate(metric))]),
        ],
      );
}
