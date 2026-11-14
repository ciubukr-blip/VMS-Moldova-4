import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Card alb, rotunjit, fără umbră.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final BorderSide side;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.side = const BorderSide(color: AppColors.divider)});

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: side),
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
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
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

  TextAlign get _textAlign => switch (align) {
        CrossAxisAlignment.center => TextAlign.center,
        CrossAxisAlignment.end => TextAlign.end,
        _ => TextAlign.start,
      };

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
        Text(label, textAlign: _textAlign, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        const SizedBox(height: 3),
        Text(value, textAlign: _textAlign, style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w700, color: valueColor ?? AppColors.text)),
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
///
/// Cu [palette], opțiunea aleasă ia nuanța pastel a secțiunii, iar între
/// opțiunile neselectate apar linii fine de separare.
class Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final SectionPalette? palette;
  const Segmented({super.key, required this.values, required this.selected, required this.label, required this.onChanged, this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final items = <Widget>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (p != null && i > 0) {
        final hide = v == selected || values[i - 1] == selected;
        items.add(Container(width: 1, height: 16, color: hide ? Colors.transparent : const Color(0xFFCBD3DF)));
      }
      final on = v == selected;
      items.add(Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: on ? (p == null ? AppColors.surface : AppColors.primarySoft) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: p == null ? null : Border.all(color: on ? AppColors.primaryLine : Colors.transparent),
              boxShadow: on && p == null ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))] : null,
            ),
            alignment: Alignment.center,
            child: Text(label(v),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? (p == null ? AppColors.text : AppColors.primary) : (p == null ? AppColors.textMuted : const Color(0xFF475569)),
                )),
          ),
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: p == null
          ? BoxDecoration(color: AppColors.track, borderRadius: BorderRadius.circular(12))
          : BoxDecoration(
              color: AppColors.track,
              border: Border.all(color: const Color(0xFFDCE2EC)),
              borderRadius: BorderRadius.circular(12),
            ),
      child: Row(children: items),
    );
  }
}

/// Cip de an, colorat în nuanța secțiunii când e ales.
class YearChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SectionPalette palette;
  const YearChip(this.label, {super.key, required this.selected, required this.onTap, required this.palette});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(color: selected ? AppColors.primary : AppColors.text, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AppColors.primarySoft,
          side: BorderSide(color: selected ? AppColors.primaryLine : const Color(0xFFDCE2EC)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}

/// Card cu o bandă pastel sus (marchează secțiunea BT / OS).
class BandCard extends StatelessWidget {
  final Widget child;
  final SectionPalette palette;
  final EdgeInsetsGeometry padding;
  const BandCard({super.key, required this.child, required this.palette, this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 12)});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: 3, color: palette.line),
          Padding(padding: padding, child: child),
        ]),
      );
}

/// Comutatorul mare dintre secțiuni (Bonuri · BT | Obligațiuni · OS).
class SectionSwitch extends StatelessWidget {
  final bool bonds;
  final ValueChanged<bool> onChanged;
  const SectionSwitch({super.key, required this.bonds, required this.onChanged});

  Widget _half(String text, bool on, SectionPalette p, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: on ? p.line : Colors.transparent),
            ),
            child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: p.text.withValues(alpha: on ? 1 : 0.75))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.track, border: Border.all(color: const Color(0xFFDCE2EC)), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          _half('Bonuri · BT', !bonds, SectionPalette.bills, () => onChanged(false)),
          _half('Obligațiuni · OS', bonds, SectionPalette.bonds, () => onChanged(true)),
        ]),
      );
}

/// Explicația de la finalul unei secțiuni (ce este un BT / o OS).
class SectionExplainer extends StatelessWidget {
  final String title;
  final String text;
  final SectionPalette palette;
  const SectionExplainer({super.key, required this.title, required this.text, required this.palette});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(color: palette.wash, borderRadius: BorderRadius.circular(14), border: Border.all(color: palette.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.help_outline, size: 16, color: palette.text)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$title: ', style: TextStyle(fontWeight: FontWeight.w600, color: palette.text)),
                TextSpan(text: text),
              ]),
              style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.4),
            ),
          ),
        ]),
      );
}

/// Chenar pentru un element dintr-o listă (un titlu planificat, un rezultat de licitație).
class OutlinedTile extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const OutlinedTile({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 10)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

/// O cifră într-o căsuță, cu denumirea și valoarea centrate (statisticile de pe ecranul Dobânzi).
class StatBox extends StatelessWidget {
  final String label;
  final String value;
  const StatBox(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
        ]),
      );
}

/// Un rând de căsuțe [StatBox] egale, cu spațiu între ele.
class StatBoxRow extends StatelessWidget {
  final List<StatBox> boxes;
  const StatBoxRow(this.boxes, {super.key});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, b) in boxes.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: b),
          ],
        ]),
      );
}
