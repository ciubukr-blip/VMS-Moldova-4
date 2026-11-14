# VMS Moldova – versiunea 3.3

Aplicație Android (Flutter) pentru valorile mobiliare de stat ale Republicii Moldova:
rate la licitații, calendarul MF, rezultatele licitațiilor și portofoliul personal
calculat conform Regulamentului VMS.

**Autor:** Craciun Radu · © 2026 Craciun Radu. Toate drepturile rezervate – vezi [LICENSE](LICENSE).

## Ce este nou în 3.0

| Zonă | Schimbare |
|---|---|
| Design | Font Inter (inclus), fundal gri deschis, carduri albe rotunjite, accente pastelate, texte mai mici dar lizibile. Cod împărțit în module (`lib/screens`, `lib/services`, `lib/models`, `lib/widgets`, `lib/theme`). |
| Dobânzi | Selectoare compacte (termen, rată, an), axa Y cu `%`, tooltip cu dată și `%`, linie punctată cu eticheta ultimei rate, card „Ultima licitație” cu variația în p.p., statistici pe perioadă. |
| Portofoliu | ISIN ales din baza de date (cu căutare), cu emitere, scadență și cupon completate automat. Câmpuri: preț pentru 100 lei și cantitate. Calculează rata dobânzii, rentabilitatea investiției, dobânda în lei pe poziție, pe titlu și pe total. Pozițiile se pot edita. Încasările viitoare apar pe 12 luni, iar portofoliul are export/import pentru backup. |
| Licitații | Calendar lunar cu zilele de licitație (BT/OS), cardul „Următoarea licitație”, detaliile fiecărei zile și rezultatele ultimei licitații (ISIN, volume, rate min/medie/max, cerere/ofertă, preț mediu). Linkurile spre calendarul trimestrial MF sunt actualizate. |
| Date | Un singur fișier `vms_data.json` (rate, ISIN-uri, rezultate, calendar), inclus în APK și actualizat automat online. |
| Publicare | `applicationId` definitiv, semnare release cu cheia ta, permisiune INTERNET, versiune 3.0.0+3, migrare automată a portofoliului din v2, ecran de confidențialitate și avertisment. |

## Ce este nou în 3.3

- **Grafice cu deplasare și zoom (Dobânzi, BT și OS):** tragere stânga–dreapta, ciupire cu două degete și butoanele −/+/„Toți anii”. Micșorat: toți anii, cu etichete scurte (09, 10 …); mărit: semestre, trimestre, luni. Axa procentelor se adaptează perioadei vizibile, iar la zoom (≤ ~2,5 ani, un singur termen) procentele apar lângă puncte, fără suprapunere. Graficul BT pornește pe „Toți anii”.
- `fl_chart` actualizat la 1.x (zoom nativ).

## Ce este nou în 3.2

- **Arhiva completă 2009–2026:** toate licitațiile de bonuri de trezorerie (91/182/364 zile; fără cele de 21 de zile) și de obligațiuni de stat, cu ISIN, volume, rate și cupoane. Sursa este `data_pipeline/manual/history.json`, generat din Excelul cu rezultatele MF:
  `cd data_pipeline && python -m tools.import_history_xlsx Rezultate_licitatii_VMS_BT_OS_2009-2026.xlsx` (necesită `openpyxl`).
  Arhiva este stratul de bază: datele preluate automat și cele din `manual/` au prioritate, arhiva doar completează golurile.
- **Dobânzi → Obligațiuni de stat:** grafic al ratelor (cuponul stabilit la licitație) pe termene de 2, 3, 5, 7 și 10 ani, filtru dobândă fixă/flotantă și pe ani, ultima rată pe fiecare termen și statistici pe perioadă (minim, medie, maxim, medie ponderată cu volumul, volum plasat, cerere/volum anunțat). Redeschiderile (ex. „4,93 ani”) sunt incluse la termenul inițial.

## Notificări (3.1)

- **Scadențe:** programate pe telefon la 09:00 (ora Chișinăului), cu 14 zile, 7 zile și o zi înainte. Funcționează fără server și fără internet.
- **Licitații:** robotul de date generează evenimente cu id stabil și le trimite prin Firebase Cloud Messaging pe trei subiecte:
  - `licitatii`: comunicat de plasare nou;
  - `rezultate`: rezultatele licitației, rata medie pe fiecare termen;
  - `calendar`: calendar trimestrial nou.

  Aplicația se abonează la aceste subiecte după comutatoarele din ecranul Alerte.
