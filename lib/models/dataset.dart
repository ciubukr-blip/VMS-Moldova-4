/// Modelele datelor publice (rate, ISIN-uri, rezultate, calendar).
library;

DateTime _d(Object? v) => DateTime.parse(v as String);
DateTime? _dn(Object? v) => v == null ? null : DateTime.parse(v as String);
double? _num(Object? v) => v == null ? null : (v as num).toDouble();

/// Elimină ora: toate calculele lucrează cu zile calendaristice.
DateTime dayOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

class RateRecord {
  final DateTime date; // data decontării (emiterii)
  final int days; // 91 / 182 / 364
  final double maxRate, avgRate, minRate;

  RateRecord({required this.date, required this.days, required this.maxRate, required this.avgRate, required this.minRate});

  factory RateRecord.fromJson(Map<String, dynamic> m) => RateRecord(
        date: _d(m['date']),
        days: (m['days'] as num).toInt(),
        maxRate: (m['max'] as num).toDouble(),
        avgRate: (m['avg'] as num).toDouble(),
        minRate: (m['min'] as num).toDouble(),
      );

  double rate(String metric) => metric == 'avg' ? avgRate : metric == 'min' ? minRate : maxRate;
}

/// Un titlu de stat identificat prin ISIN.
class Security {
  final String isin;
  final String type; // 'BT' bon de trezorerie | 'OS' obligațiune de stat
  final String termLabel;
  final DateTime auctionDate;
  final DateTime issueDate;
  final DateTime maturity;
  final double? couponRate;
  final List<DateTime> couponDates;
  final String? note;
  final bool unverified;
  final String? couponType; // 'flotant' = dobândă flotantă (rata medie BT 182 zile + marja)
  final double? margin; // marja în p.p. (doar la dobânda flotantă)
  final Map<DateTime, double> couponHistory; // ratele anunțate de MF, pe data plății cuponului

  Security({
    required this.isin,
    required this.type,
    required this.termLabel,
    required this.auctionDate,
    required this.issueDate,
    required this.maturity,
    this.couponRate,
    this.couponDates = const [],
    this.note,
    this.unverified = false,
    this.couponType,
    this.margin,
    this.couponHistory = const {},
  });

  bool get isBill => type == 'BT';
  bool get isFloating => !isBill && couponType == 'flotant';
  int get termDays => dayOnly(maturity).difference(dayOnly(issueDate)).inDays;
  String get typeName => isBill ? 'Bon de trezorerie' : 'Obligațiune de stat';

  factory Security.fromJson(Map<String, dynamic> m) => Security(
        isin: m['isin'] as String,
        type: m['type'] as String,
        termLabel: (m['term_label'] as String?) ?? '',
        auctionDate: _d(m['auction_date']),
        issueDate: _d(m['issue_date']),
        maturity: _d(m['maturity']),
        couponRate: _num(m['coupon_rate']),
        couponDates: ((m['coupon_dates'] as List?) ?? const []).map((e) => DateTime.parse(e as String)).toList()..sort(),
        note: m['note'] as String?,
        unverified: (m['unverified'] as bool?) ?? false,
        couponType: m['coupon_type'] as String?,
        margin: _num(m['margin']),
        couponHistory: {
          for (final h in ((m['coupon_history'] as List?) ?? const []).cast<Map<String, dynamic>>())
            dayOnly(DateTime.parse(h['date'] as String)): (h['rate'] as num).toDouble(),
        },
      );
}

class AuctionResult {
  final DateTime auctionDate;
  final String isin;
  final String type;
  final String termLabel;
  final DateTime? settlementDate;
  final DateTime? maturity;
  final double? rateMin, rateAvg, rateMax;
  final double? announced, demand, placedNominal, placedPrice; // mii lei

  AuctionResult({
    required this.auctionDate,
    required this.isin,
    required this.type,
    required this.termLabel,
    this.settlementDate,
    this.maturity,
    this.rateMin,
    this.rateAvg,
    this.rateMax,
    this.announced,
    this.demand,
    this.placedNominal,
    this.placedPrice,
  });

  bool get hasVolumes => placedNominal != null;

  /// Prețul mediu ponderat al unei VMS de 100 lei (dacă volumele sunt publicate).
  double? get avgPrice => (placedNominal != null && placedPrice != null && placedNominal! > 0)
      ? placedPrice! / placedNominal! * 100
      : null;

