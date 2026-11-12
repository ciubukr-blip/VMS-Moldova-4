/// Notificări (versiunea 3.1).
///
/// * Scadențe – programate local pe telefon la 09:00 ora Chișinăului, cu 14 zile,
///   7 zile și o zi înainte. Fără server și fără internet.
/// * Licitații – trimise de robotul de date prin Firebase Cloud Messaging pe
///   subiectele `licitatii`, `rezultate`, `calendar`; aplicația se abonează după
///   comutatoarele din ecranul Alerte. Dacă versiunea nu are Firebase configurat,
///   doar această parte lipsește – restul aplicației funcționează normal.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config.dart';
import '../models/dataset.dart';
import '../models/holding.dart';
import 'finance.dart';
import 'format.dart';

/// Comutator din ecranul Alerte -> subiect FCM.
const Map<String, String> kTopicForPref = {'launch': 'licitatii', 'results': 'rezultate', 'calendar': 'calendar'};

/// Comutator -> câte zile înainte de scadență.
const Map<String, int> kMaturityOffsets = {'maturity14': 14, 'maturity7': 7, 'maturity1': 1};

/// Ora la care se afișează alertele de scadență (ora Chișinăului).
const int kMaturityHour = 9;

class PlannedNotification {
  final int id;
  final DateTime day; // ziua afișării (09:00 ora Chișinăului)
  final String title;
  final String body;
  const PlannedNotification(this.id, this.day, this.title, this.body);
}

/// Alertele de scadență pentru portofoliu (funcție pură – testabilă).
/// Pozițiile cu aceeași scadență sunt grupate într-o singură notificare.
List<PlannedNotification> maturityPlan(List<Holding> holdings, Map<String, bool> prefs, DateTime now) {
  final today = dayOnly(now);
  final byMaturity = <DateTime, List<Holding>>{};
  for (final h in holdings) {
    final m = dayOnly(h.maturity);
    if (m.isAfter(today)) (byMaturity[m] ??= []).add(h);
  }
  final out = <PlannedNotification>[];
  for (final e in byMaturity.entries) {
    final maturity = e.key;
    final list = e.value;
    // încasarea din ziua scadenței: valoarea nominală + ultimul cupon (la obligațiuni)
    var amount = 0.0;
    for (final h in list) {
      for (final f in computeMetrics(h, today: now).futureFlows) {
        if (dayOnly(f.date) == maturity) amount += f.amount;
      }
    }
    for (final o in kMaturityOffsets.entries) {
      if (!(prefs[o.key] ?? true)) continue;
      final day = maturity.subtract(Duration(days: o.value));
      if (day.isBefore(today)) continue;
      final when = o.value == 1 ? 'mâine' : 'peste ${o.value} zile';
      final title = list.length == 1 ? 'Scadență $when: ${list.first.isin}' : 'Scadență $when: ${list.length} poziții';
      final body = 'Pe ${date(maturity)} încasezi ${lei(amount)}.';
      final id = (maturity.year * 10000 + maturity.month * 100 + maturity.day) * 100 + o.value;
      out.add(PlannedNotification(id, day, title, body));
    }
  }
  out.sort((a, b) => a.day.compareTo(b.day));
  return out;
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  tz.Location? _chisinau;

  /// Firebase este configurat și inițializat în această versiune.
  bool pushAvailable = false;

  static const List<AndroidNotificationChannel> _channels = [
    AndroidNotificationChannel('scadente', 'Scadențe',
        description: 'Titluri din portofoliu care ajung la scadență', importance: Importance.high),
    AndroidNotificationChannel('licitatii', 'Licitații', description: 'Comunicate de plasare noi', importance: Importance.high),
    AndroidNotificationChannel('rezultate', 'Rezultate', description: 'Rezultatele licitațiilor', importance: Importance.high),
    AndroidNotificationChannel('calendar', 'Calendar', description: 'Calendare trimestriale noi'),
  ];

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      _chisinau = tz.getLocation('Europe/Chisinau');
      await _local.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      for (final c in _channels) {
        await _android?.createNotificationChannel(c);
      }
      _localReady = true;
    } catch (e) {
      debugPrint('Notificări locale indisponibile: $e');
    }
    await _initPush();
  }

  Future<void> _initPush() async {
    if (!kFirebaseConfigured) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: kFirebaseApiKey,
          appId: kFirebaseAppId,
          messagingSenderId: kFirebaseSenderId,
          projectId: kFirebaseProjectId,
        ),
      );
      // cu aplicația deschisă, Android nu afișează singur notificarea: o afișăm noi
      FirebaseMessaging.onMessage.listen(_showForeground);
      pushAvailable = true;
    } catch (e) {
      debugPrint('Firebase indisponibil: $e');
    }
  }

  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null || !_localReady) return;
    final channel = _channels.firstWhere((c) => c.id == n.android?.channelId, orElse: () => _channels[1]);
    _local.show(
      m.messageId.hashCode & 0x7fffffff,
      n.title,
      n.body,
      NotificationDetails(android: AndroidNotificationDetails(channel.id, channel.name, importance: channel.importance)),
    );
  }

  /// Cere permisiunea de notificare (Android 13+).
  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Abonează / dezabonează telefonul de la subiectele FCM după preferințe.
  Future<void> syncTopics(Map<String, bool> prefs) async {
    if (!pushAvailable) return;
    for (final e in kTopicForPref.entries) {
      try {
        if (prefs[e.key] ?? true) {
          await FirebaseMessaging.instance.subscribeToTopic(e.value);
        } else {
          await FirebaseMessaging.instance.unsubscribeFromTopic(e.value);
        }
      } catch (err) {
        debugPrint('Subiect ${e.value}: $err');
      }
    }
  }

  /// Reprogramează toate alertele de scadență (la pornire și la orice modificare).
  Future<void> scheduleMaturities(List<Holding> holdings, Map<String, bool> prefs) async {
    final loc = _chisinau;
    if (!_localReady || loc == null) return;
    try {
      for (final p in await _local.pendingNotificationRequests()) {
        await _local.cancel(p.id);
      }
      final nowTz = tz.TZDateTime.now(loc);
      for (final p in maturityPlan(holdings, prefs, DateTime.now())) {
        final when = tz.TZDateTime(loc, p.day.year, p.day.month, p.day.day, kMaturityHour);
        if (!when.isAfter(nowTz)) continue;
        await _local.zonedSchedule(
          p.id,
          p.title,
          p.body,
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails('scadente', 'Scadențe', importance: Importance.high, priority: Priority.high),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Programarea alertelor de scadență a eșuat: $e');
    }
  }
}
