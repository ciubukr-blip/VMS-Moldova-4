import 'package:flutter_test/flutter_test.dart';
import 'package:vms_moldova/services/app_update.dart';

Map<String, dynamic> release(String tag, {bool withApk = true}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/u/r/releases/tag/$tag',
      'assets': [
        if (withApk) {'name': 'vms-moldova-20.apk', 'browser_download_url': 'https://github.com/u/r/releases/download/$tag/vms-moldova-20.apk'},
      ],
    };

void main() {
  test('o compilare mai nouă este oferită ca actualizare', () {
    final u = AppUpdateService.parseRelease(release('apk-20'), 16);
    expect(u, isNotNull);
    expect(u!.build, 20);
    expect(u.apkUrl, endsWith('.apk'));
  });

  test('aceeași compilare sau una mai veche nu este actualizare', () {
    expect(AppUpdateService.parseRelease(release('apk-16'), 16), isNull);
    expect(AppUpdateService.parseRelease(release('apk-12'), 16), isNull);
  });

  test('etichete străine sau release fără APK sunt ignorate', () {
    expect(AppUpdateService.parseRelease(release('v2.0'), 16), isNull);
    expect(AppUpdateService.parseRelease(release('apk-30', withApk: false), 16), isNull);
  });
}
