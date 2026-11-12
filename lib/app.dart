import 'package:flutter/material.dart';
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
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
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
      _sync();
      _setupNotifications(sp);
    } catch (e) {
      if (mounted) setState(() => loadError = '$e');
    }
  }

  Future<void> _sync({bool force = false}) async {
    final current = data;
    if (current == null || syncing) return;
    setState(() => syncing = true);
    final r = await _repo.sync(current, force: force);
    final lc = await _repo.lastChecked();
    if (!mounted) return;
    setState(() {
      syncing = false;
      lastChecked = lc;
      if (force || r.status == SyncStatus.updated) syncMessage = r.message;
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
