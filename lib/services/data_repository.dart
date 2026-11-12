import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/dataset.dart';

enum SyncStatus { bundled, cached, updated, upToDate, offline, invalid, disabled }

class SyncResult {
  final SyncStatus status;
  final VmsDataset? dataset;
  final String message;
  const SyncResult(this.status, this.message, [this.dataset]);
}

/// Sursa de date a aplicației:
/// 1. setul inclus în APK (assets/data/vms_data.json) – funcționează offline;
/// 2. ultima copie descărcată și validată (cache local);
/// 3. fișierul publicat de pipeline-ul automat la [kRemoteDataUrl].
///
/// O copie descărcată înlocuiește datele doar dacă trece validarea și este
/// mai nouă decât cea existentă; altfel rămân datele anterioare.
class DataRepository {
  static const _cacheKey = 'vms_data_cache_v1';
  static const _checkedKey = 'vms_data_checked_at';

  Future<VmsDataset> loadLocal() async {
    final bundled = VmsDataset.fromJson(jsonDecode(await rootBundle.loadString('assets/data/vms_data.json')) as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return bundled;
    try {
      final cached = VmsDataset.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (validate(cached) == null && _newer(cached, bundled)) return cached;
    } catch (_) {
      await prefs.remove(_cacheKey);
    }
    return bundled;
  }

  Future<DateTime?> lastChecked() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_checkedKey);
    return s == null ? null : DateTime.tryParse(s);
  }

  /// Returnează null dacă setul de date este acceptabil, altfel motivul.
  static String? validate(VmsDataset d) {
    if (d.schema != kDataSchema) return 'schema ${d.schema} nu este suportată';
    if (d.rates.length < 100) return 'istoric de rate incomplet';
    if (d.securities.isEmpty) return 'lista ISIN goală';
    for (final r in d.rates) {
      if (!(r.minRate > 0 && r.minRate <= r.avgRate && r.avgRate <= r.maxRate && r.maxRate < 40)) {
        return 'rată invalidă la ${r.date}';
      }
    }
    for (final s in d.securities) {
      if (!s.maturity.isAfter(s.issueDate)) return 'ISIN ${s.isin}: scadență invalidă';
    }
    return null;
  }

  static bool _newer(VmsDataset a, VmsDataset b) {
    final ga = a.generatedAt, gb = b.generatedAt;
    if (ga == null) return false;
    if (gb == null) return true;
    return ga.isAfter(gb);
  }

  Future<SyncResult> sync(VmsDataset current, {bool force = false}) async {
    if (kRemoteDataUrl.isEmpty) {
      return const SyncResult(SyncStatus.disabled, 'Sincronizarea online nu este configurată în această versiune.');
    }
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_checkedKey) ?? '');
    if (!force && last != null && DateTime.now().difference(last) < kSyncMinInterval) {
      return const SyncResult(SyncStatus.upToDate, 'Verificat recent.');
    }
    try {
      final resp = await http.get(Uri.parse(kRemoteDataUrl)).timeout(const Duration(seconds: 20));
      await prefs.setString(_checkedKey, DateTime.now().toIso8601String());
      if (resp.statusCode != 200) {
        return SyncResult(SyncStatus.offline, 'Serverul a răspuns ${resp.statusCode}.');
      }
      final body = utf8.decode(resp.bodyBytes);
      final remote = VmsDataset.fromJson(jsonDecode(body) as Map<String, dynamic>);
      final problem = validate(remote);
      if (problem != null) return SyncResult(SyncStatus.invalid, 'Date respinse: $problem');
      if (!_newer(remote, current)) return const SyncResult(SyncStatus.upToDate, 'Datele sunt la zi.');
      await prefs.setString(_cacheKey, body);
      return SyncResult(SyncStatus.updated, 'Date actualizate.', remote);
    } catch (e) {
      return const SyncResult(SyncStatus.offline, 'Fără conexiune – folosim datele salvate.');
    }
  }
}
