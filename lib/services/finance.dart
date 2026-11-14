/// Calcule conform Regulamentului privind VMS (BNM/MF, ed. 2025), pct. 71–76.
/// Convenția de zile: Actual/365. Valoarea nominală: 100 lei.
library;

import 'dart:math' as math;

import '../config.dart';
import '../models/dataset.dart';
import '../models/holding.dart';

int daysBetween(DateTime a, DateTime b) => dayOnly(b).difference(dayOnly(a)).inDays;

/// pct. 72 – rata nominală a dobânzii la BT: r = 100 × (N − P) / P × 365 / t
double billRate(double price, int days) => 100 * (kNominal - price) / price * 365 / days;

/// pct. 73 – rata efectivă anuală la BT: y = 100 × [(N / P)^(365/t) − 1]
double billEffectiveYield(double price, int days) => 100 * (math.pow(kNominal / price, 365 / days).toDouble() - 1);

/// Inversul pct. 72 (prețul care corespunde unei rate nominale).
double billPriceFromRate(double rate, int days) => kNominal / (1 + rate / 100 * days / 365);

/// pct. 75 – cuponul: C = N × r / 100 × t / 365
double couponAmount(double rate, int periodDays) => kNominal * rate / 100 * periodDays / 365;

class CashFlow {
  final DateTime date;
  final double amount; // pentru o VMS de 100 lei
  final bool isCoupon;
  final bool estimated; // cupon flotant a cărui rată nu a fost încă anunțată de MF
  const CashFlow(this.date, this.amount, {this.isCoupon = true, this.estimated = false});
}

/// Obligațiuni cu dobândă flotantă: cuponul = rata medie la BT de 182 zile + marja.
/// Ratele anunțate de MF vin din setul de date (actualizat automat); cupoanele încă
/// neanunțate se estimează cu ultima rată medie BT 182 zile + marja.
class FloatingRates {
  static Map<String, Security> _byIsin = const {};
  static double? reference; // ultima rată medie BT 182 zile
  static DateTime? referenceDate;

  static void load(VmsDataset d) {
    _byIsin = {for (final s in d.securities) if (s.isFloating) s.isin: s};
    final r = d.latestBt182;
    reference = r?.avgRate;
    referenceDate = r?.date;
  }

  static Security? of(String isin) => _byIsin[isin];
}

/// Rata aplicabilă fiecărui cupon (fixă sau flotantă).
class CouponRates {
  final double? fixed;
  final Map<DateTime, double> announced;
  final double? margin;

  const CouponRates.fixed(double rate)
      : fixed = rate,
        announced = const {},
        margin = null;
  const CouponRates.floating(this.announced, this.margin) : fixed = null;

  bool get isFloating => fixed == null;

  /// Rata folosită pentru cupoanele neanunțate.
  double get estimate {
    final ref = FloatingRates.reference;
    if (ref != null && margin != null) return ref + margin!;
    if (announced.isNotEmpty) return announced[(announced.keys.toList()..sort()).last]!;
    return (ref ?? 0) + (margin ?? 0);
  }

  bool isAnnounced(DateTime pay) => fixed != null || announced.containsKey(dayOnly(pay));
  double rateFor(DateTime pay) => fixed ?? announced[dayOnly(pay)] ?? estimate;
}

/// Ratele cupoanelor unei poziții; null pentru bonuri și titluri fără cupon.
CouponRates? couponRatesFor(Holding h) {
  if (h.isBill) return null;
  final live = FloatingRates.of(h.isin);
  if (live != null || h.isFloating) {
    return CouponRates.floating({...h.couponHistory, ...?live?.couponHistory}, live?.margin ?? h.margin);
  }
  final r = h.couponRate;
  return (r == null || r == 0) ? null : CouponRates.fixed(r);
}

/// Datele cupoanelor: din baza de date sau, dacă lipsesc, semestrial înapoi de la scadență.
List<DateTime> couponSchedule(DateTime issue, DateTime maturity, List<DateTime> known) {
  if (known.isNotEmpty) return [...known]..sort();
  final out = <DateTime>[];
  var k = 0;
  while (true) {
    final d = _addMonths(maturity, -6 * k);
    if (!dayOnly(d).isAfter(dayOnly(issue))) break;
    out.add(d);
    k++;
    if (k > 200) break;
  }
  out.sort();
  return out;
}

DateTime _addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final lastDay = DateTime.utc(y, m + 1, 0).day;
  return DateTime.utc(y, m, math.min(d.day, lastDay));
}

