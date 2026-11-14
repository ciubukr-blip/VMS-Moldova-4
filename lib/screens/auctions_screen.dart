import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/dataset.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AuctionsScreen extends StatefulWidget {
  final VmsDataset data;
  const AuctionsScreen({super.key, required this.data});

  @override
  State<AuctionsScreen> createState() => _AuctionsScreenState();
}

class _AuctionsScreenState extends State<AuctionsScreen> {
  late DateTime month; // prima zi a lunii afișate
  DateTime? selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    final next = _nextAuctionDay(now);
    if (next != null && next.year == now.year && next.month == now.month) selected = next;
  }

  static DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  late final Map<DateTime, List<CalendarEntry>> _plannedCache = plannedAuctions(widget.data, DateTime.now());
  Map<DateTime, List<CalendarEntry>> get _planned => _plannedCache;

  Map<DateTime, List<AuctionResult>> get _results {
    final m = <DateTime, List<AuctionResult>>{};
    for (final a in widget.data.auctions) {
      (m[_key(a.auctionDate)] ??= []).add(a);
    }
    for (final l in m.values) {
      l.sort((a, b) => (widget.data.byIsin[a.isin]?.termDays ?? 0).compareTo(widget.data.byIsin[b.isin]?.termDays ?? 0));
    }
    return m;
  }

  DateTime? _nextAuctionDay(DateTime now) {
    final today = _key(now);
    final days = _planned.keys.where((d) => !d.isBefore(today)).toList()..sort();
    return days.isEmpty ? null : days.first;
  }

  @override
  Widget build(BuildContext context) {
    final planned = _planned;
    final results = _results;
    final now = DateTime.now();
    final next = _nextAuctionDay(now);
    final last = widget.data.lastAuction;
    final quarters = widget.data.calendarSources.keys.toList()..sort();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      PageHeader('Licitații', subtitle: quarters.isEmpty ? 'Calendarul MF' : 'Calendar MF · ${quarters.map(_quarterName).join(', ')}'),
      if (next != null) ...[_nextCard(next, planned[next] ?? const [], now), const SizedBox(height: 12)],
      _calendarCard(planned, results, now),
      if (selected != null) ...[const SizedBox(height: 12), _dayDetails(selected!, planned[selected!] ?? const [], results[selected!] ?? const [])],
      if (last.isNotEmpty) ...[
        SectionHeader('Ultima licitație', action: date(last.first.auctionDate), onAction: () {
          setState(() {
            selected = _key(last.first.auctionDate);
            month = DateTime(selected!.year, selected!.month);
          });
        }),
        _resultsCard(last),
      ],
      const SectionHeader('Surse oficiale'),
      AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (final (i, e) in kSourceLinks.entries.indexed) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              title: Text(e.key),
              trailing: const Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
              onTap: () => openLink(context, e.value),
            ),
          ],
        ]),
      ),
    ]);
  }

  String _quarterName(String q) {
    final p = q.split('-Q');
    if (p.length != 2) return q;
    const r = {'1': 'I', '2': 'II', '3': 'III', '4': 'IV'};
    return 'trim. ${r[p[1]] ?? p[1]} ${p[0]}';
  }

  // ------------------------------------------------------------ următoarea licitație
  Widget _nextCard(DateTime day, List<CalendarEntry> entries, DateTime now) {
    final inDays = day.difference(_key(now)).inDays;
    final when = inDays == 0 ? 'azi' : inDays == 1 ? 'mâine' : 'peste $inDays zile';
    final settle = entries.isEmpty ? null : entries.first.settlementDate;
    return AppCard(
      onTap: () => setState(() {
        selected = day;
        month = DateTime(day.year, day.month);
      }),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text('${day.day}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary, height: 1.1)),
            Text(shortMonth(day), style: const TextStyle(fontSize: 11.5, color: AppColors.primary)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Următoarea licitație · $when', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 3),
            _dateWithTotal(day, entries, 15),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in entries)
                Pill('${e.type} ${e.term}', fg: e.type == 'OS' ? AppColors.amber : AppColors.teal, bg: e.type == 'OS' ? AppColors.amberSoft : AppColors.tealSoft),
            ]),
            if (settle != null) ...[
              const SizedBox(height: 8),
              Text('Decontare (emitere): ${date(settle)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ calendar lunar
  Widget _calendarCard(Map<DateTime, List<CalendarEntry>> planned, Map<DateTime, List<AuctionResult>> results, DateTime now) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1; // luni = 0
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();
    final today = _key(now);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Column(children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
          ),
          Expanded(child: Text(monthYear(month), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          for (final w in const ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'])
            Expanded(child: Center(child: Text(w, style: const TextStyle(fontSize: 11, color: AppColors.textFaint, fontWeight: FontWeight.w500)))),
        ]),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(
                child: Builder(builder: (_) {
                  final idx = r * 7 + c - lead + 1;
                  if (idx < 1 || idx > daysInMonth) return const SizedBox(height: 44);
                  final d = DateTime(month.year, month.month, idx);
                  final p = planned[d] ?? const <CalendarEntry>[];
                  final res = results[d] ?? const <AuctionResult>[];
                  final types = {...p.map((e) => e.type), ...res.map((e) => e.type)};
                  return _dayCell(d, types, isToday: d == today, isSelected: d == selected, hasResults: res.isNotEmpty);
                }),
              ),
          ]),
        const SizedBox(height: 8),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Dot(AppColors.teal),
          SizedBox(width: 4),
          Text('Bonuri de trezorerie', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          SizedBox(width: 14),
          _Dot(AppColors.amber),
          SizedBox(width: 4),
          Text('Obligațiuni', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          SizedBox(width: 14),
          Icon(Icons.check_circle, size: 11, color: AppColors.green),
          SizedBox(width: 4),
          Text('Rezultate', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }

  Widget _dayCell(DateTime d, Set<String> types, {required bool isToday, required bool isSelected, required bool hasResults}) {
    final has = types.isNotEmpty;
    final bg = isSelected
        ? AppColors.primary
        : has
            ? (types.contains('OS') && !types.contains('BT') ? AppColors.amberSoft : AppColors.tealSoft)
            : Colors.transparent;
    final fg = isSelected ? Colors.white : has ? AppColors.text : (d.weekday >= 6 ? AppColors.textFaint : AppColors.text);
    return GestureDetector(
      onTap: has ? () => setState(() => selected = d) : null,
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !isSelected ? Border.all(color: AppColors.primary, width: 1.2) : null,
        ),
        child: Stack(alignment: Alignment.center, children: [
          Text('${d.day}', style: TextStyle(fontSize: 13, fontWeight: has ? FontWeight.w600 : FontWeight.w400, color: fg)),
          if (has)
            Positioned(
              bottom: 5,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (types.contains('BT')) _Dot(isSelected ? Colors.white : AppColors.teal),
                if (types.contains('BT') && types.contains('OS')) const SizedBox(width: 2),
                if (types.contains('OS')) _Dot(isSelected ? Colors.white : AppColors.amber),
              ]),
            ),
          if (hasResults)
            Positioned(top: 3, right: 3, child: Icon(Icons.check_circle, size: 9, color: isSelected ? Colors.white : AppColors.green)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ detalii zi
  Widget _dayDetails(DateTime d, List<CalendarEntry> planned, List<AuctionResult> results) {
    final isPast = d.isBefore(_key(DateTime.now()));
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _dateWithTotal(d, planned, 15)),
          if (results.isNotEmpty)
            const Pill('Rezultate publicate', fg: AppColors.green, bg: AppColors.greenSoft)
          else if (isPast)
            const Pill('Rezultate în așteptare', fg: AppColors.amber, bg: AppColors.amberSoft)
          else
            const Pill('Planificat', fg: AppColors.primary, bg: AppColors.primarySoft),
        ]),
        const SizedBox(height: 10),
        if (results.isNotEmpty)
          for (final a in results) _resultRow(a)
        else
          for (final e in planned)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OutlinedTile(
                child: Row(children: [
                TypePill(e.type),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.term, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(
                      'emitere ${date(e.settlementDate)}${e.maturity != null ? ' · scadență ${date(e.maturity!)}' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ]),
                ),
                if (e.volume != null) Text('${e.volume} mil. lei', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
        if (planned.any((e) => e.sourceUrl != null)) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => openLink(context, planned.firstWhere((e) => e.sourceUrl != null).sourceUrl!),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Calendarul oficial (PDF)'),
          ),
        ],
      ]),
    );
  }

  /// Data zilei, urmată (gri, mic) de volumul maxim planificat pentru toate titlurile.
  Widget _dateWithTotal(DateTime d, List<CalendarEntry> planned, double size) {
    final total = plannedMaxTotal(planned);
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '${weekdayName(d)[0].toUpperCase()}${weekdayName(d).substring(1)}, ${date(d)}',
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: AppColors.text),
        ),
        if (total != null)
          TextSpan(
            text: ' · ${NumberFormat('#,##0', 'ro').format(total)} mil. lei',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: AppColors.textFaint),
          ),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ------------------------------------------------------------ rezultate
  Widget _resultsCard(List<AuctionResult> list) => AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final a in list) _resultRow(a),
          const SizedBox(height: 6),
          const InfoNote('Volume în milioane lei (nominal). Rate nominale anuale: minimă, medie ponderată, maximă acceptată.'),
        ]),
      );

  Widget _resultRow(AuctionResult a) {
    final s = widget.data.byIsin[a.isin];
    final cover = (a.demand != null && a.announced != null && a.announced! > 0) ? a.demand! / a.announced! : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedTile(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TypePill(a.type),
          const SizedBox(width: 8),
          Text(a.termLabel.isNotEmpty ? a.termLabel : (s?.termLabel ?? ''), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(a.isin, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          if (a.maturity != null) Text('scad. ${shortDate.format(a.maturity!)}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Stat('Min', a.rateMin == null ? '—' : pct(a.rateMin!), valueSize: 13.5)),
          Expanded(child: Stat('Medie', a.rateAvg == null ? '—' : pct(a.rateAvg!), valueSize: 13.5, valueColor: AppColors.primary)),
          Expanded(child: Stat('Max', a.rateMax == null ? '—' : pct(a.rateMax!), valueSize: 13.5)),
        ]),
        if (a.hasVolumes) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Stat('Anunțat', a.announced == null ? '—' : milLei(a.announced!), valueSize: 12.5)),
            Expanded(child: Stat('Cerere', a.demand == null ? '—' : milLei(a.demand!), valueSize: 12.5)),
            Expanded(child: Stat('Realizat', milLei(a.placedNominal!), valueSize: 12.5, valueColor: AppColors.green)),
          ]),
          const SizedBox(height: 6),
          Text(
            [
              if (cover != null) 'Cerere/ofertă ${cover.toStringAsFixed(2).replaceAll('.', ',')}×',
              if (a.avgPrice != null) 'preț mediu ${priceFmt(double.parse(a.avgPrice!.toStringAsFixed(4)))}',
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
        ]),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext context) => Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Licitațiile planificate: calendarul trimestrial MF + licitațiile anunțate prin
