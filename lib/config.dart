/// Configurație centrală. Valorile pot fi suprascrise la build:
///   flutter build apk --release --dart-define=VMS_DATA_URL=https://.../vms_data.json
library;

/// Adresa fișierului JSON publicat de pipeline-ul automat (GitHub Actions).
/// Gol = aplicația folosește doar datele incluse în APK.
const String kRemoteDataUrl = String.fromEnvironment('VMS_DATA_URL', defaultValue: '');

/// Nu verificăm serverul mai des de atât când aplicația este deschisă.
const Duration kSyncMinInterval = Duration(minutes: 30);

/// Versiunea schemei de date înțeleasă de această aplicație.
const int kDataSchema = 1;

/// Valoarea nominală standard a unei VMS (Regulament VMS, pct. 7).
const double kNominal = 100;

const String kAppVersion = '3.3.0';

/// Firebase (notificări despre licitații). Valorile vin din google-services.json,
/// transmise la build prin --dart-define (vezi .github/workflows/build-apk.yml).
/// Goale = versiune fără Firebase: alertele de scadență funcționează în continuare.
const String kFirebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const String kFirebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
const String kFirebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const String kFirebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const bool kFirebaseConfigured =
    kFirebaseApiKey != '' && kFirebaseAppId != '' && kFirebaseSenderId != '' && kFirebaseProjectId != '';

const String kCalendarCurrentPdf =
    'https://mf.gov.md/sites/default/files/trimestrul%20IV-2026%20web-rom.pdf';
const String kCalendarsPage =
    'https://mf.gov.md/ro/datoria-sectorului-public/pia%C8%9Ba-primar%C4%83-a-vms/comunicate-privind-plasarea-vms';

const Map<String, String> kSourceLinks = {
  'Calendarul licitațiilor (trim. curent)': kCalendarCurrentPdf,
  'Calendare și comunicate de plasare': kCalendarsPage,
  'Rezultatele licitațiilor': 'https://mf.gov.md/ro/datoria-sectorului-public/pia%C8%9Ba-primar%C4%83-a-vms/licita%C8%9Bii-vms',
  'Rate bonuri de trezorerie': 'https://mf.gov.md/ro/datoria-sectorului-public/ratele-dob%C3%A2nzii-bonuri-de-trezorerie',
  'Rate obligațiuni de stat': 'https://mf.gov.md/ro/datoria-sectorului-public/ratele-dob%C3%A2nzii-obliga%C8%9Biuni-de-stat',
  'Piața secundară': 'https://mf.gov.md/ro/datoria-sectorului-public/tranzac%C8%9Biile-pe-pia%C8%9Ba-secundar%C4%83-a-VMS',
  'Datoria de stat internă': 'https://mf.gov.md/ro/datoria-sectorului-public/rapoarte/datoria-de-stat/datoria-de-stat-intern%C4%83',
  'Regulamentul VMS (BNM)': 'https://www.bnm.md/files/Reg_%20VMS%202025_ro.pdf',
  'BNM – rapoarte VMS': 'https://www.bnm.md/bdi/pages/reports/dop/DOP10.xhtml?id=0&lang=ro',
};
