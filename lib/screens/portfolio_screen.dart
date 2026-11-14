import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/dataset.dart';
import '../models/holding.dart';
import '../services/finance.dart';
import '../services/format.dart';
import '../services/portfolio_backup.dart';
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
  String? expandedId; // un singur rând deschis odată

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

  Future<void> _saveFile() async {
    final path = await PortfolioBackup.saveToFile(widget.holdings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null
          ? 'Copie salvată în ${PortfolioBackup.folderLabel}. Rămâne acolo și dacă aplicația e dezinstalată.'
          : 'Fișierul nu a putut fi salvat (necesită Android 10 sau mai nou). Folosește „Exportă”.'),
    ));
  }

  Future<void> _import() async {
    final clip = await Clipboard.getData('text/plain');
    if (!mounted) return;
    await _restoreFrom(clip?.text, 'Clipboard-ul nu conține un export VMS Moldova valid.');
  }

  Future<void> _importFile() async {
    final text = await PortfolioBackup.pickFile();
    if (!mounted || text == null) return;
    await _restoreFrom(text, 'Fișierul ales nu este o copie VMS Moldova validă.');
  }

  Future<void> _restoreFrom(String? raw, String invalidMessage) async {
    List<Holding> list;
    try {
      list = PortfolioStore.decode(raw ?? '');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(invalidMessage)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(widget.holdings.isEmpty ? 'Restaurezi portofoliul?' : 'Importă portofoliul?'),
        content: Text(widget.holdings.isEmpty
            ? 'Copia conține ${list.length} poziții.'
            : '${list.length} poziții vor înlocui portofoliul curent (${widget.holdings.length} poziții).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(widget.holdings.isEmpty ? 'Restaurează' : 'Înlocuiește')),
        ],
      ),
    );
    if (ok == true) widget.onReplaceAll(list);
  }

  void _menu(String v) {
    switch (v) {
      case 'export':
        _export();
      case 'file':
        _saveFile();
      case 'import':
        _import();
      case 'importFile':
        _importFile();
    }
  }

  /// Card afișat cât timp portofoliul e gol: restaurare rapidă după o reinstalare.
  Widget _restoreCard() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ai deja o copie a portofoliului?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'După o reinstalare, poți restaura pozițiile din copia salvată automat în '
            '${PortfolioBackup.folderLabel} sau din clipboard.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importFile,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Din fișier'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Din clipboard'),
              ),
            ),
          ]),
        ]),
      );

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
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filled(
            onPressed: _add,
            tooltip: 'Adaugă investiție',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add, size: 20, color: Colors.white),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.textMuted),
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Exportă (copiază backup)')),
              PopupMenuItem(value: 'file', child: Text('Salvează copie în Descărcări')),
              PopupMenuItem(value: 'import', child: Text('Importă din clipboard')),
              PopupMenuItem(value: 'importFile', child: Text('Importă din fișier')),
            ],
          ),
        ]),
      ),
      _summaryCard(sum),
      if (widget.holdings.isEmpty) ...[
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 20), label: const Text('Adaugă investiție')),
        const SizedBox(height: 12),
        _restoreCard(),
      ],
      if (active.isNotEmpty) ...[
        const SectionHeader('Încasări viitoare'),
        _ladder(active, now),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 6),
        child: Row(children: [
          Expanded(child: Text('Pozițiile mele', style: Theme.of(context).textTheme.titleLarge)),
          _activeSelector(active.length, closed.length),
        ]),
      ),
      if (shown.isEmpty)
        AppCard(
          child: Text(
            showActive ? 'Nu ai investiții active. Apasă „+” și alege ISIN-ul din listă.' : 'Nicio poziție expirată.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      ..._groupedList(shown, now),
      if (widget.holdings.isNotEmpty) ...[
        SectionHeader('Venit pe ani', action: 'Exportă', onAction: _shareIncome),
        _incomeCard(now),
      ],
      const SizedBox(height: 10),
      const InfoNote('Calcule conform Regulamentului VMS (pct. 72–76). Valori informative, fără impozitare și comisioane.'),
    ]);
  }

  Widget _summaryCard(PortfolioSummary s) => AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vei încasa la scadență', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(money(s.atMaturity), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(width: 6),
            const Text('lei', style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _inline('Investit', intFmt(s.cost), AppColors.text),
            _inline('Câștig', '+${intFmt(s.interest)}', AppColors.green),
            _inline('Rentab.', pct(s.weightedReturn), AppColors.primary),
          ]),
        ]),
      );

  Widget _inline(String label, String value, Color color) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label '),
          TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ]),
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      );

  /// Selectorul „Active | Expirate”, lângă titlul listei.
  Widget _activeSelector(int nActive, int nClosed) {
    Widget opt(String text, bool value) {
      final on = showActive == value;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          showActive = value;
          expandedId = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: on ? AppColors.surface : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Text(text,
              style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? AppColors.text : AppColors.textMuted)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFE9ECF1),
        border: Border.all(color: const Color(0xFFD9DEE6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        opt('Active ($nActive)', true),
        Container(width: 1, height: 14, color: const Color(0xFFCDD3DC)),
        opt('Expirate ($nClosed)', false),
      ]),
    );
  }

  // ------------------------------------------------------------ încasări viitoare
  /// „Scara scadențelor”: încasările pe următoarele 12 luni, cu anul sub luni.
  Widget _ladder(List<Holding> active, DateTime now) {
    final months = List.generate(12, (i) => DateTime(now.year, now.month + i));
    final perMonth = List<double>.filled(12, 0);
    for (final h in active) {
      for (final f in computeMetrics(h, today: now).futureFlows) {
        final idx = (f.date.year - now.year) * 12 + f.date.month - now.month;
        if (idx >= 0 && idx < 12) perMonth[idx] += f.amount;
      }
    }
    final maxV = perMonth.reduce(math.max);
    if (maxV <= 0) {
      return const AppCard(child: Text('Nicio încasare în următoarele 12 luni.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)));
    }
    // câte luni din fereastră aparțin fiecărui an (pentru eticheta anului de sub luni)
    final spans = <(int, int)>[];
    for (final m in months) {
      if (spans.isEmpty || spans.last.$1 != m.year) {
        spans.add((m.year, 1));
      } else {
        spans[spans.length - 1] = (m.year, spans.last.$2 + 1);
      }
    }
    const barArea = 110.0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(children: [
        SizedBox(
          height: barArea + 18,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 12; i++) ...[
              if (i > 0 && months[i].month == 1) const _DashedDivider(),
              Expanded(child: _monthBar(months[i], perMonth[i], maxV, barArea)),
            ],
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          for (final (i, sp) in spans.indexed) ...[
            if (i > 0) const SizedBox(width: 1),
            Expanded(
              flex: sp.$2,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.only(top: 3),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFD1D5DB)))),
                child: Text('${sp.$1}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _monthBar(DateTime month, double value, double maxV, double area) {
    final bar = Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4)),
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: value <= 0 ? 0 : math.max(0.06, value / (maxV * 1.1)),
              widthFactor: 1,
              child: Container(decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4))),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(shortMonth(month), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
    ]);
    if (value <= 0) return bar;
    return Tooltip(
      message: '${monthYear(month)}\n${lei(value)}',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      textAlign: TextAlign.center,
      child: bar,
    );
  }

  // ------------------------------------------------------------ pozițiile mele
  List<Widget> _groupedList(List<Holding> list, DateTime now) {
    final byYear = <int, List<Holding>>{};
    for (final h in list) {
      (byYear[h.maturity.year] ??= []).add(h);
    }
    final out = <Widget>[];
    for (final e in byYear.entries) {
      final nominal = e.value.fold<double>(0, (t, h) => t + h.quantity * 100.0);
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
        child: Row(children: [
          Expanded(child: Text('Scadență în ${e.key}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
          Text('${intFmt(nominal)} lei', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ]),
      ));
      out.add(AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, h) in e.value.indexed) ...[
            if (i > 0) const Divider(),
            _holdingRow(h, now),
          ],
        ]),
      ));
      out.add(const SizedBox(height: 6));
    }
    return out;
  }

  /// Rândul scurt: ISIN + scadența și rata / cuponul; în dreapta valoarea nominală și câștigul.
  Widget _holdingRow(Holding h, DateTime now) {
    final m = computeMetrics(h, today: now);
    final open = expandedId == h.id;
    final (rateLabel, rateValue) = _rateOf(h, m);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => expandedId = open ? null : h.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            TypePill(h.type),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.isin, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${date(h.maturity)} · ${rateLabel.toLowerCase()} ${pct(rateValue)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${intFmt(m.principalAtMaturity)} lei', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('+${intFmt(m.interest)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.green)),
            ]),
            const SizedBox(width: 4),
            Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: open ? AppColors.primary : AppColors.textFaint),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: open
            ? Padding(padding: const EdgeInsets.only(bottom: 10), child: _holdingDetails(h, m, h.isMatured(now)))
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }

  /// Rata afișată: la BT rata dobânzii, la OS cuponul (următorul, la dobânda flotantă).
  (String, double) _rateOf(Holding h, HoldingMetrics m) {
    if (h.isBill || couponRatesFor(h) == null) return ('Rata dobânzii', m.nominalRate);
    if (m.floating) return (m.nextCouponEstimated ? 'Cupon (estimat)' : 'Cupon', m.nextCouponRate ?? h.couponRate ?? m.nominalRate);
    return ('Cupon', h.couponRate ?? m.nominalRate);
  }

  /// Detaliile deschise sub rând (cardul complet de dinainte).
  Widget _holdingDetails(Holding h, HoldingMetrics m, bool matured) {
    final pal = h.isBill ? SectionPalette.bills : SectionPalette.bonds;
    final cc = couponCount(h, today: DateTime.now());
    final gainLabel = m.hasEstimates ? 'Câștig estimat' : 'Câștig';
    final (rateLabel, rateValue) = _rateOf(h, m);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFD),
        border: Border.all(color: const Color(0xFFDCE1E8)),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 3, color: pal.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${h.termLabel.isNotEmpty ? '${h.termLabel} · ' : ''}scadență ${date(h.maturity)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: matured ? AppColors.greenSoft : pal.wash, borderRadius: BorderRadius.circular(7)),
                child: Text(
                  matured ? 'încasat' : '${intFmt(m.daysLeft)} ${m.daysLeft == 1 ? 'zi rămasă' : 'zile rămase'}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: matured ? AppColors.green : pal.text),
                ),
              ),
            ]),
            if (h.hasNote) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: AppColors.amberSoft.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.sticky_note_2_outlined, size: 14, color: AppColors.amber)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(h.note!, style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.3))),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Stat('Investit (plătit)', money(m.cost), valueSize: 13.5, align: CrossAxisAlignment.center)),
              Expanded(child: Stat('Valoare nominală', money(m.principalAtMaturity), valueSize: 13.5, align: CrossAxisAlignment.center)),
              Expanded(child: Stat(gainLabel, '+${money(m.interest)}', valueSize: 13.5, valueColor: AppColors.green, align: CrossAxisAlignment.center)),
            ]),
            const SizedBox(height: 5),
            Text(
              'Valoarea nominală = suma primită la scadență (${intFmt(h.quantity)} × 100 lei)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            if (cc != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: pal.wash, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(10)),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Cupoane: ${cc.mine} din ${cc.total}', style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                    TextSpan(text: ' · încasate ${cc.received}'),
                    if (cc.next != null)
                      TextSpan(text: '\nurmătorul (${cc.nextOrdinal == 1 ? 'primul' : 'al ${cc.nextOrdinal}-lea'}) ${date(cc.next!)}'),
                  ]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.45),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Stat('Preț', priceFmt(h.price), valueSize: 13.5, align: CrossAxisAlignment.center)),
              Expanded(child: Stat(rateLabel, pct(rateValue), valueSize: 13.5, valueColor: AppColors.primary, align: CrossAxisAlignment.center)),
              Expanded(
                child: Stat('Rentabilitate', pct(m.investmentReturn), valueSize: 13.5, valueColor: AppColors.primary, align: CrossAxisAlignment.center),
              ),
            ]),
            if (h.manual)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('ISIN introdus manual', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.amber)),
              ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(onPressed: () => _edit(h), icon: const Icon(Icons.edit_outlined, size: 17), label: const Text('Editează')),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _delete(h),
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text('Șterge'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ venit pe ani
  Widget _incomeCard(DateTime now) {
    final years = incomeByYear(widget.holdings, today: now);
    if (years.isEmpty) {
      return const AppCard(child: Text('Încă nu există venituri de afișat.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)));
    }
    final t = _IncomeTotals.of(years);
    final current = years.where((y) => y.year == now.year).firstOrNull;
    final maxV = years.map((y) => y.total.abs()).reduce(math.max);
    const head = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.textMuted, height: 1.2);
    const cell = TextStyle(fontSize: 12, color: AppColors.text);
    const bold = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text);

    Widget cellNum(double v, TextStyle st) => Text(intFmt(v.round()), textAlign: TextAlign.right, style: st);
    Widget tag(int year, bool estimated) {
      final (text, fg, bg) = year < now.year
          ? ('încasat', AppColors.green, AppColors.greenSoft)
          : year == now.year
              ? ('în curs', AppColors.primary, AppColors.primarySoft)
              : (estimated ? 'estimat*' : 'estimat', AppColors.textMuted, AppColors.background);
      return Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: fg)),
      );
    }

    TableRow row(List<Widget> cells, {Decoration? decoration}) => TableRow(
          decoration: decoration,
          children: [for (final c in cells) Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2), child: c)],
        );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // grafic pe ani
        SizedBox(
          height: 120,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final y in years) Expanded(child: _yearBar(y, maxV, now)),
          ]),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _legendDot(AppColors.green, 'încasat'),
          _legendDot(AppColors.primary.withValues(alpha: 0.35), 'urmează în ${now.year}'),
          _legendDot(const Color(0xFFC7CCD3), 'estimat'),
        ]),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.45), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1), 4: FlexColumnWidth(1.05)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            row(const [
              Text('An', style: head),
              Text('Dobândă\nBT', textAlign: TextAlign.right, style: head),
              Text('Cupoane\nOS', textAlign: TextAlign.right, style: head),
              Text('Dif. la\nscadență', textAlign: TextAlign.right, style: head),
              Text('Total', textAlign: TextAlign.right, style: head),
            ], decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider)))),
            for (final y in years)
              row([
                Row(children: [Text('${y.year}', style: cell), Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: tag(y.year, y.estimated)))]),
                cellNum(y.bills, cell),
                cellNum(y.coupons, cell),
                cellNum(y.maturityDiff, cell),
                cellNum(y.total, bold),
              ], decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))))),
            row([
              const Text('Total', style: bold),
              cellNum(t.bills, bold),
              cellNum(t.coupons, bold),
              cellNum(t.diff, bold),
              cellNum(t.total, bold.copyWith(color: AppColors.green)),
            ], decoration: const BoxDecoration(color: Color(0xFFF8F9FB), border: Border(top: BorderSide(color: Color(0xFFD1D5DB), width: 1.5)))),
          ],
        ),
        const SizedBox(height: 6),
        _subtotal('Încasat', t.received, AppColors.green),
        _subtotal('Urmează să încasezi', t.pending, AppColors.primary),
        if (current != null) ...[
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'În ${now.year}: încasat '),
              TextSpan(text: lei(current.received), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.green)),
              const TextSpan(text: ' · urmează să încasezi până la 31.12: '),
              TextSpan(text: lei(current.pending), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
            ]),
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Dobânda BT = (100 − preț) × titluri, în anul scadenței. Cupoanele, în anul plății, minus dobânda acumulată '
          'plătită la cumpărare. Diferența la scadență = (100 − preț) × titluri la OS cumpărate sub / peste 100 lei.'
          '${years.any((y) => y.estimated) ? ' * Include cupoane flotante cu rata estimată.' : ''}'
          ' Sume în lei, informative; regimul fiscal se verifică la Serviciul Fiscal de Stat.',
          style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint, height: 1.4),
        ),
      ]),
    );
  }

  Widget _subtotal(String label, double v, Color color) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted))),
          Text(intFmt(v.round()), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  Widget _legendDot(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ]);

  /// O bară pe an: verde = încasat, albastru = anul curent (plin încasat, deschis urmează), gri = estimat.
  Widget _yearBar(YearIncome y, double maxV, DateTime now) {
    final total = math.max(0.0, y.total);
    final f = maxV <= 0 ? 0.0 : total / (maxV * 1.15);
    final past = y.year < now.year, cur = y.year == now.year;
    final recFrac = total <= 0 ? 0.0 : (math.max(0.0, y.received) / total).clamp(0.0, 1.0);
    final doneShare = past ? 1.0 : (cur ? recFrac : 0.0);
    final receivedFlex = (doneShare * 1000).round(), pendingFlex = 1000 - receivedFlex;
    final k = total >= 1000 ? '${NumberFormat('0.0', 'ro').format(total / 1000)}k' : intFmt(total.round());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final h = math.max(total > 0 ? 3.0 : 0.0, c.maxHeight * f);
            return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(k, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              SizedBox(
                height: math.min(h, math.max(0.0, c.maxHeight - 16)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Column(children: [
                    if (pendingFlex > 0)
                      Expanded(
                        flex: pendingFlex,
                        child: Container(color: cur ? AppColors.primary.withValues(alpha: 0.35) : const Color(0xFFC7CCD3)),
                      ),
                    if (receivedFlex > 0)
                      Expanded(flex: receivedFlex, child: Container(color: cur ? AppColors.primary : AppColors.green)),
                  ]),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 4),
        Text('${y.year}', style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ]),
    );
  }

  // ------------------------------------------------------------ export CSV
  String _incomeCsv(List<YearIncome> years, DateTime now) {
    String n(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
    String status(int y) => y < now.year ? 'încasat' : y == now.year ? 'în curs' : 'estimat';
    final t = _IncomeTotals.of(years);
    final b = StringBuffer('﻿'); // BOM: Excel recunoaște diacriticele
    b.writeln('An;Stare;Dobândă BT (lei);Cupoane OS (lei);Diferență la scadență (lei);Total (lei);Încasat (lei);Urmează să încasezi (lei)');
    for (final y in years) {
      b.writeln('${y.year};${status(y.year)};${n(y.bills)};${n(y.coupons)};${n(y.maturityDiff)};${n(y.total)};${n(y.received)};${n(y.pending)}');
    }
    b.writeln('Total;;${n(t.bills)};${n(t.coupons)};${n(t.diff)};${n(t.total)};${n(t.received)};${n(t.pending)}');
    return b.toString();
  }

  Future<void> _shareIncome() async {
    final now = DateTime.now();
    final years = incomeByYear(widget.holdings, today: now);
    if (years.isEmpty) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copiază tabelul'),
            subtitle: const Text('îl lipești într-un e-mail sau document'),
            onTap: () => Navigator.pop(c, 'copy'),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Salvează ca fișier CSV'),
            subtitle: Text('se deschide în Excel · ${PortfolioBackup.folderLabel}'),
            onTap: () => Navigator.pop(c, 'csv'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final csv = _incomeCsv(years, now);
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: csv.replaceFirst('﻿', '').replaceAll(';', '\t')));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tabelul a fost copiat.')));
      return;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    final path = await PortfolioBackup.saveText('venit-pe-ani-${now.year}-${two(now.month)}-${two(now.day)}.csv', csv, mime: 'text/csv');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null ? 'Salvat în ${PortfolioBackup.folderLabel}.' : 'Fișierul nu a putut fi salvat. Folosește „Copiază tabelul”.'),
    ));
  }
}

/// Totalurile tabelului „Venit pe ani”.
class _IncomeTotals {
  final double bills, coupons, diff, received, pending;
  const _IncomeTotals(this.bills, this.coupons, this.diff, this.received, this.pending);
  double get total => bills + coupons + diff;

  static _IncomeTotals of(List<YearIncome> ys) => _IncomeTotals(
        ys.fold(0, (t, y) => t + y.bills),
        ys.fold(0, (t, y) => t + y.coupons),
        ys.fold(0, (t, y) => t + y.maturityDiff),
        ys.fold(0, (t, y) => t + y.received),
        ys.fold(0, (t, y) => t + y.pending),
      );
}

/// Linie verticală punctată la trecerea în anul nou (graficul încasărilor).
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, child: CustomPaint(painter: _DashPainter()));
}

class _DashPainter extends CustomPainter {
  const _DashPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFC7CCD3)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, math.min(y + 3, size.height)), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