- **Fără spam:** se notifică doar licitațiile viitoare, rezultatele din ultimele 3 zile și calendarele cu licitații viitoare. Arhiva recuperată nu trimite nimic.
- **Configurare:** două secrete în GitHub (Settings → Secrets and variables → Actions):
  - `GOOGLE_SERVICES_JSON`: conținutul fișierului `google-services.json` din Firebase, pentru aplicația Android `md.vmsmoldova.app`;
  - `FIREBASE_SERVICE_ACCOUNT`: cheia JSON a contului de serviciu Firebase, cu care robotul trimite notificările.

  Fără aceste secrete, aplicația și robotul funcționează normal, doar fără notificări despre licitații.
- **Calendarul din aplicație:** afișează și licitațiile anunțate prin comunicatele de plasare, nu doar pe cele din calendarul trimestrial.
- **Date la zi după notificare:** fiecare notificare poartă versiunea datelor (`generated_at`). La primirea ei, sau la deschiderea aplicației după ea, aplicația descarcă imediat fișierul, fără limita de 30 de minute și ocolind cache-ul GitHub. Reîncearcă timp de ~12 minute până primește versiunea anunțată, pentru că robotul face commit după trimitere, iar GitHub poate servi câteva minute copia veche.
- **Linkul „Calendar MF”** se calculează după trimestrul curent (de ex. „trimestrul I-2027”), deci nu mai trebuie schimbat manual la fiecare trimestru.

## Formule (Regulamentul VMS, ed. 2025)

Convenția de zile este Actual/365, iar valoarea nominală este N = 100 lei.

- **Bonuri de trezorerie, pct. 72:** `r = 100 × (N − P) / P × 365 / t`
  - *Rata dobânzii:* t = zile de la emitere la scadență.
  - *Rentabilitatea investiției:* t = zile de la data achiziției la scadență. Dacă data achiziției este data emiterii, cele două rate coincid.
  - *Dobânda:* `cantitate × (100 − P)` lei.
- **Obligațiuni:**
  - Cuponul (pct. 75): `C = N × r/100 × zile_perioadă/365`.
  - Dobânda acumulată la cumpărare (pct. 76): `D = C × n/t`.
  - Randamentul (pct. 74) se obține prin rezolvarea numerică a ecuației prețului (prețul brut include dobânda acumulată).
  - La paritate, randamentul pct. 74 este ușor peste cupon, pentru că formula capitalizează anual.

Formulele au fost verificate pe cifrele oficiale (vezi `test/finance_test.dart`):

- Licitația din 03.11.2026, 364 de zile: formula dă 12,61%, iar MF a publicat 12,61%.
- Dobânda acumulată la MD4004001740: formula dă 3,9671233 lei, exact valoarea din comunicatul MF.

## Compilare (Windows)

```bat
:: 1. o singură dată: generează proiectul Android cu identitatea corectă
flutter create . --platforms android --org md.vmsmoldova --project-name vms_moldova
dart run tool/setup_android.dart

:: 2. dependențe și teste
flutter pub get
flutter test

:: 3. APK / App Bundle (cu sincronizare online, după ce ai publicat datele – vezi mai jos)
flutter build apk --release --dart-define=VMS_DATA_URL=https://raw.githubusercontent.com/UTILIZATOR/REPO/main/data/vms_data.json
flutter build appbundle --release --dart-define=VMS_DATA_URL=...
```

> Dacă ai deja un folder `android/` generat cu `com.example.vms_moldova`, șterge-l înainte de pasul 1.
> Scriptul fixează `applicationId = md.vmsmoldova.app`. **După prima publicare în Google Play acest
> identificator nu se mai poate schimba.** Dacă vrei alt identificator, modifică-l acum în
> `tool/setup_android.dart` (constanta `appId`).

## Cheia de semnare (o singură dată, apoi păstreaz-o în siguranță)

