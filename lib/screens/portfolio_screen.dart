import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dataset.dart';
import '../models/holding.dart';
import '../services/finance.dart';
import '../services/format.dart';
import '../services/portfolio_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'holding_form.dart';

class PortfolioScreen extends StatefulWidget {
  final VmsDataset data;
  final List<Holding> holdings;
  final ValueChanged<Holding> onSave; // adăugare sau editare (după id)
  final ValueChanged<Holding> onDelete;
  final ValueChanged<List<Holding>> onReplaceAll;

  const PortfolioScreen({
    super.key,
    required this.data,
    required this.holdings,
    required this.onSave,
    required this.onDelete,
    required this.onReplaceAll,
  });

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  bool showActive = true;

  Future<void> _add() async {
    final h = await showHoldingForm(context, widget.data);
    if (h != null) widget.onSave(h);
  }

  Future<void> _edit(Holding h) async {
    final updated = await showHoldingForm(context, widget.data, initial: h);
    if (updated != null) widget.onSave(updated);
  }

  Future<void> _delete(Holding h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ștergi investiția?'),
        content: Text('${h.isin} · ${intFmt(h.quantity)} unități'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Șterge')),
        ],
      ),
    );
    if (ok == true) widget.onDelete(h);
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: PortfolioStore.encode(widget.holdings)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Portofoliul a fost copiat. Lipește-l într-un e-mail sau notiță ca backup.'),
    ));
  }

  Future<void> _import() async {
    final clip = await Clipboard.getData('text/plain');
    if (!mounted) return;
    List<Holding> list;
    try {
      list = PortfolioStore.decode(clip?.text ?? '');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard-ul nu conține un export VMS Moldova valid.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Importă portofoliul?'),
        content: Text('${list.length} poziții vor înlocui portofoliul curent (${widget.holdings.length} poziții).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Înlocuiește')),
        ],
      ),
    );
    if (ok == true) widget.onReplaceAll(list);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = widget.holdings.where((h) => !h.isMatured(now)).toList()..sort((a, b) => a.maturity.compareTo(b.maturity));
    final closed = widget.holdings.where((h) => h.isMatured(now)).toList()..sort((a, b) => b.maturity.compareTo(a.maturity));
    final shown = showActive ? active : closed;
    final sum = summarize(active);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      PageHeader(
        'Portofoliu',
        subtitle: 'Salvat doar pe acest telefon',
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz, color: AppColors.textMuted),
          onSelected: (v) => v == 'export' ? _export() : _import(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'export', child: Text('Exportă (copiază backup)')),
            PopupMenuItem(value: 'import', child: Text('Importă din clipboard')),
          ],
        ),
      ),
      _summaryCard(sum, active.length),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 20), label: const Text('Adaugă investiție')),
      if (active.isNotEmpty) ...[
        const SectionHeader('Încasări viitoare'),
        _ladder(active, now),
      ],
      const SectionHeader('Pozițiile mele'),
      Segmented<bool>(
        values: const [true, false],
        selected: showActive,
        label: (v) => v ? 'Active (${active.length})' : 'Ajunse la scadență (${closed.length})',
        onChanged: (v) => setState(() => showActive = v),
      ),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        AppCard(
          child: Text(
            showActive ? 'Nu ai investiții active. Apasă „Adaugă investiție” și alege ISIN-ul din listă.' : 'Nicio poziție ajunsă la scadență.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      for (final h in shown) ...[_holdingCard(h, now), const SizedBox(height: 10)],
      const SizedBox(height: 6),
      const InfoNote(
        'Calcule conform Regulamentului VMS: rata dobânzii la bonuri – pct. 72 (Actual/365); '
        'obligațiuni – randament pct. 74, cupon pct. 75, dobândă acumulată pct. 76. '
        'Valori informative, fără impozitare și comisioane.',
      ),
    ]);
  }

  Widget _summaryCard(PortfolioSummary s, int count) => AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vei încasa la scadență', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(money(s.atMaturity), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
            const SizedBox(width: 6),
            const Text('lei', style: TextStyle(fontSize: 14, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          ]),
          Text(
            '${intFmt(s.units)} VMS × 100 lei${s.coupons > 0 ? ' + cupoane ${lei(s.coupons)}' : ''}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Stat('Investit', lei(s.cost), valueSize: 13.5)),
            Expanded(child: Stat('Dobândă', '+${lei(s.interest)}', valueColor: AppColors.green, valueSize: 13.5)),
            Expanded(child: Stat('Rentab. medie', pct(s.weightedReturn), valueColor: AppColors.primary, valueSize: 13.5)),
          ]),
          if (count > 0) ...[
            const SizedBox(height: 10),
            Text('$count poziții active · rentabilitate ponderată cu suma investită', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
          ],
        ]),
      );

  /// „Scara scadențelor”: încasările pe următoarele 12 luni.
  Widget _ladder(List<Holding> active, DateTime now) {
    final flows = <CashFlow>[];
    final owner = <CashFlow, Holding>{};
    for (final h in active) {
      for (final f in computeMetrics(h, today: now).futureFlows) {
        flows.add(f);
        owner[f] = h;
      }
    }
    flows.sort((a, b) => a.date.compareTo(b.date));
    final months = List.generate(12, (i) => DateTime(now.year, now.month + i));
    final perMonth = List<double>.filled(12, 0);
    for (final f in flows) {
      final idx = (f.date.year - now.year) * 12 + f.date.month - now.month;
      if (idx >= 0 && idx < 12) perMonth[idx] += f.amount;
    }
    final maxV = perMonth.reduce(math.max);
    final later = flows.where((f) => (f.date.year - now.year) * 12 + f.date.month - now.month >= 12).fold<double>(0, (s, f) => s + f.amount);
    final next = flows.take(3).toList();

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (maxV > 0)
          SizedBox(
            height: 130,
            child: BarChart(BarChartData(
              maxY: maxV * 1.15,
              alignment: BarChartAlignment.spaceBetween,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.text,
                  tooltipRoundedRadius: 10,
                  fitInsideHorizontally: true,
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${monthYear(months[group.x])}\n${lei(rod.toY)}',
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 4,
                      child: Text(shortMonth(months[v.toInt()]), style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
                    ),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < 12; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: perMonth[i],
                      width: 13,
                      color: perMonth[i] > 0 ? AppColors.primary : AppColors.divider,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxV * 1.15, color: AppColors.background),
                    ),
                  ]),
              ],
            )),
          )
        else
          const Text('Nicio încasare în următoarele 12 luni.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        if (later > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('După 12 luni: ${lei(later)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ),
        if (next.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(),
          for (final f in next)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Container(
                  width: 42,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(color: AppColors.tile, borderRadius: BorderRadius.circular(10)),
                  child: Column(children: [
                    Text('${f.date.day}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.1)),
                    Text(shortMonth(f.date), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(owner[f]?.isin ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(f.isCoupon ? 'Cupon' : 'Rambursare la scadență', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  ]),
                ),
                Text(lei(f.amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _holdingCard(Holding h, DateTime now) {
    final m = computeMetrics(h, today: now);
    final matured = h.isMatured(now);
    return AppCard(
      onTap: () => _edit(h),
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TypePill(h.type),
          const SizedBox(width: 8),
          Expanded(child: Text(h.isin, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textMuted),
            onSelected: (v) => v == 'edit' ? _edit(h) : _delete(h),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Editează')),
              PopupMenuItem(value: 'delete', child: Text('Șterge')),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${h.termLabel.isNotEmpty ? '${h.termLabel} · ' : ''}scadență ${date(h.maturity)}'
              '${matured ? ' · încasat' : ' · ${m.daysLeft} zile rămase'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: m.progress,
                minHeight: 5,
                backgroundColor: AppColors.background,
                color: matured ? AppColors.green : AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Stat('Preț', priceFmt(h.price), valueSize: 13.5)),
              Expanded(child: Stat('Cantitate', intFmt(h.quantity), valueSize: 13.5)),
              Expanded(child: Stat('Investit', money(m.cost), valueSize: 13.5)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Stat('Rata dobânzii', pct(m.nominalRate), valueSize: 13.5, valueColor: AppColors.primary)),
              Expanded(child: Stat('Rentabilitate', pct(m.investmentReturn), valueSize: 13.5, valueColor: AppColors.primary)),
              Expanded(child: Stat('Dobândă', '+${money(m.interest)}', valueSize: 13.5, valueColor: AppColors.green)),
            ]),
            if (h.couponRate != null && !h.isBill)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Cupon ${pct(h.couponRate!)} · cupoane de încasat ${lei(m.couponsTotal)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ),
            if (h.manual)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('ISIN introdus manual', style: TextStyle(fontSize: 11, color: AppColors.amber)),
              ),
          ]),
        ),
      ]),
    );
  }
}
