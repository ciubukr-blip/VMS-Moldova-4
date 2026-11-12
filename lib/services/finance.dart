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
  const CashFlow(this.date, this.amount, {this.isCoupon = true});
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

/// Cupoanele (cu suma fiecăruia) pentru o obligațiune.
List<CashFlow> bondCoupons(DateTime issue, DateTime maturity, double rate, List<DateTime> known) {
  final dates = couponSchedule(issue, maturity, known);
  final out = <CashFlow>[];
  var prev = issue;
  for (final d in dates) {
    out.add(CashFlow(d, couponAmount(rate, daysBetween(prev, d))));
    prev = d;
  }
  return out;
}

/// pct. 76 – dobânda acumulată (cuponul curent) la data [on]: D = C × n / t
double accruedInterest(DateTime issue, DateTime maturity, double rate, List<DateTime> known, DateTime on) {
  final dates = couponSchedule(issue, maturity, known);
  var prev = issue;
  for (final d in dates) {
    if (!dayOnly(on).isBefore(dayOnly(prev)) && dayOnly(on).isBefore(dayOnly(d))) {
      final t = daysBetween(prev, d);
      return couponAmount(rate, t) * daysBetween(prev, on) / t;
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
  });

  double get totalReceipts => principalAtMaturity + couponsTotal;
}

HoldingMetrics computeMetrics(Holding h, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final q = h.quantity.toDouble();
  final term = math.max(1, daysBetween(h.issueDate, h.maturity));
  final held = math.max(1, daysBetween(h.purchaseDate, h.maturity));
  final left = daysBetween(now, h.maturity);
  final progress = (1 - left / held).clamp(0.0, 1.0).toDouble();

  if (h.isBill || h.couponRate == null || h.couponRate == 0) {
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

  final rate = h.couponRate!;
  final coupons = bondCoupons(h.issueDate, h.maturity, rate, h.couponDates);
  final fromIssue = [...coupons, CashFlow(h.maturity, kNominal, isCoupon: false)];
  final afterPurchase = [
    ...coupons.where((c) => dayOnly(c.date).isAfter(dayOnly(h.purchaseDate))),
    CashFlow(h.maturity, kNominal, isCoupon: false),
  ];
  final accrued = accruedInterest(h.issueDate, h.maturity, rate, h.couponDates, h.purchaseDate);
  final gross = h.price + accrued;
  final couponsPerUnit = afterPurchase.where((c) => c.isCoupon).fold<double>(0, (s, c) => s + c.amount);
  final cost = q * gross;
  final investmentReturn = bondYield(gross, afterPurchase, h.purchaseDate);
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
        if (dayOnly(c.date).isAfter(dayOnly(now))) CashFlow(c.date, c.amount * q, isCoupon: c.isCoupon),
    ],
  );
}

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
    units += h.quantity;
  }
  return PortfolioSummary(holdings.length, units, cost, principal, coupons, interest, cost > 0 ? weighted / cost : 0);
}