```bat
keytool -genkey -v -keystore %USERPROFILE%\vms-upload-keystore.jks -storetype JKS ^
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Creează `android/key.properties` (este ignorat de git):

```properties
storePassword=PAROLA_TA
keyPassword=PAROLA_TA
keyAlias=upload
storeFile=C:/Users/NUMELE_TAU/vms-upload-keystore.jks
```

Fă o copie a fișierului `.jks` și a parolelor într-un loc sigur, în afara calculatorului.
Fără ele nu poți publica actualizări. În Google Play activează **Play App Signing**: cheia
de mai sus devine „upload key” și poate fi resetată prin Google dacă se pierde.

## Actualizarea aplicației (fără Google Play)

- Fiecare rulare „Compilare APK” publică în Releases un APK cu eticheta `apk-<număr>`. Numărul rulării devine `versionCode`, deci crește la fiecare compilare.
- Cu secretele `KEYSTORE_*` setate, toate APK-urile au aceeași semnătură și se instalează peste versiunea existentă, fără ștergere. Portofoliul și setările rămân.
- În ecranul „Mai mult”, aplicația verifică ultimul release din GitHub. Dacă e mai nou, afișează „Actualizare disponibilă” cu butonul de descărcare.
- Compilările locale (fără `--dart-define=APP_BUILD` și `GITHUB_REPO`) nu verifică actualizări.

## Actualizarea automată a datelor (MF → aplicație)

```
mf.gov.md  ──►  GitHub Actions (la 5 min în zilele de licitație)  ──►  data/vms_data.json  ──►  aplicația
             comunicate plasare (PDF) → ISIN-uri noi
             rezultate (PDF + pagini HTML) → rate și volume
             calendar trimestrial (PDF) → calendarul din app
```

1. Publică proiectul într-un repository GitHub. Datele sunt publice, dar codul poate rămâne privat dacă folosești alt host pentru JSON.
2. Workflow-ul `.github/workflows/update-data.yml` rulează singur:
   - marți și miercuri (zilele de licitație), la fiecare 30 de minute între 12:07 și 18:37;
   - în restul zilelor, de două ori pe zi, la 14:23 și 17:23.
   Orele sunt pentru ora de iarnă a Chișinăului. GitHub programează în UTC, așa că vara totul vine cu o oră mai târziu.
3. `data_pipeline/` descarcă publicațiile noi, le validează și scrie `data/vms_data.json` doar dacă toate verificările trec. Verificările includ ordinea min ≤ medie ≤ max, rata recalculată din volume vs. rata publicată, datele calendarului și ISIN-urile.
4. Aplicația verifică fișierul la pornire și la revenirea în aplicație, cel mult o dată la 30 de minute. Acceptă datele doar dacă trec validarea și sunt mai noi. Fără internet, folosește ultima copie sau datele incluse în APK.
5. Problemele se scriu în `data/validation_log.json`. Dacă validarea eșuează, GitHub îți trimite e-mail, iar datele publicate rămân cele vechi.
6. Corecturi manuale: editezi `data_pipeline/manual/*.json`, iar fișierele de acolo au prioritate.
7. Evenimentele noi (calendar nou, licitație anunțată, rezultate integrate) sunt scrise deduplicat în `data/events.json`. Ele sunt baza pentru notificările push (etapa următoare: FCM).

Test local al pipeline-ului:

```bash
cd data_pipeline
pip install -r requirements.txt
python -m unittest discover -s tests -t .
python -m vms_pipeline.build            # cu internet
python -m vms_pipeline.build --offline --asset ../assets/data/vms_data.json   # doar seed-uri manuale
```

## Stare și limitări cunoscute

- Codul Dart nu a fost compilat în mediul în care a fost scris (nu era disponibil Flutter SDK). Rulează `flutter analyze` și `flutter test` înainte de build.
- Parserele pipeline-ului sunt testate pe text extras din publicațiile reale ale MF, dar nu au rulat încă pe site-ul live. Calendarul trimestrial (PDF tabelar) este partea cea mai fragilă: dacă nu poate fi citit sigur, apare un avertisment în log, iar calendarul se completează în `manual/calendar.json`.
- Baza ISIN inclusă are toate emisiunile din 2026 până la licitația din 03.11.2026, plus redeschiderea MD4004001740. Bonurile emise în 2025 și obligațiunile mai vechi încă în circulație se adaugă automat de pipeline sau manual în formular („ISIN-ul nu e în listă?”).
- Rezultatele licitației OS din 11.11.2026 nu sunt încă în setul inclus. Le aduce sincronizarea.
- Notificările push (FCM) nu sunt încă active: preferințele se salvează, iar `events.json` pregătește deduplicarea.
- Impozitarea și comisioanele nu sunt incluse în calcule.

## Licență

© 2026 Craciun Radu. Toate drepturile rezervate. Codul este public doar pentru vizualizare; copierea, modificarea sau publicarea lui (inclusiv în magazine de aplicații) nu sunt permise fără acordul scris al autorului. Detalii în [LICENSE](LICENSE).