  factory AuctionResult.fromJson(Map<String, dynamic> m) => AuctionResult(
        auctionDate: _d(m['auction_date']),
        isin: m['isin'] as String,
        type: (m['type'] as String?) ?? 'BT',
        termLabel: (m['term_label'] as String?) ?? '',
        settlementDate: _dn(m['settlement_date']),
        maturity: _dn(m['maturity']),
        rateMin: _num(m['rate_min']),
        rateAvg: _num(m['rate_avg']),
        rateMax: _num(m['rate_max']),
        announced: _num(m['announced']),
        demand: _num(m['demand']),
        placedNominal: _num(m['placed_nominal']),
        placedPrice: _num(m['placed_price']),
      );
}

class CalendarEntry {
  final String quarter;
  final DateTime auctionDate;
  final DateTime settlementDate;
  final String type; // BT / OS
  final String term;
  final String? volume; // mil. lei, interval (ex. "1200-1400")
  final DateTime? maturity;
  final String? sourceUrl;

  CalendarEntry({
    required this.quarter,
    required this.auctionDate,
    required this.settlementDate,
    required this.type,
    required this.term,
    this.volume,
    this.maturity,
    this.sourceUrl,
  });

  factory CalendarEntry.fromJson(Map<String, dynamic> m, String quarter, String? url) => CalendarEntry(
        quarter: quarter,
        auctionDate: _d(m['auction_date']),
        settlementDate: _d(m['settlement_date']),
        type: (m['type'] as String?) ?? 'BT',
        term: (m['term'] as String?) ?? '',
        volume: m['volume'] as String?,
        maturity: _dn(m['maturity']),
        sourceUrl: url,
      );
}

class VmsDataset {
  final int schema;
  final DateTime? generatedAt;
  final List<RateRecord> rates;
  final List<Security> securities;
  final List<AuctionResult> auctions;
  final List<CalendarEntry> calendar;
  final Map<String, String> calendarSources; // trimestru -> PDF
  late final Map<String, Security> byIsin = {for (final s in securities) s.isin: s};

  VmsDataset({
    required this.schema,
    required this.generatedAt,
    required this.rates,
    required this.securities,
    required this.auctions,
    required this.calendar,
    required this.calendarSources,
  });

  factory VmsDataset.fromJson(Map<String, dynamic> j) {
    final cal = <CalendarEntry>[];
    final sources = <String, String>{};
    for (final q in (j['calendar'] as List? ?? const [])) {
      final qm = q as Map<String, dynamic>;
      final quarter = qm['quarter'] as String;
      final url = qm['source_url'] as String?;
      if (url != null) sources[quarter] = url;
      for (final e in (qm['entries'] as List? ?? const [])) {
        cal.add(CalendarEntry.fromJson(e as Map<String, dynamic>, quarter, url));
      }
    }
    cal.sort((a, b) => a.auctionDate.compareTo(b.auctionDate));
    return VmsDataset(
      schema: (j['schema'] as num?)?.toInt() ?? 0,
      generatedAt: j['generated_at'] == null ? null : DateTime.tryParse(j['generated_at'] as String),
      rates: (j['rates'] as List).map((e) => RateRecord.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
      securities: (j['securities'] as List).map((e) => Security.fromJson(e as Map<String, dynamic>)).toList(),
      auctions: (j['auctions'] as List).map((e) => AuctionResult.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => a.auctionDate.compareTo(b.auctionDate)),
      calendar: cal,
      calendarSources: sources,
    );
  }

  /// Ultima rată medie la BT de 182 zile – referința cupoanelor cu dobândă flotantă.
  RateRecord? get latestBt182 {
    for (final r in rates.reversed) {
      if (r.days == 182) return r;
    }
    return null;
  }

  /// Rezultatele ultimei licitații (toate termenele din aceeași zi).
  List<AuctionResult> get lastAuction {
    if (auctions.isEmpty) return const [];
    final last = auctions.last.auctionDate;
    return auctions.where((a) => a.auctionDate == last).toList()
      ..sort((a, b) => (byIsin[a.isin]?.termDays ?? 0).compareTo(byIsin[b.isin]?.termDays ?? 0));
  }

  /// Ultima licitație care are și volume publicate.
  List<AuctionResult> get lastAuctionWithVolumes {
    final withVol = auctions.where((a) => a.hasVolumes).toList();
    if (withVol.isEmpty) return lastAuction;
    final last = withVol.last.auctionDate;
    return auctions.where((a) => a.auctionDate == last).toList()
      ..sort((a, b) => (byIsin[a.isin]?.termDays ?? 0).compareTo(byIsin[b.isin]?.termDays ?? 0));
  }
}
