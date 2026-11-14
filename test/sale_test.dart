import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vms_moldova/models/holding.dart';
import 'package:vms_moldova/services/finance.dart';

/// Exemplul real: BT 182 zile, emis 03.09.2026, scadență 04.03.2027, cumpărat la 95,29 (9,91%).
Holding _bt({List<Sale> sales = const []}) => Holding(
      id: 'bt182',
      isin: 'MD3001003128',
      type: 'BT',
      termLabel: '182 zile',
      issueDate: DateTime(2026, 9, 3),
      maturity: DateTime(2027, 3, 4),
      purchaseDate: DateTime(2026, 9, 3),
      price: 95.29,
      quantity: 1000,
      sales: sales,
    );

/// OS 3 ani, cupon 10,25%, cumpărată la emitere la 100.
Holding _os({List<Sale> sales = const []}) => Holding(
      id: 'os',
      isin: 'MD4004001096',
      type: 'OS',
      termLabel: '3 ani',
      issueDate: DateTime(2026, 6, 12),
      maturity: DateTime(2029, 6, 12),
      purchaseDate: DateTime(2026, 6, 12),
      price: 100,
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
      sales: sales,
    );

void main() {
  final saleDay = DateTime(2026, 11, 14);

  group('Vânzare BT (exemplul real)', () {
    test('la 97,20: vânzătorul 10,16%, cumpărătorul 9,56%', () {
      final q = saleQuote(_bt(), date: saleDay, quantity: 1000, price: 97.20);
      expect(q.daysHeld, 72);
      expect(q.daysLeft, 110);
      expect(q.sellerRate, closeTo(10.16, 0.005));
      expect(q.buyerRate, closeTo(9.56, 0.005));
      expect(q.proceeds, closeTo(97200, 0.01));
      expect(q.profit, closeTo(1910, 0.01));
    });

    test('pentru 9,91% pe an prețul este 97,15; la prețul rotunjit rata efectivă e 9,90%', () {
      final p = priceForSellerRate(_bt(), saleDay, 9.91);
      expect(p, 97.15);
      expect(saleQuote(_bt(), date: saleDay, quantity: 1, price: p).sellerRate, closeTo(9.90, 0.005));
    });

    test('rata până la scadență = rata de la cumpărare (9,91%)', () {
      expect(holdToMaturityRate(_bt()), closeTo(9.91, 0.005));
    });

    test('prețul BT rotunjit din rată (pct. 72)', () {
      expect(billPriceRounded(12.61, 364), 88.83);
    });
  });

  group('Vânzare OS', () {
    test('dobânda acumulată la 14.11.2026 = 4,35 lei; la 101: 13,06% / 10,03%', () {
      final q = saleQuote(_os(), date: saleDay, quantity: 500, price: 101);
      expect(q.accruedPerUnit, closeTo(4.35, 0.005));
      expect(q.proceeds, closeTo(500 * (101 + q.accruedPerUnit), 0.01));
      expect(q.sellerRate, closeTo(13.06, 0.01));
      expect(q.buyerRate, closeTo(10.03, 0.01));
    });

    test('prețul pentru o rată dată reproduce rata', () {
      final p = priceForSellerRate(_os(), saleDay, 13.0);
      expect(saleQuote(_os(), date: saleDay, quantity: 1, price: p).sellerRate, closeTo(13.0, 0.05));
    });
  });

  group('Vânzare parțială', () {
    final sale = Sale(id: 's1', date: saleDay, quantity: 400, price: 97.20);

    test('rămân 600 de titluri; metricile folosesc doar titlurile rămase', () {
      final h = _bt(sales: [sale]);
      expect(h.remaining, 600);
      expect(h.soldQuantity, 400);
      final m = computeMetrics(h, today: saleDay);
      expect(m.principalAtMaturity, 60000);
      expect(m.interest, closeTo(600 * 4.71, 0.01));
    });

    test('vânzările se salvează și se citesc', () {
      final h = _bt(sales: [sale]);
      final back = Holding.fromJson(jsonDecode(jsonEncode(h.toJson())) as Map<String, dynamic>);
      expect(back.sales.single.quantity, 400);
      expect(back.sales.single.price, 97.20);
      expect(back.sales.single.date, saleDay);
      expect(Holding.fromJson(_bt().toJson()).sales, isEmpty);
    });

    test('venit pe ani: coloana Vânzări în anul vânzării, total = câștigul rămas + câștigul vândut', () {
      final h = _bt(sales: [sale]);
      final ys = incomeByYear([h], today: saleDay);
      final y2026 = ys.firstWhere((y) => y.year == 2026);
      expect(y2026.sales, closeTo(764, 0.01));
      expect(ys.firstWhere((y) => y.year == 2027).bills, closeTo(2826, 0.01));
      final total = ys.fold<double>(0, (t, y) => t + y.total);
      expect(total, closeTo(764 + 2826, 0.01));
    });

    test('OS vândută parțial după un cupon: totalul pe ani se potrivește', () {
      final s = Sale(id: 's2', date: DateTime(2027, 2, 1), quantity: 200, price: 99.5);
      final h = _os(sales: [s]);
      final ys = incomeByYear([h], today: DateTime(2027, 3, 1));
      final total = ys.fold<double>(0, (t, y) => t + y.total);
      final soldProfit = saleQuote(_os(), date: s.date, quantity: 200, price: 99.5).profit;
      final keptGain = computeMetrics(h, today: DateTime(2027, 3, 1)).interest;
      expect(total, closeTo(soldProfit + keptGain, 0.01));
      // cuponul din 12.12.2026 a fost încasat pentru toate cele 500 de titluri
      expect(ys.firstWhere((y) => y.year == 2026).coupons, greaterThan(0));
    });
  });
}
