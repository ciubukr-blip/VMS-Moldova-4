import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vms_moldova/models/holding.dart';
import 'package:vms_moldova/services/portfolio_store.dart';

Holding _h(String id) => Holding(
      id: id,
      isin: 'MD3001000000',
      type: 'BT',
      termLabel: '364 zile',
      issueDate: DateTime(2026, 11, 5),
      maturity: DateTime(2027, 11, 4),
      purchaseDate: DateTime(2026, 11, 5),
      price: 88.83,
      quantity: 1000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Protecția portofoliului la citire', () {
    test('o poziție stricată nu șterge restul, iar originalul e păstrat', () async {
      final j = jsonDecode(PortfolioStore.encode([_h('a'), _h('b')])) as Map<String, dynamic>;
      (j['holdings'] as List).add({'id': 'c', 'isin': 'X'}); // lipsesc câmpuri obligatorii
      final raw = jsonEncode(j);
      SharedPreferences.setMockInitialValues({'portfolio_v3': raw});

      final store = PortfolioStore();
      final list = await store.load();
      expect(list.map((h) => h.id), ['a', 'b']);
      expect(store.hadUnreadableData, isTrue);

      await store.save(list); // salvarea nu mai pierde originalul
      final p = await SharedPreferences.getInstance();
      expect(p.getString('portfolio_v3_unreadable'), raw);
    });

    test('date complet necitibile: portofoliu gol, dar copia rămâne', () async {
      SharedPreferences.setMockInitialValues({'portfolio_v3': '{"format":"alt-format-viitor"}'});
      final store = PortfolioStore();
      expect(await store.load(), isEmpty);
      expect(store.hadUnreadableData, isTrue);
      await store.save([_h('nou')]);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('portfolio_v3_unreadable'), '{"format":"alt-format-viitor"}');
    });

    test('copia păstrată e recuperată când portofoliul principal lipsește', () async {
      SharedPreferences.setMockInitialValues({'portfolio_v3_unreadable': PortfolioStore.encode([_h('x')])});
      final list = await PortfolioStore().load();
      expect(list.single.id, 'x');
      final p = await SharedPreferences.getInstance();
      expect(p.getString('portfolio_v3'), isNotNull);
    });

    test('portofoliu valid: nimic de păstrat', () async {
      SharedPreferences.setMockInitialValues({'portfolio_v3': PortfolioStore.encode([_h('a')])});
      final store = PortfolioStore();
      expect((await store.load()).single.id, 'a');
      expect(store.hadUnreadableData, isFalse);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('portfolio_v3_unreadable'), isNull);
    });

    test('decodeLenient respinge textul care nu e export', () {
      expect(PortfolioStore.decodeLenient('nu e json').invalid, isTrue);
      expect(PortfolioStore.decodeLenient('{"a":1}').invalid, isTrue);
    });
  });
}
