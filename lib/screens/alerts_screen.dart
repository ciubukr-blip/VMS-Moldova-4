import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AlertsScreen extends StatelessWidget {
  final Map<String, bool> preferences;
  final void Function(String, bool) onChange;
  final bool pushAvailable; // Firebase configurat în această versiune
  const AlertsScreen({super.key, required this.preferences, required this.onChange, this.pushAvailable = false});

  static const Map<String, Map<String, (String, String?)>> groups = {
    'Licitații': {
      'launch': ('Licitație nouă anunțată', 'Comunicatul de plasare apare pe mf.gov.md'),
      'results': ('Rezultatele licitației', 'Rata medie pe fiecare termen, imediat ce sunt preluate'),
      'calendar': ('Calendar trimestrial nou', 'MF publică graficul pentru trimestrul următor'),
    },
    'Portofoliul meu': {
      'maturity14': ('Scadență peste 14 zile', null),
      'maturity7': ('Scadență peste 7 zile', null),
      'maturity1': ('Scadență mâine', null),
    },
  };

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        const PageHeader('Alerte', subtitle: 'Alege ce notificări vrei să primești'),
        for (final g in groups.entries) ...[
          SectionHeader(g.key),
          if (g.key == 'Licitații' && !pushAvailable)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: InfoNote(
                'Această versiune nu are serviciul de notificări (Firebase) configurat, așa că alertele despre licitații '
                'nu pot fi primite. Preferințele se păstrează și vor fi folosite automat.',
                icon: Icons.notifications_paused_outlined,
                color: AppColors.amber,
                bg: AppColors.amberSoft,
              ),
            ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final (i, e) in g.value.entries.indexed) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                SwitchListTile(
                  dense: true,
                  title: Text(e.value.$1),
                  subtitle: e.value.$2 == null ? null : Text(e.value.$2!),
                  value: preferences[e.key] ?? true,
                  onChanged: (v) => onChange(e.key, v),
                ),
              ],
            ]),
          ),
          if (g.key == 'Portofoliul meu')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: InfoNote('Alertele de scadență sunt programate pe telefon, la 09:00 ora Chișinăului, '
                  'și funcționează și fără internet.'),
            ),
        ],
        const SizedBox(height: 12),
        const InfoNote(
          'Site-ul MF este verificat pe server, la fiecare 30 de minute în zilele de licitație. Fiecare eveniment '
          'generează o singură notificare și doar pentru licitații viitoare sau rezultate recente – fără arhivă.',
        ),
      ]);
}
