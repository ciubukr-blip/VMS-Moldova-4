// Pregătește proiectul Android generat de `flutter create` pentru publicare.
// Rulează din rădăcina proiectului:  dart run tool/setup_android.dart
//
// Ce face (idempotent – poate fi rulat de mai multe ori):
//  1. applicationId definitiv: md.vmsmoldova.app (identitatea în Google Play, nu se mai schimbă după publicare)
//  2. semnare release din android/key.properties (cheia ta, nu cheia de debug)
//  3. permisiunea INTERNET (necesară sincronizării datelor) și numele „VMS Moldova”
//  4. <queries> pentru deschiderea linkurilor https (url_launcher, Android 11+)
//  5. .gitignore pentru cheie și parole
//  6. core library desugaring (necesar pentru flutter_local_notifications)
//  7. notificări: POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED și receptoarele pentru alertele programate
import 'dart:io';

const appId = 'md.vmsmoldova.app';
const marker = '// vms-moldova: release signing';

void main() {
  final gradleKts = File('android/app/build.gradle.kts');
  final gradleGroovy = File('android/app/build.gradle');
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync() || (!gradleKts.existsSync() && !gradleGroovy.existsSync())) {
    stderr.writeln('Nu găsesc proiectul Android. Rulează întâi:\n'
        '  flutter create . --platforms android --org md.vmsmoldova --project-name vms_moldova');
    exit(1);
  }

  if (gradleKts.existsSync()) {
    _patchKts(gradleKts);
  } else {
    stderr.writeln('Proiect Groovy (build.gradle) detectat. Actualizează Flutter (proiectele noi folosesc build.gradle.kts) '
        'sau aplică manual pașii din README, secțiunea „Semnare”.');
    exit(1);
  }
  _patchManifest(manifest);
  _patchGitignore();

  final keyProps = File('android/key.properties');
  stdout.writeln('\n✔ Android pregătit (applicationId $appId).');
  if (!keyProps.existsSync()) {
    stdout.writeln('⚠ Lipsește android/key.properties – build-ul release va fi semnat cu cheia de DEBUG\n'
        '  și NU poate fi publicat. Vezi README → „Cheia de semnare”.');
  } else {
    stdout.writeln('✔ android/key.properties găsit – release-ul va fi semnat cu cheia ta.');
  }
}

void _patchKts(File f) {
  var s = f.readAsStringSync();
  final original = s;

  // 1. applicationId
  s = s.replaceAllMapped(RegExp(r'applicationId\s*=\s*"[^"]*"'), (_) => 'applicationId = "$appId"');

  // 2. semnare
  if (!s.contains(marker)) {
    if (!s.contains('import java.util.Properties')) {
      s = 'import java.util.Properties\nimport java.io.FileInputStream\n\n$s';
    }
    const loader = '''
$marker
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

''';
    final androidIdx = s.indexOf(RegExp(r'^android\s*\{', multiLine: true));
    if (androidIdx < 0) _fail('nu găsesc blocul android { } în ${f.path}');
    s = s.replaceRange(androidIdx, androidIdx, loader);

    const signing = '''
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

''';
    final btIdx = s.indexOf(RegExp(r'^\s*buildTypes\s*\{', multiLine: true));
    if (btIdx < 0) _fail('nu găsesc buildTypes { } în ${f.path}');
    s = s.replaceRange(btIdx, btIdx, signing);

    final debugLine = RegExp(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)');
    if (!debugLine.hasMatch(s)) _fail('nu găsesc linia signingConfig = signingConfigs.getByName("debug")');
    s = s.replaceFirst(
      debugLine,
      'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
    );
  }

  // 3. core library desugaring (cerut de flutter_local_notifications)
  if (!s.contains('isCoreLibraryDesugaringEnabled')) {
    final co = RegExp(r'compileOptions\s*\{');
    if (!co.hasMatch(s)) _fail('nu găsesc compileOptions { } în ${f.path}');
    s = s.replaceFirstMapped(co, (m) => '${m[0]}\n        isCoreLibraryDesugaringEnabled = true');
  }
  if (!s.contains('desugar_jdk_libs')) {
    s = '${s.trimRight()}\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n';
  }

  if (s != original) {
    f.writeAsStringSync(s);
    stdout.writeln('✔ ${f.path} actualizat');
  } else {
    stdout.writeln('• ${f.path} era deja configurat');
  }
}

void _patchManifest(File f) {
  var s = f.readAsStringSync();
  final original = s;
  if (!s.contains('android.permission.INTERNET')) {
    s = s.replaceFirst(RegExp(r'<application'), '<uses-permission android:name="android.permission.INTERNET"/>\n    <application');
  }
  s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="VMS Moldova"');
  // notificări: permisiunea Android 13+ și reprogramarea alertelor de scadență după repornirea telefonului
  for (final perm in ['android.permission.POST_NOTIFICATIONS', 'android.permission.RECEIVE_BOOT_COMPLETED']) {
    if (!s.contains(perm)) {
      s = s.replaceFirst(RegExp(r'<application'), '<uses-permission android:name="$perm"/>\n    <application');
    }
  }
  if (!s.contains('ScheduledNotificationReceiver')) {
    s = s.replaceFirst(
      '</application>',
      '    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n'
          '        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n'
          '            <intent-filter>\n'
          '                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n'
          '                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n'
          '                <action android:name="android.intent.action.QUICKBOOT_POWERON" />\n'
          '                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n'
          '            </intent-filter>\n'
          '        </receiver>\n'
          '    </application>',
    );
  }
  if (!s.contains('android:scheme="https"')) {
    s = s.replaceFirst(
      '</manifest>',
      '    <queries>\n'
          '        <intent>\n'
          '            <action android:name="android.intent.action.VIEW" />\n'
          '            <data android:scheme="https" />\n'
          '        </intent>\n'
          '    </queries>\n'
          '</manifest>',
    );
  }
  if (s != original) {
    f.writeAsStringSync(s);
    stdout.writeln('✔ ${f.path} actualizat');
  } else {
    stdout.writeln('• ${f.path} era deja configurat');
  }
}

void _patchGitignore() {
  final f = File('.gitignore');
  final s = f.existsSync() ? f.readAsStringSync() : '';
  const lines = ['android/key.properties', '*.jks', '*.keystore'];
  final missing = lines.where((l) => !s.split('\n').contains(l)).toList();
  if (missing.isEmpty) return;
  f.writeAsStringSync('$s${s.endsWith('\n') || s.isEmpty ? '' : '\n'}# cheia de semnare – nu o publica niciodată\n${missing.join('\n')}\n');
  stdout.writeln('✔ .gitignore actualizat');
}

Never _fail(String msg) {
  stderr.writeln('✖ $msg\nAplică manual pașii din README, secțiunea „Semnare”.');
  exit(1);
}
