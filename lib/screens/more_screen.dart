import 'package:flutter/material.dart';

import '../config.dart';
import '../models/dataset.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class MoreScreen extends StatelessWidget {
  final VmsDataset data;
  final DateTime? lastChecked;
  final bool syncing;
  final String? syncMessage;
  final VoidCallback onSync;

  const MoreScreen({
    super.key,
    required this.data,
    required this.lastChecked,
    required this.syncing,
    required this.syncMessage,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final gen = data.generatedAt?.toLocal();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      const PageHeader('Mai mult'),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.82,
          children: [
            IconTile(icon: Icons.event_note_outlined, label: 'Calendar MF', onTap: () => openLink(context, kCalendarCurrentPdf)),
            IconTile(icon: Icons.fact_check_outlined, label: 'Rezultate MF', onTap: () => openLink(context, kSourceLinks['Rezultatele licitațiilor']!)),
            IconTile(icon: Icons.gavel_outlined, label: 'Regulament VMS', onTap: () => openLink(context, kSourceLinks['Regulamentul VMS (BNM)']!)),
            IconTile(icon: Icons.account_balance_outlined, label: 'BNM', onTap: () => openLink(context, kSourceLinks['BNM – rapoarte VMS']!)),
          ],
        ),
      ),
      const SectionHeader('Date'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KV('Set de date generat', gen == null ? '—' : '${date(gen)} ${gen.hour.toString().padLeft(2, '0')}:${gen.minute.toString().padLeft(2, '0')}'),
          KV('Ultima verificare online', lastChecked == null ? 'niciodată' : '${date(lastChecked!)} ${lastChecked!.hour.toString().padLeft(2, '0')}:${lastChecked!.minute.toString().padLeft(2, '0')}'),
          KV('Licitații în istoric', intFmt(data.rates.map((r) => r.date).toSet().length)),
          KV('ISIN-uri în baza de date', intFmt(data.securities.length)),
          const SizedBox(height: 10),
          if (syncMessage != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: InfoNote(syncMessage!)),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: syncing || kRemoteDataUrl.isEmpty ? null : onSync,
              icon: syncing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 18),
              label: Text(kRemoteDataUrl.isEmpty ? 'Sincronizare neconfigurată' : 'Actualizează acum'),
            ),
          ),
        ]),
      ),
      const SectionHeader('Despre'),
      const AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('VMS Moldova · versiunea $kAppVersion', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            'Aplicație informativă despre valorile mobiliare de stat ale Republicii Moldova: rate la licitații, '
            'calendarul Ministerului Finanțelor și evidența personală a investițiilor.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      const AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Confidențialitate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            'Portofoliul este salvat doar pe acest dispozitiv. Aplicația nu cere cont, nu colectează date personale '
            'și nu trimite portofoliul nicăieri. Singura conexiune la internet descarcă datele publice ale MF.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      const AppCard(
        color: AppColors.amberSoft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Important', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.amber)),
          SizedBox(height: 8),
          Text(
            'Informațiile nu reprezintă consultanță de investiții. Calculele sunt orientative; sursa oficială rămâne '
            'Ministerul Finanțelor și Banca Națională a Moldovei.',
            style: TextStyle(fontSize: 12.5, color: AppColors.amber, height: 1.4),
          ),
        ]),
      ),
    ]);
  }
}
