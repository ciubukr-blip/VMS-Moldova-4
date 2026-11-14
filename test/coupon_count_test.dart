import 'package:flutter_test/flutter_test.dart';
import 'package:vms_moldova/models/dataset.dart';
import 'package:vms_moldova/models/holding.dart';
import 'package:vms_moldova/screens/auctions_screen.dart';
import 'package:vms_moldova/services/finance.dart';

/// OS pe 3 ani, 6 cupoane semestriale, emisă la 12.06.2026.
Holding _bond({required DateTime purchase}) => Holding(
      id: 'os',
      isin: 'MD4004001096',
      type: 'OS',
      termLabel: '3 ani',
      issueDate: DateTime(2026, 6, 12),
      maturity: DateTime(2029, 6, 12),
      purchaseDate: purchase,
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
    );

CalendarEntry _planned(String? volume) => CalendarEntry(
      quarter: '2026-Q4',
      auctionDate: DateTime(2026, 11, 17),
      settlementDate: DateTime(2026, 11, 19),
      type: 'BT',
      term: '182 zile',
      volume: volume,
    );

void main() {
  group('Numărul de cupoane', () {
    test('cumpărată la emitere, înaintea celui de-al 3-lea cupon', () {
      final c = couponCount(_bond(purchase: DateTime(2026, 6, 12)), today: DateTime(2027, 9, 1))!;
      expect(c.total, 6);
      expect(c.mine, 6);
      expect(c.received, 2);
      expect(c.nextOrdinal, 3);
      expect(c.next, DateTime(2027, 12, 12));
    });

    test('cumpărată pe piața secundară: doar cupoanele de după cumpărare îi revin', () {
      final c = couponCount(_bond(purchase: DateTime(2027, 7, 1)), today: DateTime(2027, 8, 1))!;
      expect(c.mine, 4);
      expect(c.total, 6);
      expect(c.received, 0);
      expect(c.nextOrdinal, 3);
    });

    test('cuponul din ziua cumpărării nu îi revine cumpărătorului', () {
      final c = couponCount(_bond(purchase: DateTime(2027, 6, 12)), today: DateTime(2027, 6, 12))!;
      expect(c.mine, 4);
    });

    test('cuponul de azi se numără ca încasat', () {
      final c = couponCount(_bond(purchase: DateTime(2026, 6, 12)), today: DateTime(2027, 12, 12))!;
      expect(c.received, 3);
      expect(c.nextOrdinal, 4);
    });

    test('după scadență: toate încasate, niciun cupon următor', () {
      final c = couponCount(_bond(purchase: DateTime(2026, 6, 12)), today: DateTime(2030, 1, 1))!;
      expect(c.received, 6);
      expect(c.next, isNull);
      expect(c.nextOrdinal, isNull);
    });

    test('bonurile de trezorerie nu au cupoane', () {
      final bt = Holding(
        id: 'bt',
        isin: 'MD3001000000',
        type: 'BT',
        termLabel: '364 zile',
        issueDate: DateTime(2026, 11, 5),
        maturity: DateTime(2027, 11, 4),
        purchaseDate: DateTime(2026, 11, 5),
        price: 88.83,
        quantity: 1000,
      );
      expect(couponCount(bt), isNull);
    });
  });

  group('Totalul planificat la licitație', () {
    test('adună capătul maxim al fiecărui interval', () {
      expect(plannedMaxTotal([_planned('30-60'), _planned('1200-1400'), _planned('1400-1800')]), 3260);
    });

    test('ignoră titlurile fără volum; null dacă niciunul nu are', () {
      expect(plannedMaxTotal([_planned(null), _planned('30-50')]), 50);
      expect(plannedMaxTotal([_planned(null)]), isNull);
    });

    test('acceptă o singură valoare și separatorul de mii cu spațiu', () {
      expect(plannedMaxTotal([_planned('500'), _planned('1 200 - 1 400')]), 1900);
    });
  });
}
