import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dataset.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/rate_chart.dart';

/// O licitație de obligațiuni de stat: rata (cuponul) stabilită la plasare și volumele.
class BondPoint {
  final DateTime date; // data licitației
  final int years; // termenul inițial al obligațiunii (2, 3, 5, 7, 10)
  final double rate;
  final bool floating;
  final double? announced, demand, placed;
  const BondPoint(this.date, this.years, this.rate, this.floating, this.announced, this.demand, this.placed);
}

/// Licitațiile OS cu rată publicată, grupate pe termenul inițial al ISIN-ului
/// (o redeschidere de „4,93 ani” aparține obligațiunii de 5 ani).
List<BondPoint> bondPoints(VmsDataset data) {
  int? yearsOf(String label) {
    final m = RegExp(r'(\d+)(?:[.,](\d+))?').firstMatch(label);
    if (m == null) return null;
    final v = double.parse('${m.group(1)}.${m.group(2) ?? '0'}');
    const std = [2, 3, 5, 7, 10];
    return std.firstWhere((y) => y >= v - 0.25, orElse: () => v.round());
  }

  final out = <BondPoint>[];
  for (final a in data.auctions) {
    if (a.type != 'OS' || a.rateAvg == null) continue;
    final s = data.byIsin[a.isin];
    final years = yearsOf(s?.termLabel ?? a.termLabel);
    if (years == null) continue;
    out.add(BondPoint(a.auctionDate, years, a.rateAvg!, s?.isFloating ?? false, a.announced, a.demand, a.placedNominal));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

class BondRatesSection extends StatefulWidget {
  final VmsDataset data;
  const BondRatesSection({super.key, required this.data});

  @override
  State<BondRatesSection> createState() => _BondRatesSectionState();
}

class _BondRatesSectionState extends State<BondRatesSection> {
  late final List<BondPoint> all = bondPoints(widget.data);
  late final List<int> terms = (all.map((p) => p.years).toSet().toList()..sort());
  late int term = terms.contains(3) ? 3 : (terms.isEmpty ? 0 : terms.first); // 0 = toate
  String kind = 'all'; // all | fix | flot
  int? year;

  static const _kindNames = {'all': 'Toate', 'fix': 'Dobândă fixă', 'flot': 'Flotantă'};

  bool _kindOk(BondPoint p) => kind == 'all' || (kind == 'flot') == p.floating;

  List<BondPoint> _series(int y) => all.where((p) => p.years == y && _kindOk(p) && (year == null || p.date.year == year)).toList();

  @override
  Widget build(BuildContext context) {
    if (all.isEmpty) {
      return const AppCard(child: InfoNote('Nu există încă rezultate pentru obligațiunile de stat.'));
    }
    final years = all.where(_kindOk).map((p) => p.date.year).toSet().toList()..sort();
    final shown = term == 0 ? terms : [term];
    return Column(children: [
      _latestCard(),
      const SizedBox(height: 12),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Segmented<int>(
            values: [...terms, 0],
            selected: term,
            label: (v) => v == 0 ? 'Toate' : '$v ani',
            onChanged: (v) => setState(() => term = v),
          ),
          const SizedBox(height: 8),
          Segmented<String>(
            values: const ['all', 'fix', 'flot'],
            selected: kind,
            label: (v) => _kindNames[v]!,
            onChanged: (v) => setState(() {
              kind = v;
              if (year != null && !all.any((p) => _kindOk(p) && p.date.year == year)) year = null;
            }),
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
          _chart(shown),
          if (term == 0) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 4, children: [for (final y in terms) _legend(y)]),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          _periodStats(shown.expand(_series).toList()),
        ]),
      ),
      const SizedBox(height: 12),
      const InfoNote(
        'Rata = cuponul stabilit la licitație (rata nominală anuală). La dobânda flotantă este rata primului cupon '
        '(rata medie BT 182 zile + marja). Redeschiderile sunt incluse la termenul inițial al obligațiunii. '
        'Volume în milioane lei.',
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

  Widget _legend(int y) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 3, decoration: BoxDecoration(color: AppColors.forBondYears(y), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text('$y ani', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ]);

  Widget _latestCard() {
    final last = all.last.date;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Ultima rată pe termen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('ultima licitație OS ${date(last)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final y in terms) Expanded(child: _latestTile(y)),
        ]),
      ]),
    );
  }

  Widget _latestTile(int y) {
    final s = all.where((p) => p.years == y).toList();
    if (s.isEmpty) return const SizedBox.shrink();
    final last = s.last;
    final prev = s.length > 1 ? s[s.length - 2].rate : last.rate;
    final diff = last.rate - prev;
    final up = diff > 0.004, down = diff < -0.004;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.forBondYears(y), shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$y ani', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(pct(last.rate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
      ),
      const SizedBox(height: 2),
      Text(DateFormat('MM.yyyy').format(last.date), style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Pill(
          '${up ? '▲' : down ? '▼' : '='} ${NumberFormat('0.00', 'ro').format(diff.abs())}',
          fg: up ? AppColors.green : down ? AppColors.red : AppColors.textMuted,
          bg: up ? AppColors.greenSoft : down ? AppColors.redSoft : AppColors.background,
          fontSize: 10,
        ),
      ),
    ]);
  }

  Widget _periodStats(List<BondPoint> s) {
    if (s.isEmpty) return const SizedBox.shrink();
    final v = s.map((p) => p.rate).toList();
    final avg = v.reduce((a, b) => a + b) / v.length;
    final placed = s.fold<double>(0, (t, p) => t + (p.placed ?? 0));
    final weighted = placed > 0 ? s.fold<double>(0, (t, p) => t + p.rate * (p.placed ?? 0)) / placed : null;
    final withAnn = s.where((p) => (p.announced ?? 0) > 0 && p.demand != null).toList();
    final ann = withAnn.fold<double>(0, (t, p) => t + p.announced!);
    final dem = withAnn.fold<double>(0, (t, p) => t + p.demand!);
    final cover = ann > 0 ? dem / ann : null;
    return Column(children: [
      Row(children: [
        Expanded(child: Stat('Minim', pct(v.reduce(math.min)), valueSize: 14)),
        Expanded(child: Stat('Medie', pct(avg), valueSize: 14)),
        Expanded(child: Stat('Maxim', pct(v.reduce(math.max)), valueSize: 14)),
        Expanded(child: Stat('Licitații', '${s.length}', valueSize: 14)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Stat('Medie ponderată', weighted == null ? '–' : pct(weighted), valueSize: 14)),
        Expanded(child: Stat('Plasat', milLei(placed), valueSize: 14)),
        Expanded(child: Stat('Cerere / anunțat', cover == null ? '–' : '${NumberFormat('0', 'ro').format(cover * 100)}%', valueSize: 14)),
        const Expanded(child: SizedBox.shrink()),
      ]),
    ]);
  }

  Widget _chart(List<int> shown) => ZoomableRateChart(
        key: ValueKey('os-$term-$kind-$year'),
        series: [
          for (final y in shown)
            RateSeries(AppColors.forBondYears(y), [for (final p in _series(y)) RatePoint(p.date, p.rate)]),
        ],
      );
}
