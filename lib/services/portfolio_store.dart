import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/holding.dart';

/// Portofoliul se păstrează doar pe dispozitiv (fără cont), cu export/import JSON
/// pentru backup manual. Formatul are versiune pentru migrări viitoare.
///
/// Protecție la citire: dacă datele salvate nu pot fi citite complet (de exemplu
/// după o schimbare de format), textul original se copiază sub [_unreadableKey]
/// înainte ca o salvare ulterioară să-l suprascrie. Copia nu se șterge niciodată
/// automat; o versiune viitoare care o poate citi o recuperează la pornire.
class PortfolioStore {
  static const _key = 'portfolio_v3';
  static const _legacyKey = 'holdings_v2';
  static const _unreadableKey = 'portfolio_v3_unreadable';
  static const _format = 'vms-moldova-portfolio';

  /// `true` dacă la ultima încărcare au existat date care nu au putut fi citite
  /// (păstrate în siguranță, dar neafișate).
  bool hadUnreadableData = false;

  Future<List<Holding>> load() async {
    final p = await SharedPreferences.getInstance();
    hadUnreadableData = false;
    final raw = p.getString(_key);
    if (raw != null) {
      final r = decodeLenient(raw);
      if (r.skipped > 0 || r.invalid) await _preserve(p, raw);
      if (r.holdings.isNotEmpty || !r.invalid) {
        hadUnreadableData = r.skipped > 0;
        return r.holdings;
      }
      hadUnreadableData = true;
      return [];
    }
    // portofoliul principal lipsește, dar există o copie păstrată anterior:
    // o încercăm (poate versiunea curentă o poate citi)
    final kept = p.getString(_unreadableKey);
    if (kept != null) {
      final r = decodeLenient(kept);
      if (r.holdings.isNotEmpty) {
        await p.setString(_key, encode(r.holdings));
        return r.holdings;
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

  /// Păstrează textul original o singură dată (prima copie necitibilă e cea valoroasă).
  Future<void> _preserve(SharedPreferences p, String raw) async {
    if (p.getString(_unreadableKey) == null) await p.setString(_unreadableKey, raw);
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

  /// Ca [decode], dar nu aruncă: pozițiile care nu pot fi citite sunt sărite și numărate.
  /// `invalid` = textul nu este deloc un portofoliu VMS Moldova.
  static ({List<Holding> holdings, int skipped, bool invalid}) decodeLenient(String raw) {
    Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      return (holdings: const <Holding>[], skipped: 0, invalid: true);
    }
    if (j is! Map<String, dynamic> || j['format'] != _format || j['holdings'] is! List) {
      return (holdings: const <Holding>[], skipped: 0, invalid: true);
    }
    final out = <Holding>[];
    var skipped = 0;
    for (final e in j['holdings'] as List) {
      try {
        out.add(Holding.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        skipped++;
      }
    }
    return (holdings: out, skipped: skipped, invalid: false);
  }
}
