import 'package:flutter_test/flutter_test.dart';
import 'package:vms_moldova/models/holding.dart';
import 'package:vms_moldova/services/finance.dart';

Holding _bt({DateTime? maturity}) => Holding(
      id: 'bt',
      isin: 'MD3001000000',
      type: 'BT',
      termLabel: '364 zile',
      issueDate: DateTime(2026, 11, 5),
      maturity: maturity ?? DateTime(2027, 11, 4),
      purchaseDate: DateTime(2026, 11, 5),
      price: 88.83,
      quantity: 1000,
    );

/// OS 3 ani, cupon fix 10,25%, 6 cupoane semestriale.
Holding _os({required DateTime purchase, double price = 100}) => Holding(
      id: 'os',
      isin: 'MD4004001096',
      type: 'OS',
      termLabel: '3 ani',
      issueDate: DateTime(2026, 6, 12),
      maturity: DateTime(2029, 6, 12),
      purchaseDate: purchase,
      price: price,
      quantity: 500,
      couponRate: 10.25,
      couponDates: [
        DateTime(2026, 12, 12),
        DateTime(2027, 6, 12),
        DateTime(2027, 12, 12),
        DateTime(2028, 6, 12),
        DateTime(2028, 12, 12),
        DateTime(2029, 6, 12),
      ],
    );

double _sum(List<YearIncome> ys) => ys.fold(0, (t, y) => t + y.total);

void main() {
  final today = DateTime(2026, 11, 14);

  test('BT: dobânda (100 − preț) × titluri, în anul scadenței', () {
    final ys = incomeByYear([_bt()], today: today);
    expect(ys.map((y) => y.year), [2027]);
    expect(ys.single.bills, closeTo(11170, 0.01));
    expect(ys.single.pending, closeTo(11170, 0.01));
    expect(ys.single.received, 0);
  });

  test('OS la emitere: cupoanele în anul plății, fără diferență la scadență', () {
    final h = _os(purchase: DateTime(2026, 6, 12));
    final ys = incomeByYear([h], today: today);
    expect(ys.map((y) => y.year), [2026, 2027, 2028, 2029]);
    expect(ys.every((y) => y.maturityDiff == 0), isTrue);
    expect(ys.first.coupons, greaterThan(0)); // cuponul din 12.12.2026
    expect(_sum(ys), closeTo(computeMetrics(h, today: today).interest, 0.01));
  });

  test('OS pe piața secundară: dobânda acumulată se scade în anul cumpărării, scontul apare la scadență', () {
    final h = _os(purchase: DateTime(2026, 9, 1), price: 98.24);
    final ys = incomeByYear([h], today: today);
    final y2026 = ys.firstWhere((y) => y.year == 2026);
    final accrued = accruedInterest(h.issueDate, h.maturity, 10.25, h.couponDates, h.purchaseDate) * 500;
    final dec2026 = bondCoupons(h.issueDate, h.maturity, 10.25, h.couponDates).first.amount * 500;
    expect(y2026.coupons, closeTo(dec2026 - accrued, 0.01));
    expect(ys.firstWhere((y) => y.year == 2029).maturityDiff, closeTo(500 * (100 - 98.24), 0.01));
    expect(_sum(ys), closeTo(computeMetrics(h, today: today).interest, 0.01));
  });

  test('încasat / urmează să încasezi, după data de azi', () {
    final h = _os(purchase: DateTime(2026, 6, 12));
    final ys = incomeByYear([h], today: DateTime(2027, 9, 1));
    final y2027 = ys.firstWhere((y) => y.year == 2027);
    expect(y2027.received, greaterThan(0)); // iunie 2027
    expect(y2027.pending, greaterThan(0)); // decembrie 2027
    expect(y2027.received + y2027.pending, closeTo(y2027.total, 0.01));
    expect(ys.firstWhere((y) => y.year == 2026).pending, 0);
  });

  test('mai multe poziții: totalul pe ani este suma câștigurilor', () {
    final list = [_bt(), _bt(maturity: DateTime(2027, 5, 6)), _os(purchase: DateTime(2026, 9, 1), price: 98.24)];
    final ys = incomeByYear(list, today: today);
    final gains = list.fold<double>(0, (t, h) => t + computeMetrics(h, today: today).interest);
    expect(_sum(ys), closeTo(gains, 0.01));
  });
}
