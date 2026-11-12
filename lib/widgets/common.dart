import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Card alb, rotunjit, fără umbră.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Titlul mare al paginii + subtitlu discret.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle!, style: t.bodySmall),
            ],
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primary)),
            ),
        ]),
      );
}

/// Pătrat cu icon + etichetă (stil grilă de produse).
class IconTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  const IconTile({super.key, required this.icon, required this.label, this.onTap, this.color});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: AppColors.tile, borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, size: 22, color: color ?? AppColors.primary),
            ),
            const SizedBox(height: 7),
            Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.2)),
          ]),
        ),
      );
}

/// Etichetă colorată discret (ex. „BT”, „+0,12%”).
class Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final double fontSize;
  const Pill(this.text, {super.key, this.fg = AppColors.primary, this.bg = AppColors.primarySoft, this.fontSize = 11});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg)),
      );
}

class TypePill extends StatelessWidget {
  final String type;
  const TypePill(this.type, {super.key});
  @override
  Widget build(BuildContext context) =>
      type == 'OS' ? const Pill('OS', fg: AppColors.amber, bg: AppColors.amberSoft) : const Pill('BT', fg: AppColors.teal, bg: AppColors.tealSoft);
}

/// O cifră cu eticheta deasupra.
class Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final CrossAxisAlignment align;
  final double valueSize;
  const Stat(this.label, this.value, {super.key, this.valueColor, this.align = CrossAxisAlignment.start, this.valueSize = 15});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.text)),
      ]);
}

class InfoNote extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color bg;
  const InfoNote(this.text, {super.key, this.icon = Icons.info_outline, this.color = AppColors.textMuted, this.bg = Colors.transparent});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(bg == Colors.transparent ? 4 : 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, color: color, height: 1.35))),
        ]),
      );
}

/// Rând etichetă – valoare (pentru detalii).
class KV extends StatelessWidget {
  final String k;
  final String v;
  final bool strong;
  const KV(this.k, this.v, {super.key, this.strong = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w600 : FontWeight.w500, color: AppColors.text)),
        ]),
      );
}

Future<void> openLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nu am putut deschide linkul. Verifică dacă ai un browser instalat.')));
  }
}

/// Selector compact cu „pastile” (ex. 91 / 182 / 364).
class Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  const Segmented({super.key, required this.values, required this.selected, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: v == selected ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: v == selected ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))] : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(label(v),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: v == selected ? FontWeight.w600 : FontWeight.w500,
                        color: v == selected ? AppColors.text : AppColors.textMuted,
                      )),
                ),
              ),
            ),
        ]),
      );
}
