import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AlertsScreen extends StatelessWidget {
  final Map<String, bool> preferences;
  final void Function(String, bool) onChange;
  const AlertsScreen({super.key, required this.preferences, required this.onChange});

  static const Map<String, Map<String, (String, String?)>> groups = {
    'Licitații': {
      'launch': ('Licitație nouă anunțată', 'Comunicatul de plasare apare pe mf.gov.md'),
      'calendar': ('Calendar trimestrial nou', 'MF publică graficul pentru trimestrul următor'),
      'published': ('Rezultate publicate de MF', 'Imediat după licitație'),
      'integrated': ('Rezultate validate în aplicație', 'După verificarea automată a datelor'),
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
        const InfoNote(
          'Notificările push vor fi activate odată cu serviciul de notificări (Firebase). '
          'Preferințele tale sunt deja salvate și vor fi folosite automat.',
          icon: Icons.notifications_paused_outlined,
          color: AppColors.amber,
          bg: AppColors.amberSoft,
        ),
        for (final g in groups.entries) ...[
          SectionHeader(g.key),
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
        ],
        const SizedBox(height: 12),
        const InfoNote(
          'Verificarea site-ului MF se face pe server, la fiecare 5 minute în zilele de licitație, '
          'cu deduplicare: fiecare eveniment generează o singură notificare. Telefonul nu face verificări periodice.',
        ),
      ]);
}
