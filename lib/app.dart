import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/dataset.dart';
import 'models/holding.dart';
import 'screens/alerts_screen.dart';
import 'screens/auctions_screen.dart';
import 'screens/more_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/rates_screen.dart';
import 'services/data_repository.dart';
import 'services/finance.dart';
import 'services/notifications.dart';
import 'services/portfolio_store.dart';
import 'theme/app_theme.dart';

class VmsApp extends StatelessWidget {
  const VmsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'VMS Moldova',
        theme: AppTheme.light(),
        locale: const Locale('ro'),
        supportedLocales: const [Locale('ro'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _repo = DataRepository();
  final _store = PortfolioStore();
  int tab = 0;
  VmsDataset? data;
  List<Holding> holdings = [];
  DateTime? lastChecked;
  bool syncing = false;
  String? syncMessage;
  String? loadError;
  StreamSubscription<void>? _dataEventsSub;
  bool _catchingUp = false;

  /// După o notificare, fișierul nou poate ajunge pe server cu câteva minute întârziere
  /// (robotul face commit după trimitere, iar GitHub ține fișierul în cache ~5 minute).
  static const List<Duration> _catchUpWaits = [
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 3),
    Duration(minutes: 5),
  ];

  final Map<String, bool> prefs = {
    'launch': true,
    'results': true,
    'calendar': true,
    'maturity14': true,
    'maturity7': true,
    'maturity1': true,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataEventsSub = NotificationService.instance.dataEvents.listen((_) => _catchUp());
    _load();
  }

  @override
  void dispose() {
    _dataEventsSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// La pornire și la revenire: dacă o notificare a anunțat date noi, sincronizare forțată
  /// (fără limita de 30 de minute); altfel verificarea obișnuită.
  Future<void> _refresh() async {
    final current = data;
    if (current != null && await _repo.pendingUpdate(current)) {
      await _catchUp();
    } else {
      await _sync();
    }
  }

  /// Sincronizare forțată, reîncercată până sosesc datele anunțate de notificare.
  Future<void> _catchUp() async {
    if (_catchingUp) return;
    _catchingUp = true;
    try {
      for (final wait in _catchUpWaits) {
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        final current = data;
        if (!mounted || current == null) return;
        if (!await _repo.pendingUpdate(current)) return;
        if (syncing) continue; // o verificare este deja în curs; reîncercăm după pauză
        await _sync(force: true, quiet: true);
      }
    } finally {
      _catchingUp = false;
    }
  }

  Future<void> _load() async {
    try {
      final d = await _repo.loadLocal();
      final h = await _store.load();
      final sp = await SharedPreferences.getInstance();
      for (final k in prefs.keys.toList()) {
        prefs[k] = sp.getBool('alert_$k') ?? prefs[k]!;
      }
      // v3.0 avea două comutatoare pentru rezultate („publicate” / „validate”)
      if (!sp.containsKey('alert_results') && sp.containsKey('alert_published')) {
        prefs['results'] = sp.getBool('alert_published')!;
      }
      final lc = await _repo.lastChecked();
      if (!mounted) return;
      FloatingRates.load(d);
      setState(() {
        data = d;
        holdings = h;
        lastChecked = lc;
      });
      _refresh();
      _setupNotifications(sp);
      _offerRestore(sp);
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  /// După o reinstalare portofoliul e gol, dar copia făcută la „Descarcă actualizarea”
  /// e de obicei încă în clipboard. Verificăm o singură dată per instalare (Android
  /// afișează un mesaj la citirea clipboard-ului) și propunem restaurarea.
  Future<void> _offerRestore(SharedPreferences sp) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_store.hadUnreadableData) {
      messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 8),
        content: Text('Unele poziții salvate nu au putut fi citite de această versiune. '
            'Au fost păstrate în siguranță și vor fi recuperate de o versiune viitoare.'),
      ));
    }
    if (holdings.isNotEmpty || (sp.getBool('restore_checked') ?? false)) return;
    await sp.setBool('restore_checked', true);
    final clip = await Clipboard.getData('text/plain');
    final text = clip?.text;
    if (text == null || !text.contains('vms-moldova-portfolio')) return;
    List<Holding> list;
    try {
      list = PortfolioStore.decode(text);
    } catch (_) {
      return;
    }
    if (list.isEmpty || !mounted || holdings.isNotEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restaurezi portofoliul?'),
        content: Text('Am găsit în clipboard o copie a portofoliului cu ${list.length} poziții '
            '(de exemplu, cea salvată înainte de actualizare).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Nu acum')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurează')),
        ],
      ),
    );
    if (ok == true && mounted && holdings.isEmpty) await _saveHoldings(list);
  }

  Future<void> _sync({bool force = false, bool quiet = false}) async {
    final current = data;
    if (current == null || syncing) return;
    setState(() => syncing = true);
    final r = await _repo.sync(current, force: force);
    final lc = await _repo.lastChecked();
    if (!mounted) return;
    setState(() {
      syncing = false;
      lastChecked = lc;
      if ((force && !quiet) || r.status == SyncStatus.updated) syncMessage = r.message;
      if (r.dataset != null) {
        data = r.dataset;
        FloatingRates.load(r.dataset!);
      }
    });
  }

  Future<void> _saveHoldings(List<Holding> list) async {
    setState(() => holdings = list);
    await _store.save(list);
    await NotificationService.instance.scheduleMaturities(list, prefs);
  }

  Future<void> _setupNotifications(SharedPreferences sp) async {
    final n = NotificationService.instance;
    // permisiunea (Android 13+) se cere o singură dată, la prima pornire
    if (!(sp.getBool('notif_permission_asked') ?? false) && prefs.values.any((v) => v)) {
      await sp.setBool('notif_permission_asked', true);
      await n.requestPermission();
    }
    await n.scheduleMaturities(holdings, prefs);
    await n.syncTopics(prefs);
  }

  void _upsert(Holding h) {
    final list = [...holdings];
    final i = list.indexWhere((x) => x.id == h.id);
    if (i >= 0) {
      list[i] = h;
    } else {
      list.add(h);
    }
    _saveHoldings(list);
  }

  Future<void> _setPref(String key, bool value) async {
    setState(() => prefs[key] = value);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('alert_$key', value);
    final n = NotificationService.instance;
    if (value) await n.requestPermission();
    if (kMaturityOffsets.containsKey(key)) {
      await n.scheduleMaturities(holdings, prefs);
    } else {
      await n.syncTopics(prefs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    Widget body;
    if (loadError != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Datele nu au putut fi încărcate:\n$loadError')));
    } else if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = IndexedStack(index: tab, children: [
        RatesScreen(key: ValueKey('rates-${d.generatedAt}'), data: d),
        PortfolioScreen(
          data: d,
          holdings: holdings,
          onSave: _upsert,
          onDelete: (h) => _saveHoldings(holdings.where((x) => x.id != h.id).toList()),
          onReplaceAll: _saveHoldings,
        ),
        AuctionsScreen(key: ValueKey('auctions-${d.generatedAt}'), data: d),
        AlertsScreen(preferences: prefs, onChange: _setPref, pushAvailable: NotificationService.instance.pushAvailable),
        MoreScreen(
          data: d,
          lastChecked: lastChecked,
          syncing: syncing,
          syncMessage: syncMessage,
          onSync: () => _sync(force: true),
          holdings: holdings,
        ),
      ]);
    }
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.show_chart_rounded), label: 'Dobânzi'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Portofoliu'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Licitații'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications), label: 'Alerte'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Mai mult'),
        ],
      ),
    );
  }
}
