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
  DataRepository({http.Client? client, String? remoteUrl})
      : _client = client,
        _remoteUrl = remoteUrl ?? kRemoteDataUrl;

  final http.Client? _client;
  final String _remoteUrl;

  static const _cacheKey = 'vms_data_cache_v1';
  static const _checkedKey = 'vms_data_checked_at';

  /// Amprenta (ETag) ultimei versiuni primite de la server, cu adresa și versiunea
  /// datelor (generated_at) la care se referă. Cu ea, serverul răspunde „304 – nemodificat”
  /// (câteva sute de bytes) în loc să trimită din nou tot fișierul.
  static const _etagKey = 'vms_data_etag_v1';

  /// Versiunea datelor anunțată de o notificare push (generated_at), încă neprimită.
  static const _expectedKey = 'vms_data_expected';

  /// Notificare fără versiune (robot mai vechi): o singură sincronizare forțată.
  static const _forceKey = 'vms_data_force_sync';

  /// O notificare mai veche de atât nu mai forțează sincronizarea.
  static const _expectedMaxAge = Duration(hours: 24);

  /// Ține minte că o notificare a anunțat date noi. Rulează și în fundal
  /// (handler-ul FCM are propriul isolate), deci folosește doar SharedPreferences.
  static Future<void> rememberEvent(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final v = DateTime.tryParse('${data['generated_at'] ?? ''}');
    if (v == null) {
      await prefs.setBool(_forceKey, true);
      return;
    }
    final old = DateTime.tryParse(prefs.getString(_expectedKey) ?? '');
    if (old == null || v.isAfter(old)) await prefs.setString(_expectedKey, v.toIso8601String());
  }

  /// true dacă o notificare a anunțat date pe care [current] încă nu le are.
  Future<bool> pendingUpdate(VmsDataset current) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // valoarea poate fi scrisă de handler-ul din fundal
    if (prefs.getBool(_forceKey) ?? false) return true;
    final expected = DateTime.tryParse(prefs.getString(_expectedKey) ?? '');
    if (expected == null) return false;
    final have = current.generatedAt;
    final reached = have != null && !have.isBefore(expected);
    final stale = DateTime.now().difference(expected) > _expectedMaxAge;
    if (reached || stale) {
      await prefs.remove(_expectedKey);
      return false;
    }
    return true;
  }

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
    if (_remoteUrl.isEmpty) {
      return const SyncResult(SyncStatus.disabled, 'Sincronizarea online nu este configurată în această versiune.');
    }
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_checkedKey) ?? '');
    if (!force && last != null && DateTime.now().difference(last) < kSyncMinInterval) {
      return const SyncResult(SyncStatus.upToDate, 'Verificat recent.');
    }
    try {
      var uri = Uri.parse(_remoteUrl);
      if (force) {
        // raw.githubusercontent.com păstrează fișierul în cache ~5 minute; parametrul ocolește cache-ul
        uri = uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().millisecondsSinceEpoch}'});
      }
      final etag = _usableEtag(prefs, current);
      final headers = <String, String>{if (etag != null) 'If-None-Match': etag};
      final client = _client ?? http.Client();
      final http.Response resp;
      try {
        resp = await client.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      } finally {
        if (_client == null) client.close();
      }
      await prefs.setString(_checkedKey, DateTime.now().toIso8601String());
      if (resp.statusCode == 304) {
        // serverul confirmă că avem deja ultima versiune
        await prefs.remove(_forceKey);
        return const SyncResult(SyncStatus.upToDate, 'Datele sunt la zi.');
      }
      if (resp.statusCode != 200) {
        return SyncResult(SyncStatus.offline, 'Serverul a răspuns ${resp.statusCode}.');
      }
      final body = utf8.decode(resp.bodyBytes);
      final remote = VmsDataset.fromJson(jsonDecode(body) as Map<String, dynamic>);
      final problem = validate(remote);
      if (problem != null) {
        await prefs.remove(_etagKey); // nu reținem amprenta unui fișier respins
        return SyncResult(SyncStatus.invalid, 'Date respinse: $problem');
      }
      await prefs.remove(_forceKey); // sincronizarea cerută de notificare a avut loc
      final newer = _newer(remote, current);
      if (newer) await prefs.setString(_cacheKey, body);
      await _saveEtag(prefs, resp.headers['etag'], newer ? remote : current);
      if (!newer) return const SyncResult(SyncStatus.upToDate, 'Datele sunt la zi.');
      return SyncResult(SyncStatus.updated, 'Date actualizate.', remote);
    } catch (e) {
      return const SyncResult(SyncStatus.offline, 'Fără conexiune – folosim datele salvate.');
    }
  }

  /// Adresa fără parametri (fără `?t=...`), ca amprenta să fie valabilă și la sincronizarea forțată.
  String get _baseUrl => _remoteUrl.split('?').first;

  /// Amprenta se trimite doar dacă e pentru aceeași adresă și dacă datele afișate
  /// sunt cel puțin la fel de noi ca versiunea la care se referă. Altfel (cache șters,
  /// adresă schimbată, date mai vechi) descărcăm fișierul complet, ca înainte.
  String? _usableEtag(SharedPreferences prefs, VmsDataset current) {
    final raw = prefs.getString(_etagKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final etag = j['etag'] as String?;
      final version = DateTime.tryParse('${j['version'] ?? ''}');
      final have = current.generatedAt;
      if (etag == null || etag.isEmpty || j['url'] != _baseUrl) return null;
      if (version == null || have == null || have.isBefore(version)) return null;
      return etag;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveEtag(SharedPreferences prefs, String? etag, VmsDataset content) async {
    final version = content.generatedAt;
    if (etag == null || etag.isEmpty || version == null) {
      await prefs.remove(_etagKey);
      return;
    }
    await prefs.setString(_etagKey, jsonEncode({'url': _baseUrl, 'etag': etag, 'version': version.toIso8601String()}));
  }
}
