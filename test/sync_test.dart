import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  group('Descărcare doar când datele s-au schimbat (ETag)', () {
    const url = 'https://example.test/vms_data.json';
    setUp(() => SharedPreferences.setMockInitialValues({}));

    String bodyAt(String generatedAt) {
      final j = jsonDecode(File('assets/data/vms_data.json').readAsStringSync()) as Map<String, dynamic>;
      return jsonEncode({...j, 'generated_at': generatedAt});
    }

    test('a doua verificare trimite amprenta și primește 304, fără fișier', () async {
      final v1 = DateTime.now().toUtc().toIso8601String();
      final sent = <String?>[];
      final client = MockClient((req) async {
        final inm = req.headers['If-None-Match'];
        sent.add(inm);
        if (inm == '"v1"') return http.Response('', 304);
        return http.Response.bytes(utf8.encode(bodyAt(v1)), 200, headers: {'etag': '"v1"'});
      });
      final repo = DataRepository(client: client, remoteUrl: url);
      final old = datasetAt(DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String());

      final first = await repo.sync(old, force: true);
      expect(first.status, SyncStatus.updated);
      final second = await repo.sync(first.dataset!, force: true);
      expect(second.status, SyncStatus.upToDate);
      expect(sent, [null, '"v1"']);
    });

    test('date noi pe server: 200 cu fișierul nou și amprentă nouă', () async {
      final v1 = DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String();
      final v2 = DateTime.now().toUtc().toIso8601String();
      var serverVersion = v1;
      final client = MockClient((req) async {
        final tag = '"$serverVersion"';
        if (req.headers['If-None-Match'] == tag) return http.Response('', 304);
        return http.Response.bytes(utf8.encode(bodyAt(serverVersion)), 200, headers: {'etag': tag});
      });
      final repo = DataRepository(client: client, remoteUrl: url);
      final first = await repo.sync(datasetAt('2020-01-01T00:00:00Z'), force: true);
      expect(first.status, SyncStatus.updated);
      serverVersion = v2;
      final second = await repo.sync(first.dataset!, force: true);
      expect(second.status, SyncStatus.updated);
      expect(second.dataset!.generatedAt!.isAtSameMomentAs(DateTime.parse(v2)), isTrue);
    });

    test('dacă datele afișate sunt mai vechi decât amprenta, descarcă fișierul complet', () async {
      final v1 = DateTime.now().toUtc().toIso8601String();
      final sent = <String?>[];
      final client = MockClient((req) async {
        sent.add(req.headers['If-None-Match']);
        return http.Response.bytes(utf8.encode(bodyAt(v1)), 200, headers: {'etag': '"v1"'});
      });
      final repo = DataRepository(client: client, remoteUrl: url);
      final old = datasetAt('2020-01-01T00:00:00Z');
      await repo.sync(old, force: true);
      // de ex. cache-ul local a fost șters și aplicația a revenit la datele din APK
      await repo.sync(old, force: true);
      expect(sent, [null, null]);
    });

    test('fișier respins: amprenta nu se păstrează', () async {
      final sent = <String?>[];
      final client = MockClient((req) async {
        sent.add(req.headers['If-None-Match']);
        return http.Response.bytes(utf8.encode(jsonEncode({'schema': 999})), 200, headers: {'etag': '"bad"'});
      });
      final repo = DataRepository(client: client, remoteUrl: url);
      final now = datasetAt(DateTime.now().toUtc().toIso8601String());
      expect((await repo.sync(now, force: true)).status, isNot(SyncStatus.updated));
      await repo.sync(now, force: true);
      expect(sent, [null, null]);
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