/// Cupoanele (cu suma fiecăruia) pentru o obligațiune cu cupon fix.
List<CashFlow> bondCoupons(DateTime issue, DateTime maturity, double rate, List<DateTime> known) =>
    bondCouponsWith(issue, maturity, CouponRates.fixed(rate), known);

/// Cupoanele cu rata fiecărei perioade (fixă sau flotantă).
List<CashFlow> bondCouponsWith(DateTime issue, DateTime maturity, CouponRates rates, List<DateTime> known) {
  final dates = couponSchedule(issue, maturity, known);
  final out = <CashFlow>[];
  var prev = issue;
  for (final d in dates) {
    out.add(CashFlow(d, couponAmount(rates.rateFor(d), daysBetween(prev, d)), estimated: !rates.isAnnounced(d)));
    prev = d;
  }
  return out;
}

/// pct. 76 – dobânda acumulată (cuponul curent) la data [on]: D = C × n / t
double accruedInterest(DateTime issue, DateTime maturity, double rate, List<DateTime> known, DateTime on) =>
    accruedInterestWith(issue, maturity, CouponRates.fixed(rate), known, on);

double accruedInterestWith(DateTime issue, DateTime maturity, CouponRates rates, List<DateTime> known, DateTime on) {
  final dates = couponSchedule(issue, maturity, known);
  var prev = issue;
  for (final d in dates) {
    if (!dayOnly(on).isBefore(dayOnly(prev)) && dayOnly(on).isBefore(dayOnly(d))) {
      final t = daysBetween(prev, d);
      return couponAmount(rates.rateFor(d), t) * daysBetween(prev, on) / t;
    }
    prev = d;
  }
  return 0;
}

