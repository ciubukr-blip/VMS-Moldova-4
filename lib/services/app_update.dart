import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// O versiune nouă a aplicației publicată în GitHub Releases.
class AppUpdate {
  final int build;
  final String apkUrl;
  final String pageUrl;
  const AppUpdate({required this.build, required this.apkUrl, required this.pageUrl});
}

/// Verifică în GitHub Releases dacă există un APK mai nou decât cel instalat.
///
/// Workflow-ul „Compilare APK” publică fiecare compilare cu eticheta `apk-<număr>`
/// și transmite același număr aplicației prin `--dart-define=APP_BUILD`. Un APK cu
/// număr mai mare, semnat cu aceeași cheie, se instalează peste cel vechi și
/// păstrează portofoliul și setările.
class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client;
  final http.Client? _client;

  static bool get enabled => kGithubRepo.isNotEmpty && kAppBuild > 0;

  /// Returnează actualizarea disponibilă, `null` dacă aplicația e la zi.
  /// Aruncă excepție la erori de rețea, ca interfața să poată afișa un mesaj.
  Future<AppUpdate?> check() async {
    if (!enabled) return null;
    final client = _client ?? http.Client();
    try {
      final res = await client.get(
        Uri.parse('https://api.github.com/repos/$kGithubRepo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) return null; // nicio versiune publicată încă
      if (res.statusCode != 200) throw Exception('GitHub a răspuns ${res.statusCode}');
      return parseRelease(jsonDecode(res.body) as Map<String, dynamic>, kAppBuild);
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Extrage actualizarea dintr-un răspuns `releases/latest`, dacă e mai nouă decât [installed].
  static AppUpdate? parseRelease(Map<String, dynamic> release, int installed) {
    final tag = '${release['tag_name'] ?? ''}';
    final m = RegExp(r'^apk-(\d+)$').firstMatch(tag);
    if (m == null) return null;
    final build = int.parse(m.group(1)!);
    if (build <= installed) return null;
    final assets = (release['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final apk = assets.firstWhere(
      (a) => '${a['name']}'.toLowerCase().endsWith('.apk'),
      orElse: () => const {},
    );
    final url = '${apk['browser_download_url'] ?? ''}';
    if (url.isEmpty) return null;
    return AppUpdate(build: build, apkUrl: url, pageUrl: '${release['html_url'] ?? url}');
  }
}
