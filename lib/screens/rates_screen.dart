import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dataset.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

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
    year = widget.data.rates.isEmpty ? null : widget.data.rates.last.date.year;
  }

  List<RateRecord> _series(int d) => widget.data.rates.where((r) => r.days == d && (year == null || r.date.year == year)).toList();

  @override
  Widget build(BuildContext context) {
    final rates = widget.data.rates;
    final years = rates.map((e) => e.date.year).toSet().toList()..sort();
    final terms = term == 0 ? const [91, 182, 364] : [term];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      PageHeader('Dobânzi', subtitle: 'Bonuri de trezorerie · rate la licitațiile MF'),
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
        'Istoricul 2021–2026 a fost importat din arhivă și se completează automat după fiecare licitație.',
      ),
      const SectionHeader('Obligațiuni de stat'),
      const AppCard(
        child: InfoNote('Pentru obligațiuni (2, 3, 5, 7, 10 ani) rata cuponului se vede la fiecare ISIN în Portofoliu și în rezultatele licitațiilor. '
            'Graficul istoric pentru obligațiuni va fi adăugat după importul complet al arhivei.'),
      ),
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

  Widget _chart(List<int> terms) {
    final series = {for (final d in terms) d: _series(d)}..removeWhere((_, v) => v.isEmpty);
    if (series.isEmpty) {
      return const SizedBox(height: 220, child: Center(child: Text('Nu există date pentru selecție.', style: TextStyle(color: AppColors.textMuted))));
    }
    final pts = series.values.expand((e) => e).toList();
    final xs = pts.map((r) => r.date.millisecondsSinceEpoch.toDouble());
    final ys = pts.map((r) => r.rate(metric));
    final start = xs.reduce(math.min), end0 = xs.reduce(math.max);
    final end = end0 == start ? start + 86400000.0 : end0;
    final lo = ys.reduce(math.min), hi = ys.reduce(math.max);
    final range = hi - lo;
    final step = range <= 3 ? 1.0 : range <= 8 ? 2.0 : range <= 16 ? 4.0 : 5.0;
    final minY = math.max(0.0, ((lo - step * 0.3) / step).floorToDouble() * step);
    final maxY = ((hi + step * 0.3) / step).ceilToDouble() * step;
    final single = series.length == 1;
    final lastRate = single ? series.values.first.last.rate(metric) : null;
    final lastColor = single ? AppColors.forTerm(series.keys.first) : AppColors.primary;
    final dateLabel = year == null ? DateFormat('yyyy') : DateFormat('MM.yy');

    return SizedBox(
      height: 230,
      child: LineChart(
        LineChartData(
          minX: start,
          maxX: end,
          minY: minY,
          maxY: maxY,
          clipData: FlClipData.all(),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.text,
              tooltipRoundedRadius: 10,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => spots.map((s) {
                final d = DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
                final first = s == spots.first;
                return LineTooltipItem(
                  '${first ? '${date(d)}\n' : ''}${pct(s.y)}',
                  TextStyle(color: s.bar.color ?? Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            for (final e in series.entries)
              LineChartBarData(
                spots: [for (final r in e.value) FlSpot(r.date.millisecondsSinceEpoch.toDouble(), r.rate(metric))],
                color: AppColors.forTerm(e.key),
                barWidth: 2,
                isCurved: false,
                dotData: FlDotData(
                  show: single,
                  checkToShowDot: (spot, bar) => spot == bar.spots.last,
                  getDotPainter: (spot, p, bar, i) => FlDotCirclePainter(radius: 3.5, color: bar.color ?? AppColors.primary, strokeWidth: 2, strokeColor: Colors.white),
                ),
                belowBarData: BarAreaData(
                  show: single,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.forTerm(e.key).withValues(alpha: 0.14), AppColors.forTerm(e.key).withValues(alpha: 0.0)],
                  ),
                ),
              ),
          ],
          extraLinesData: ExtraLinesData(horizontalLines: [
            if (lastRate != null)
              HorizontalLine(
                y: lastRate,
                color: lastColor.withValues(alpha: 0.45),
                strokeWidth: 1,
                dashArray: const [3, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.only(left: 2, bottom: 2),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: lastColor),
                  labelResolver: (l) => 'ultima: ${pct(l.y)}',
                ),
              ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: step,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 4,
                  child: Text('${v.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: math.max(86400000.0, (end - start) / 4),
                getTitlesWidget: (v, meta) {
                  if (v == meta.max && v != meta.min) return const SizedBox.shrink();
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    space: 6,
                    child: Text(dateLabel.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())),
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) => FlLine(color: AppColors.divider, strokeWidth: 1),
          ),
        ),
      ),
    );
  }
}
