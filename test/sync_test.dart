import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vms_moldova/config.dart';
import 'package:vms_moldova/models/dataset.dart';
import 'package:vms_moldova/services/data_repository.dart';

VmsDataset datasetAt(String generatedAt) {
  final j = jsonDecode(File('assets/data/vms_data.json').readAsStringSync()) as Map<String, dynamic>;
  return VmsDataset.fromJson({...j, 'generated_at': generatedAt});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sincronizare forțată după notificare', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('fără notificare nu se forțează nimic', () async {
      final now = DateTime.now().toUtc().toIso8601String();
      expect(await DataRepository().pendingUpdate(datasetAt(now)), isFalse);
    });

    test('se forțează până sosește versiunea anunțată', () async {
      final announced = DateTime.now().toUtc();
      await DataRepository.rememberEvent({'event': 'results:x', 'generated_at': announced.toIso8601String()});
      final repo = DataRepository();
      final older = datasetAt(announced.subtract(const Duration(hours: 3)).toIso8601String());
      expect(await repo.pendingUpdate(older), isTrue);
      expect(await repo.pendingUpdate(datasetAt(announced.toIso8601String())), isFalse);
      // după ce a sosit, nu mai forțează nici pentru o copie veche
      expect(await repo.pendingUpdate(older), isFalse);
    });

    test('o notificare mai veche de o zi nu mai forțează', () async {
      final announced = DateTime.now().toUtc().subtract(const Duration(days: 2));
      await DataRepository.rememberEvent({'generated_at': announced.toIso8601String()});
      final older = datasetAt(announced.subtract(const Duration(hours: 1)).toIso8601String());
      expect(await DataRepository().pendingUpdate(older), isFalse);
    });

    test('notificare fără versiune: forțează o sincronizare', () async {
      await DataRepository.rememberEvent({'event': 'launch:x'});
      final now = DateTime.now().toUtc().toIso8601String();
      expect(await DataRepository().pendingUpdate(datasetAt(now)), isTrue);
    });
  });

  test('linkul calendarului MF urmează trimestrul curent, inclusiv la schimbarea anului', () {
    expect(calendarPdfUrl(DateTime(2026, 11, 13)),
        'https://mf.gov.md/sites/default/files/trimestrul%20IV-2026%20web-rom.pdf');
    expect(calendarPdfUrl(DateTime(2027, 1, 2)),
        'https://mf.gov.md/sites/default/files/trimestrul%20I-2027%20web-rom.pdf');
    expect(calendarPdfUrl(DateTime(2027, 6, 30)), contains('trimestrul%20II-2027'));
  });
}
