import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vms_moldova/models/dataset.dart';
import 'package:vms_moldova/models/holding.dart';
import 'package:vms_moldova/services/data_repository.dart';
import 'package:vms_moldova/screens/auctions_screen.dart';
import 'package:vms_moldova/screens/bond_rates_section.dart';
import 'package:vms_moldova/services/finance.dart';
import 'package:vms_moldova/services/notifications.dart';
import 'package:vms_moldova/services/portfolio_store.dart';

void main() {
  group('Regulament VMS – bonuri de trezorerie (pct. 72)', () {
    // Licitația din 03.11.2026, 364 zile: 1.602.059,70 mii lei nominal, 1.423.055,43 mii lei la preț.
    // MF a publicat rata medie ponderată 12,61%.
    test('rata medie din volumele publicate', () {
      final price = 1423055.43 / 1602059.70 * 100;
      expect(billRate(price, 364), closeTo(12.61, 0.01));
    });
    test('91 zile: 3,15% publicat', () {
      final price = 40713.41 / 41032.20 * 100;
      expect(billRate(price, 91), closeTo(3.15, 0.02));
    });
    test('preț din rată și înapoi', () {
      final p = billPriceFromRate(11.63, 182);
      expect(billRate(p, 182), closeTo(11.63, 1e-9));
    });
  });

  group('Obligațiuni (pct. 74–76)', () {
    final issue = DateTime.utc(2024, 12, 13);
    final mat = DateTime.utc(2034, 12, 13);
    test('dobânda acumulată coincide cu comunicatele MF', () {
      // Redeschiderea MD4004001740 (8%): 3,9671233 lei la 12.06.2026 și 1,9726027 lei la 13.03.2026.
      expect(accruedInterest(issue, mat, 8, const [], DateTime.utc(2026, 6, 12)), closeTo(3.9671233, 1e-6));
      expect(accruedInterest(issue, mat, 8, const [], DateTime.utc(2026, 3, 13)), closeTo(1.9726027, 1e-6));
    });
    test('randament la paritate ≈ cupon capitalizat anual', () {
      final i = DateTime.utc(2026, 10, 9);
      final m = DateTime.utc(2028, 10, 9);
      final flows = [...bondCoupons(i, m, 7.75, const []), CashFlow(m, 100, isCoupon: false)];
      expect(bondYield(100, flows, i), closeTo(7.90, 0.01));
    });
  });

  group('Portofoliu', () {
    final h = Holding(
      id: '1',
      isin: 'MD4003005296',
      type: 'BT',
      termLabel: '364 zile',
      issueDate: DateTime(2026, 11, 5),
      maturity: DateTime(2027, 11, 4),
      purchaseDate: DateTime(2026, 11, 5),
      price: 88.83,
      quantity: 1000,
    );
    test('rata dobânzii = rentabilitatea când cumpărarea e la emitere', () {
      final m = computeMetrics(h, today: DateTime(2026, 11, 12));
      expect(m.nominalRate, closeTo(m.investmentReturn, 1e-9));
      expect(m.principalAtMaturity, 100000);
      expect(m.cost, closeTo(88830, 1e-6));
      expect(m.interest, closeTo(11170, 1e-6));
    });
    test('cumpărare ulterioară crește rentabilitatea la același preț', () {
      final later = h.copyWith(purchaseDate: DateTime(2027, 5, 5));
      final m = computeMetrics(later, today: DateTime(2027, 5, 6));
      expect(m.investmentReturn, greaterThan(m.nominalRate));
    });
    test('export / import', () {
      final back = PortfolioStore.decode(PortfolioStore.encode([h]));
      expect(back.single.isin, h.isin);
      expect(back.single.quantity, 1000);
      expect(back.single.purchaseDate, DateTime(2026, 11, 5));
    });
    test('migrare din v2', () {
      final m = Holding.fromV2({
        'id': 'x', 'name': 'MD4003005296', 'kind': 'Bon de trezorerie', 'nominal': 10000,
        'purchasePrice': 8883, 'annualCoupon': 0, 'purchaseDate': '2026-11-05T00:00:00.000', 'maturity': '2027-11-04T00:00:00.000',
      })!;
      expect(m.quantity, 100);
      expect(m.price, closeTo(88.83, 1e-9));
    });
  });

  test('setul de date inclus trece validarea', () {
    final j = jsonDecode(File('assets/data/vms_data.json').readAsStringSync()) as Map<String, dynamic>;
    final d = VmsDataset.fromJson(j);
    expect(DataRepository.validate(d), isNull);
    // ultima licitație: cel puțin un termen, toate din aceeași zi (BT are 3 termene, OS de regulă unul)
    expect(d.lastAuction, isNotEmpty);
    expect(d.lastAuction.map((a) => a.auctionDate).toSet().length, 1);
    expect(d.calendar, isNotEmpty);
  });

  group('Dobândă flotantă (MD4004001583: BT 182 zile + 1,00 p.p.)', () {
    final issue = DateTime.utc(2024, 3, 15);
    final mat = DateTime.utc(2031, 3, 15);
    final announced = {DateTime.utc(2026, 3, 15): 10.32, DateTime.utc(2026, 9, 15): 10.54, DateTime.utc(2027, 3, 15): 10.95};
    final h = Holding(
      id: 'f',
      isin: 'MD4004001583',
      type: 'OS',
      termLabel: '7 ani',
      issueDate: issue,
      maturity: mat,
      purchaseDate: DateTime.utc(2026, 3, 15),
      price: 100,
      quantity: 10,
      couponType: 'flotant',
      margin: 1.0,
      couponHistory: announced,
    );

    test('cupoanele anunțate folosesc rata publicată de MF', () {
      final c = bondCouponsWith(issue, mat, CouponRates.floating(announced, 1.0), const []);
      final sep = c.firstWhere((x) => x.date == DateTime.utc(2026, 9, 15));
      expect(sep.amount, closeTo(couponAmount(10.54, 184), 1e-9));
      expect(sep.estimated, isFalse);
    });

    test('următorul cupon și estimările', () {
      final m = computeMetrics(h, today: DateTime.utc(2026, 11, 12));
      expect(m.floating, isTrue);
      expect(m.nextCouponDate, DateTime.utc(2027, 3, 15));
      expect(m.nextCouponRate, closeTo(10.95, 1e-9));
      expect(m.nextCouponEstimated, isFalse);
      expect(m.hasEstimates, isTrue);
      expect(m.couponsTotal, greaterThan(0));
    });

    test('cupon neanunțat = ultima rată BT 182 zile + marja', () {
      FloatingRates.reference = 9.0;
      expect(const CouponRates.floating({}, 1.0).rateFor(DateTime.utc(2028, 3, 15)), 10.0);
      FloatingRates.reference = null;
    });

    test('poziția flotantă se salvează și se reîncarcă', () {
      final back = Holding.fromJson(h.toJson());
      expect(back.isFloating, isTrue);
      expect(back.margin, 1.0);
      expect(back.couponHistory[DateTime.utc(2027, 3, 15)], 10.95);
    });
  });

  group('Alerte de scadență (notificări locale)', () {
    Holding bt(String isin, DateTime mat, int qty) => Holding(
          id: isin,
          isin: isin,
          type: 'BT',
          termLabel: '91 zile',
          issueDate: mat.subtract(const Duration(days: 91)),
          maturity: mat,
          purchaseDate: mat.subtract(const Duration(days: 91)),
          price: 97,
          quantity: qty,
        );
    final all = {for (final k in kMaturityOffsets.keys) k: true};

    test('14, 7 și 1 zi înainte, grupate pe scadență', () {
      final now = DateTime(2026, 11, 12, 15);
      final mat = DateTime(2026, 12, 3);
      final plan = maturityPlan([bt('MD4003000001', mat, 10), bt('MD4003000002', mat, 5)], all, now);
      expect(plan.map((p) => p.day).toList(), [DateTime.utc(2026, 11, 19), DateTime.utc(2026, 11, 26), DateTime.utc(2026, 12, 2)]);
      expect(plan.last.title, 'Scadență mâine: 2 poziții');
      expect(plan.last.body, contains('1.500,00 lei'));
      expect(plan.map((p) => p.id).toSet().length, 3);
    });

    test('respectă comutatoarele și nu programează în trecut', () {
      final h = [bt('MD4003000001', DateTime(2026, 12, 3), 1)];
      final noTomorrow = {...all, 'maturity1': false};
      expect(maturityPlan(h, noTomorrow, DateTime(2026, 11, 20)).map((p) => p.day).toList(), [DateTime.utc(2026, 11, 26)]);
      expect(maturityPlan(h, noTomorrow, DateTime(2026, 11, 28)), isEmpty);
    });

    test('titlurile scadente nu generează alerte', () {
      expect(maturityPlan([bt('MD4003000001', DateTime(2026, 11, 1), 1)], all, DateTime(2026, 11, 12)), isEmpty);
    });
  });

  test('calendarul include licitațiile din comunicatele de plasare, fără dubluri', () {
    final d = VmsDataset.fromJson(jsonDecode(File('assets/data/vms_data.json').readAsStringSync()) as Map<String, dynamic>);
    final latest = d.securities.map((s) => s.auctionDate).reduce((a, b) => a.isAfter(b) ? a : b);
    final planned = plannedAuctions(d, latest);
    final day = planned[DateTime(latest.year, latest.month, latest.day)]!;
    expect(day, isNotEmpty);
    final keys = day.map((e) => '${e.type}${e.term.replaceAll(RegExp(r'[^0-9]'), '')}').toList();
    expect(keys.toSet().length, keys.length);
  });
  test('arhiva 2009–2026: rate BT și statistica OS', () {
    final d = VmsDataset.fromJson(jsonDecode(File('assets/data/vms_data.json').readAsStringSync()) as Map<String, dynamic>);
    expect(d.rates.first.date.year, 2009);
    final pts = bondPoints(d);
    expect(pts.length, greaterThan(300));
    expect(pts.map((p) => p.years).toSet(), containsAll(<int>[2, 3, 5, 7, 10]));
    // redeschiderea de 4,93 ani (MD3RM2002947, 17.10.2018) aparține obligațiunii de 5 ani
    expect(pts.where((p) => p.date == DateTime.parse('2018-10-17') && p.years == 5), isNotEmpty);
    expect(pts.any((p) => p.floating), isTrue);
  });
}