/// pct. 74 – randamentul i din ecuația prețului:
/// P = Σ C_k / (1 + i/100)^(t_k/365) + N / (1 + i/100)^(t_n/365)
/// Rezolvată numeric (bisecție). [grossPrice] include dobânda acumulată.
double bondYield(double grossPrice, List<CashFlow> flows, DateTime settle) {
  double f(double i) {
    var s = 0.0;
    for (final c in flows) {
      s += c.amount / math.pow(1 + i / 100, daysBetween(settle, c.date) / 365);
    }
    return s - grossPrice;
  }

  var lo = -90.0, hi = 300.0;
  for (var k = 0; k < 200; k++) {
    final mid = (lo + hi) / 2;
    if (f(mid) > 0) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Toți indicatorii afișați pentru o poziție.
class HoldingMetrics {
  final double nominalRate; // rata dobânzii (de la emitere la scadență, la prețul introdus)
  final double investmentReturn; // rentabilitatea investiției (de la data achiziției)
  final double effectiveYield; // rata efectivă anuală (pct. 73 / pct. 74)
  final double accruedPerUnit; // dobânda acumulată plătită la cumpărare (OS)
  final double cost; // suma plătită
  final double principalAtMaturity; // cantitate × 100 lei
  final double couponsTotal; // cupoane încasate după cumpărare (OS)
  final double interest; // câștigul total în lei
  final int daysHeld; // zile de la cumpărare la scadență
  final int daysLeft; // zile până la scadență (de azi)
  final double progress; // 0..1 din perioada deținerii
  final List<CashFlow> futureFlows; // pe întreaga poziție (lei)
  final bool floating; // dobândă flotantă
  final double? margin; // p.p. (dobândă flotantă)
  final DateTime? nextCouponDate;
  final double? nextCouponRate;
  final bool nextCouponEstimated; // rata următorului cupon nu e încă anunțată
  final bool hasEstimates; // există cupoane calculate cu rata estimată

  const HoldingMetrics({
    required this.nominalRate,
    required this.investmentReturn,
    required this.effectiveYield,
    required this.accruedPerUnit,
    required this.cost,
    required this.principalAtMaturity,
    required this.couponsTotal,
    required this.interest,
    required this.daysHeld,
    required this.daysLeft,
    required this.progress,
    required this.futureFlows,
    this.floating = false,
    this.margin,
    this.nextCouponDate,
    this.nextCouponRate,
    this.nextCouponEstimated = false,
    this.hasEstimates = false,
  });

  double get totalReceipts => principalAtMaturity + couponsTotal;
}

HoldingMetrics computeMetrics(Holding h, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final q = h.remaining.toDouble(); // titlurile rămase după vânzări
  final term = math.max(1, daysBetween(h.issueDate, h.maturity));
  final held = math.max(1, daysBetween(h.purchaseDate, h.maturity));
  final left = daysBetween(now, h.maturity);
  final progress = (1 - left / held).clamp(0.0, 1.0).toDouble();

  final rates = couponRatesFor(h);
  if (rates == null) {
    final interest = q * (kNominal - h.price);
    return HoldingMetrics(
      nominalRate: billRate(h.price, term),
      investmentReturn: billRate(h.price, held),
      effectiveYield: billEffectiveYield(h.price, held),
      accruedPerUnit: 0,
      cost: q * h.price,
      principalAtMaturity: q * kNominal,
      couponsTotal: 0,
      interest: interest,
      daysHeld: held,
      daysLeft: left,
      progress: progress,
      futureFlows: [CashFlow(h.maturity, q * kNominal, isCoupon: false)],
    );
  }

  final coupons = bondCouponsWith(h.issueDate, h.maturity, rates, h.couponDates);
  final fromIssue = [...coupons, CashFlow(h.maturity, kNominal, isCoupon: false)];
  final afterPurchase = [
    ...coupons.where((c) => dayOnly(c.date).isAfter(dayOnly(h.purchaseDate))),
    CashFlow(h.maturity, kNominal, isCoupon: false),
  ];
  final accrued = accruedInterestWith(h.issueDate, h.maturity, rates, h.couponDates, h.purchaseDate);
  final gross = h.price + accrued;
  final couponsPerUnit = afterPurchase.where((c) => c.isCoupon).fold<double>(0, (s, c) => s + c.amount);
  final cost = q * gross;
  final investmentReturn = bondYield(gross, afterPurchase, h.purchaseDate);
  final upcoming = coupons.where((c) => dayOnly(c.date).isAfter(dayOnly(now))).toList();
  final next = upcoming.isEmpty ? null : upcoming.first;
  return HoldingMetrics(
    nominalRate: bondYield(h.price, fromIssue, h.issueDate),
    investmentReturn: investmentReturn,
    effectiveYield: investmentReturn, // pct. 74 este deja o rată anuală efectivă
    accruedPerUnit: accrued,
    cost: cost,
    principalAtMaturity: q * kNominal,
    couponsTotal: q * couponsPerUnit,
    interest: q * (couponsPerUnit + kNominal) - cost,
    daysHeld: held,
    daysLeft: left,
    progress: progress,
    futureFlows: [
      for (final c in afterPurchase)
        if (dayOnly(c.date).isAfter(dayOnly(now))) CashFlow(c.date, c.amount * q, isCoupon: c.isCoupon, estimated: c.estimated),
    ],
    floating: rates.isFloating,
    margin: rates.margin,
    nextCouponDate: next?.date,
    nextCouponRate: next == null ? null : rates.rateFor(next.date),
    nextCouponEstimated: next?.estimated ?? false,
    hasEstimates: afterPurchase.any((c) => c.estimated),
  );
}

/// Cupoanele unei obligațiuni din perspectiva deținătorului.
class CouponCount {
  final int total; // cupoanele obligațiunii, de la emitere la scadență
  final int mine; // cele plătite după data cumpărării (revin deținătorului)
  final int received; // dintre ale mele, deja plătite până azi (inclusiv)
  final DateTime? next; // data următorului cupon (null dacă nu mai urmează niciunul)
  final int? nextOrdinal; // al câtelea cupon al obligațiunii este următorul (1 = primul)
  const CouponCount({required this.total, required this.mine, required this.received, this.next, this.nextOrdinal});
}

/// Numărul de cupoane (fără sume): null pentru bonuri și titluri fără cupon.
CouponCount? couponCount(Holding h, {DateTime? today}) {
  if (couponRatesFor(h) == null) return null;
  final dates = couponSchedule(h.issueDate, h.maturity, h.couponDates);
  if (dates.isEmpty) return null;
  final bought = dayOnly(h.purchaseDate), now = dayOnly(today ?? DateTime.now());
  var mine = 0, received = 0;
  DateTime? next;
  int? ordinal;
  for (var i = 0; i < dates.length; i++) {
    final d = dayOnly(dates[i]);
    if (!d.isAfter(bought)) continue;
    mine++;
    if (!d.isAfter(now)) {
      received++;
    } else if (next == null) {
      next = dates[i];
      ordinal = i + 1;
    }
  }
  return CouponCount(total: dates.length, mine: mine, received: received, next: next, nextOrdinal: ordinal);
}

/// Venitul unui an calendaristic (lei), pe surse.
class YearIncome {
  final int year;
  double bills = 0; // dobânda la BT: (100 − preț) × titluri, în anul scadenței
  double coupons = 0; // cupoanele OS în anul plății, minus dobânda acumulată plătită la cumpărare
  double maturityDiff = 0; // OS: (100 − preț) × titluri, în anul scadenței (scont / primă)
  double sales = 0; // vânzări: (preț vânzare − preț cumpărare + dobânda acumulată primită) × titluri
  double received = 0; // partea deja încasată (până azi, inclusiv)
  double pending = 0; // partea care urmează
  bool estimated = false; // conține cupoane flotante cu rata încă neanunțată
  YearIncome(this.year);

  double get total => bills + coupons + maturityDiff + sales;
}

/// Venitul pe ani pentru toate pozițiile (active și ajunse la scadență), crescător după an.
/// Suma pe toți anii este egală cu suma câștigurilor din [computeMetrics].
List<YearIncome> incomeByYear(Iterable<Holding> holdings, {DateTime? today}) {
  final now = dayOnly(today ?? DateTime.now());
  final years = <int, YearIncome>{};
  void add(DateTime date, double amount, void Function(YearIncome y, double v) into, {bool estimated = false}) {
    if (amount == 0) return;
    final y = years.putIfAbsent(date.year, () => YearIncome(date.year));
    into(y, amount);
    if (dayOnly(date).isAfter(now)) {
      y.pending += amount;
    } else {
      y.received += amount;
    }
    if (estimated) y.estimated = true;
  }

  for (final h in holdings) {
    final rem = h.remaining.toDouble();
    final diffPerUnit = kNominal - h.price;
    final rates = couponRatesFor(h);
    if (rates == null) {
      add(h.maturity, rem * diffPerUnit, h.isBill ? (y, v) => y.bills += v : (y, v) => y.maturityDiff += v);
    } else {
      // cupoanele: pentru titlurile deținute la data plății (rămase + cele vândute după acea dată)
      final coupons = bondCouponsWith(h.issueDate, h.maturity, rates, h.couponDates);
      for (final c in coupons) {
        if (!dayOnly(c.date).isAfter(dayOnly(h.purchaseDate))) continue;
        final held = rem + h.sales.where((x) => !dayOnly(x.date).isBefore(dayOnly(c.date))).fold<int>(0, (t, x) => t + x.quantity);
        add(c.date, held * c.amount, (y, v) => y.coupons += v, estimated: c.estimated);
      }
      final accrued = accruedInterestWith(h.issueDate, h.maturity, rates, h.couponDates, h.purchaseDate);
      add(h.purchaseDate, -h.quantity * accrued, (y, v) => y.coupons += v);
      add(h.maturity, rem * diffPerUnit, (y, v) => y.maturityDiff += v);
    }
    for (final x in h.sales) {
      add(x.date, x.quantity * (x.price - h.price + accruedAt(h, x.date)), (y, v) => y.sales += v);
    }
  }
  return years.values.toList()..sort((a, b) => a.year.compareTo(b.year));
}

/// Dobânda acumulată pentru o VMS de 100 lei la data [on] (0 pentru bonuri).
double accruedAt(Holding h, DateTime on) {
  final rates = couponRatesFor(h);
  return rates == null ? 0 : accruedInterestWith(h.issueDate, h.maturity, rates, h.couponDates, on);
}

/// Rata anuală a investiției dacă poziția e păstrată până la scadență.
double holdToMaturityRate(Holding h) => computeMetrics(h).investmentReturn;

/// Rezultatul unei vânzări pe piața secundară (pentru [quantity] titluri).
class SaleQuote {
  final double price; // preț net pentru 100 lei
  final double accruedPerUnit; // dobânda acumulată plătită de cumpărător (OS)
  final double proceeds; // primești: titluri × (preț + dobândă acumulată)
  final double cost; // ai plătit la cumpărare pentru aceste titluri (cu dobânda acumulată)
  final double couponsReceived; // cupoanele încasate pentru aceste titluri până la vânzare
  final double profit; // câștigul tău (poate fi negativ)
  final double sellerRate; // rata anuală a ta, de la cumpărare la vânzare
  final double buyerRate; // rata anuală a cumpărătorului, de la vânzare la scadență
  final int daysHeld, daysLeft;
  const SaleQuote({
    required this.price,
    required this.accruedPerUnit,
    required this.proceeds,
    required this.cost,
    required this.couponsReceived,
    required this.profit,
    required this.sellerRate,
    required this.buyerRate,
    required this.daysHeld,
    required this.daysLeft,
  });
}

/// Calculul unei vânzări la prețul [price], la data [date].
/// BT: ratele după pct. 72; OS: randamentul după pct. 74 (cu dobânda acumulată, pct. 76).
SaleQuote saleQuote(Holding h, {required DateTime date, required int quantity, required double price}) {
  final q = quantity.toDouble();
  final rates = couponRatesFor(h);
  final held = math.max(1, daysBetween(h.purchaseDate, date));
  final left = math.max(1, daysBetween(date, h.maturity));
  if (rates == null) {
    return SaleQuote(
      price: price,
      accruedPerUnit: 0,
      proceeds: q * price,
      cost: q * h.price,
      couponsReceived: 0,
      profit: q * (price - h.price),
      sellerRate: 100 * (price - h.price) / h.price * 365 / held,
      buyerRate: billRate(price, left),
      daysHeld: held,
      daysLeft: left,
    );
  }
  final coupons = bondCouponsWith(h.issueDate, h.maturity, rates, h.couponDates);
  final accB = accruedInterestWith(h.issueDate, h.maturity, rates, h.couponDates, h.purchaseDate);
  final accS = accruedInterestWith(h.issueDate, h.maturity, rates, h.couponDates, date);
  final got = coupons.where((c) => dayOnly(c.date).isAfter(dayOnly(h.purchaseDate)) && !dayOnly(c.date).isAfter(dayOnly(date))).toList();
  final future = [
    ...coupons.where((c) => dayOnly(c.date).isAfter(dayOnly(date))),
    CashFlow(h.maturity, kNominal, isCoupon: false),
  ];
  final cpu = got.fold<double>(0, (t, c) => t + c.amount);
  return SaleQuote(
    price: price,
    accruedPerUnit: accS,
    proceeds: q * (price + accS),
    cost: q * (h.price + accB),
    couponsReceived: q * cpu,
    profit: q * (price + accS + cpu - h.price - accB),
    sellerRate: bondYield(h.price + accB, [...got, CashFlow(date, price + accS, isCoupon: false)], h.purchaseDate),
    buyerRate: bondYield(price + accS, future, date),
    daysHeld: held,
    daysLeft: left,
  );
}

/// Prețul net (rotunjit la 2 zecimale) la care vânzătorul obține rata anuală [rate].
double priceForSellerRate(Holding h, DateTime date, double rate) {
  final rates = couponRatesFor(h);
  final held = math.max(1, daysBetween(h.purchaseDate, date));
  double p;
  if (rates == null) {
    p = h.price * (1 + rate / 100 * held / 365);
  } else {
    final coupons = bondCouponsWith(h.issueDate, h.maturity, rates, h.couponDates);
    final accB = accruedInterestWith(h.issueDate, h.maturity, rates, h.couponDates, h.purchaseDate);
    final accS = accruedInterestWith(h.issueDate, h.maturity, rates, h.couponDates, date);
    final f = 1 + rate / 100;
    var pvCoupons = 0.0;
    for (final c in coupons) {
      if (dayOnly(c.date).isAfter(dayOnly(h.purchaseDate)) && !dayOnly(c.date).isAfter(dayOnly(date))) {
        pvCoupons += c.amount / math.pow(f, daysBetween(h.purchaseDate, c.date) / 365);
      }
    }
    p = (h.price + accB - pvCoupons) * math.pow(f, held / 365).toDouble() - accS;
  }
  return (p * 100).round() / 100;
}

/// Prețul BT (rotunjit la 2 zecimale) pentru o rată nominală (pct. 72).
double billPriceRounded(double rate, int days) => (billPriceFromRate(rate, days) * 100).round() / 100;

class PortfolioSummary {
  final int positions;
  final int units;
  final double cost;
  final double atMaturity; // principal (unități × 100)
  final double coupons;
  final double interest;
  final double weightedReturn; // ponderat cu suma investită

  const PortfolioSummary(this.positions, this.units, this.cost, this.atMaturity, this.coupons, this.interest, this.weightedReturn);
}

PortfolioSummary summarize(List<Holding> holdings, {DateTime? today}) {
  var cost = 0.0, principal = 0.0, coupons = 0.0, interest = 0.0, weighted = 0.0;
  var units = 0;
  for (final h in holdings) {
    final m = computeMetrics(h, today: today);
    cost += m.cost;
    principal += m.principalAtMaturity;
    coupons += m.couponsTotal;
    interest += m.interest;
    weighted += m.cost * m.investmentReturn;
    units += h.remaining;
  }
  return PortfolioSummary(holdings.length, units, cost, principal, coupons, interest, cost > 0 ? weighted / cost : 0);
}
