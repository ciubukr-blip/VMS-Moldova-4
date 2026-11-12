import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/holding.dart';

/// Portofoliul se păstrează doar pe dispozitiv (fără cont), cu export/import JSON
/// pentru backup manual. Formatul are versiune pentru migrări viitoare.
class PortfolioStore {
  static const _key = 'portfolio_v3';
  static const _legacyKey = 'holdings_v2';
  static const _format = 'vms-moldova-portfolio';

  Future<List<Holding>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null) {
      try {
        return decode(raw);
      } catch (_) {
        return [];
      }
    }
    // migrare automată din versiunea 2
    final legacy = p.getString(_legacyKey);
    if (legacy == null) return [];
    try {
      final list = (jsonDecode(legacy) as List)
          .map((e) => Holding.fromV2(e as Map<String, dynamic>))
          .whereType<Holding>()
          .toList();
      await save(list);
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Holding> holdings) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, encode(holdings));
  }

  static String encode(List<Holding> holdings) => jsonEncode({
        'format': _format,
        'version': 3,
        'exportedAt': DateTime.now().toIso8601String(),
        'holdings': holdings.map((h) => h.toJson()).toList(),
      });

  /// Aruncă FormatException dacă textul nu este un export valid.
  static List<Holding> decode(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['format'] != _format) {
      throw const FormatException('Nu este un export VMS Moldova');
    }
    return (j['holdings'] as List).map((e) => Holding.fromJson(e as Map<String, dynamic>)).toList();
  }
}