/// comunicatele de plasare (ISIN-uri noi), fără dubluri. Comunicatele vechi (peste 14 zile)
/// nu se adaugă – pentru trecut contează rezultatele.
Map<DateTime, List<CalendarEntry>> plannedAuctions(VmsDataset data, DateTime now) {
  DateTime key(DateTime d) => DateTime(d.year, d.month, d.day);
  String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
  final m = <DateTime, List<CalendarEntry>>{};
  for (final e in data.calendar) {
    (m[key(e.auctionDate)] ??= []).add(e);
  }
  final from = key(now).subtract(const Duration(days: 14));
  for (final s in data.securities) {
    final d = key(s.auctionDate);
    if (d.isBefore(from)) continue;
    final day = m[d] ??= [];
    final dup = day.any((e) => e.type == s.type && digits(e.term) == digits(s.termLabel));
    if (dup) continue;
    day.add(CalendarEntry(
      quarter: '',
      auctionDate: s.auctionDate,
      settlementDate: s.issueDate,
      type: s.type,
      term: s.termLabel,
      maturity: s.maturity,
    ));
  }
  for (final l in m.values) {
    l.sort((a, b) => a.type == b.type
        ? (int.tryParse(digits(a.term)) ?? 0).compareTo(int.tryParse(digits(b.term)) ?? 0)
        : a.type.compareTo(b.type));
  }
  return m;
}

/// Volumul maxim planificat (mil. lei) pentru titlurile unei zile: capătul de sus al fiecărui
/// interval publicat de MF („1200-1400” → 1400). Null dacă niciun titlu nu are volum.
double? plannedMaxTotal(List<CalendarEntry> planned) {
  double? total;
  for (final e in planned) {
    final v = e.volume;
    if (v == null) continue;
    final nums = RegExp(r'\d+(?:[.,]\d+)?')
        .allMatches(v.replaceAll(RegExp(r'(?<=\d)[ \u00A0](?=\d{3}\b)'), ''))
        .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.')))
        .whereType<double>()
        .toList();
    if (nums.isEmpty) continue;
    total = (total ?? 0) + nums.reduce((a, b) => a > b ? a : b);
  }
  return total;
}
