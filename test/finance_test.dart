import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vms_moldova/models/dataset.dart';
import 'package:vms_moldova/models/holding.dart';
import 'package:vms_moldova/services/data_repository.dart';
import 'package:vms_moldova/services/finance.dart';
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
    expect(d.lastAuction.length, 3);
    expect(d.calendar, isNotEmpty);
  });
}
