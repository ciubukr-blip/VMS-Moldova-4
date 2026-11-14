import 'dart:io';

import 'package:flutter/services.dart';

import '../models/holding.dart';
import 'portfolio_store.dart';

/// Copii ale portofoliului care supraviețuiesc dezinstalării aplicației.
///
/// Fișierele se scriu în `Descărcări/VMS Moldova/` prin MediaStore (Android 10+,
/// fără permisiuni). Folderul Descărcări nu se șterge la dezinstalare, deci copia
/// poate fi aleasă la restaurare cu selectorul de fișiere al sistemului.
/// Partea nativă este în `MainActivity.kt`, scrisă de `tool/setup_android.dart`.
class PortfolioBackup {
  static const _channel = MethodChannel('md.vmsmoldova/backup');

  /// Folderul în care se salvează copiile, așa cum îl vede utilizatorul.
  static const folderLabel = 'Descărcări › VMS Moldova';

  static String _fileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'portofoliu-${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
  }

  /// Salvează portofoliul într-un fișier nou. Returnează calea relativă
  /// (ex. `Download/VMS Moldova/portofoliu-….json`) sau `null` dacă nu s-a putut
  /// (alt sistem decât Android, Android sub 10, eroare).
  static Future<String?> saveToFile(List<Holding> holdings, {DateTime? now}) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('save', {
        'name': _fileName(now ?? DateTime.now()),
        'content': PortfolioStore.encode(holdings),
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Salvează un fișier text oarecare (ex. CSV) în același folder din Descărcări.
  static Future<String?> saveText(String name, String content, {String mime = 'text/plain'}) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('save', {'name': name, 'content': content, 'mime': mime});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Deschide selectorul de fișiere și returnează conținutul fișierului ales
  /// (`null` dacă utilizatorul a renunțat sau selectorul nu e disponibil).
  static Future<String?> pickFile() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('pick');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Copia de siguranță dinaintea unei actualizări: fișier în Descărcări și,
  /// în plus, clipboard-ul (de unde aplicația reinstalată îl găsește singură).
  /// Returnează calea fișierului salvat, dacă s-a putut.
  static Future<String?> beforeUpdate(List<Holding> holdings) async {
    if (holdings.isEmpty) return null;
    await Clipboard.setData(ClipboardData(text: PortfolioStore.encode(holdings)));
    return saveToFile(holdings);
  }
}
