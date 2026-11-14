import 'package:flutter/material.dart';

import '../models/dataset.dart';
import '../models/holding.dart';
import '../services/finance.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Deschide formularul de adăugare/editare. Returnează poziția salvată sau null.
Future<Holding?> showHoldingForm(BuildContext context, VmsDataset data, {Holding? initial}) {
  return showModalBottomSheet<Holding>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => HoldingForm(data: data, initial: initial),
  );
}

class HoldingForm extends StatefulWidget {
  final VmsDataset data;
  final Holding? initial;
  const HoldingForm({super.key, required this.data, this.initial});

  @override
  State<HoldingForm> createState() => _HoldingFormState();
}

class _HoldingFormState extends State<HoldingForm> {
  final _form = GlobalKey<FormState>();
  final _price = TextEditingController();
  final _qty = TextEditingController();
  final _manualIsin = TextEditingController();
  final _manualCoupon = TextEditingController();
  final _note = TextEditingController();

  /// Sugestii rapide pentru notiță (se adaugă la textul existent).
  static const _noteSuggestions = ['Familie', 'Studiile copiilor', 'Pensie', 'Fond de urgență', 'Banii mamei'];

  Security? _security;
  bool _manual = false;
  String _manualType = 'BT';
  DateTime? _manualIssue;
  DateTime? _manualMaturity;
  DateTime? _purchase;

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    if (h != null) {
      _price.text = priceFmt(h.price);
      _qty.text = '${h.quantity}';
      _purchase = h.purchaseDate;
      _note.text = h.note ?? '';
      final s = widget.data.byIsin[h.isin];
      if (s != null && !h.manual) {
        _security = s;
      } else {
        _manual = true;
        _manualIsin.text = h.isin;
        _manualType = h.type;
        _manualIssue = h.issueDate;
        _manualMaturity = h.maturity;
        if (h.couponRate != null) _manualCoupon.text = priceFmt(h.couponRate!);
      }
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _qty.dispose();
    _manualIsin.dispose();
    _manualCoupon.dispose();
    _note.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- draft
  DateTime? get _issue => _manual ? _manualIssue : _security?.issueDate;
  DateTime? get _maturity => _manual ? _manualMaturity : _security?.maturity;

  /// Poziția construită din câmpurile curente (null dacă lipsesc date).
  Holding? _draft() {
    final price = parseDecimal(_price.text);
    final qty = int.tryParse(_qty.text.trim());
    final issue = _issue, mat = _maturity;
    if (price == null || price <= 0 || qty == null || qty <= 0 || issue == null || mat == null || !mat.isAfter(issue)) return null;
    final purchase = _purchase ?? issue;
    if (!purchase.isBefore(mat)) return null;
    final id = widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    if (_manual) {
      final coupon = parseDecimal(_manualCoupon.text);
      return Holding(
        id: id,
        isin: _manualIsin.text.trim().toUpperCase(),
        type: _manualType,
        termLabel: _manualType == 'BT' ? '${daysBetween(issue, mat)} zile' : '',
        issueDate: issue,
        maturity: mat,
        couponRate: _manualType == 'OS' ? coupon : null,
        purchaseDate: purchase,
        price: price,
        quantity: qty,
        manual: true,
        note: _note.text,
      );
    }
    return Holding.fromSecurity(_security!, id: id, purchaseDate: purchase, price: price, quantity: qty, note: _note.text);
  }

  Future<void> _pickSecurity() async {
    final s = await showModalBottomSheet<Security>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _IsinPicker(data: widget.data),
    );
    if (s != null) {
      setState(() {
        _security = s;
        _manual = false;
        _purchase = s.issueDate; // implicit: cumpărare la emitere
      });
    }
  }

  Future<void> _pickDate({required DateTime initial, required ValueChanged<DateTime> onPicked, DateTime? first, DateTime? last}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(2000),
      lastDate: last ?? DateTime(2100),
    );
    if (d != null) setState(() => onPicked(d));
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (!_manual && _security == null) {
      _snack('Alege ISIN-ul din listă');
      return;
    }
    final issue = _issue, mat = _maturity;
    if (issue == null || mat == null) {
      _snack('Completează data emiterii și scadența');
      return;
    }
    if (!mat.isAfter(issue)) {
      _snack('Scadența trebuie să fie după data emiterii');
      return;
    }
    final purchase = _purchase ?? issue;
    if (purchase.isBefore(DateTime(issue.year, issue.month, issue.day))) {
      _snack('Data achiziției nu poate fi înainte de emitere');
      return;
    }
    if (!purchase.isBefore(mat)) {
      _snack('Data achiziției trebuie să fie înainte de scadență');
      return;
    }
    final h = _draft();
    if (h == null) {
      _snack('Verifică prețul și cantitatea');
      return;
    }
    Navigator.pop(context, h);
  }

  void _addSuggestion(String t) {
    final cur = _note.text.trim();
    if (cur.toLowerCase().contains(t.toLowerCase())) return;
    final next = cur.isEmpty ? t : '$cur · $t';
    if (next.length > 300) return;
    _note.text = next;
    _note.selection = TextSelection.collapsed(offset: next.length);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final draft = _draft();
    final avgPrice = _security == null
        ? null
        : widget.data.auctions.where((a) => a.isin == _security!.isin && a.avgPrice != null).map((a) => a.avgPrice!).fold<double?>(null, (_, v) => v);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(widget.initial == null ? 'Investiție nouă' : 'Editează investiția', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          // ---- ISIN
          if (!_manual) ...[
            _label('ISIN'),
            InkWell(
              onTap: _pickSecurity,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Expanded(
                    child: Text(_security?.isin ?? 'Alege din listă…',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _security == null ? AppColors.textFaint : AppColors.text)),
                  ),
                  const Icon(Icons.expand_more, color: AppColors.textMuted),
                ]),
              ),
            ),
            if (_security != null) ...[const SizedBox(height: 8), _securityInfo(_security!)],
          ] else
            ..._manualFields(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _manual = !_manual),
              child: Text(_manual ? 'Alege ISIN din baza de date' : 'ISIN-ul nu e în listă? Introdu manual'),
            ),
          ),
          // ---- preț & cantitate
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Preț (pentru 100 lei)', helperText: 'ex. 88,83'),
                validator: (v) {
                  final p = parseDecimal(v);
                  if (p == null || p <= 0 || p > 200) return 'Preț invalid';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantitate VMS', helperText: 'număr de unități'),
                validator: (v) {
                  final q = int.tryParse((v ?? '').trim());
                  if (q == null || q <= 0) return 'Număr întreg > 0';
                  return null;
                },
              ),
            ),
          ]),
          if (avgPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(children: [
                ActionChip(
                  label: Text('Preț mediu la licitație: ${priceFmt(double.parse(avgPrice.toStringAsFixed(4)))}'),
                  onPressed: () => setState(() => _price.text = priceFmt(double.parse(avgPrice.toStringAsFixed(4)))),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ),
          const SizedBox(height: 12),
          // ---- data achiziției
          _label('Data achiziției'),
          Row(children: [
            Expanded(
              child: _dateButton(_purchase ?? _issue, 'implicit = data emiterii', () {
                final issue = _issue;
                if (issue == null) return;
                _pickDate(initial: _purchase ?? issue, first: issue, last: _maturity, onPicked: (d) => _purchase = d);
              }),
            ),
            if (_purchase != null && _issue != null && daysBetween(_issue!, _purchase!) != 0)
              TextButton(onPressed: () => setState(() => _purchase = _issue), child: const Text('= emitere')),
          ]),
          const SizedBox(height: 16),
          // ---- notiță
          TextFormField(
            controller: _note,
            minLines: 1,
            maxLines: 4,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notiță (opțional)',
              helperText: 'pentru cine sau pentru ce sunt banii',
              prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in _noteSuggestions)
              ActionChip(
                label: Text(t),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => setState(() => _addSuggestion(t)),
              ),
          ]),
          const SizedBox(height: 16),
          if (draft != null) _preview(draft),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(widget.initial == null ? 'Adaugă în portofoliu' : 'Salvează modificările')),
        ]),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      );

  Widget _dateButton(DateTime? d, String hint, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(d == null ? hint : date(d), style: TextStyle(fontSize: 14, color: d == null ? AppColors.textFaint : AppColors.text)),
          ]),
        ),
      );

  Widget _securityInfo(Security s) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Row(children: [
            TypePill(s.type),
            const SizedBox(width: 8),
            Text('${s.typeName} · ${s.termLabel}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 6),
          KV('Data emiterii', date(s.issueDate)),
          KV('Data scadenței', date(s.maturity)),
          KV('Termen', '${s.termDays} zile'),
          if (s.couponRate != null) KV('Rata cuponului', pct(s.couponRate!)),
          if (s.isFloating) ...[
            KV('Cupon', 'flotant: BT 182 zile${s.margin != null ? ' + ${priceFmt(s.margin!)} p.p.' : ''}'),
            if (s.couponHistory.isNotEmpty) KV('Ultima rată anunțată', _lastAnnounced(s)),
          ],
          if (s.unverified) const InfoNote('Date preluate automat, încă neconfirmate manual.', icon: Icons.warning_amber_rounded, color: AppColors.amber),
        ]),
      );

  String _lastAnnounced(Security s) {
    final last = (s.couponHistory.keys.toList()..sort()).last;
    return '${pct(s.couponHistory[last]!)} (cupon ${date(last)})';
  }

  List<Widget> _manualFields() => [
        TextFormField(
          controller: _manualIsin,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'ISIN', helperText: 'ex. MD4003005296'),
          validator: (v) => RegExp(r'^MD\d{10}$').hasMatch((v ?? '').trim().toUpperCase()) ? null : 'Format: MD + 10 cifre',
        ),
        const SizedBox(height: 10),
        Segmented<String>(
          values: const ['BT', 'OS'],
          selected: _manualType,
          label: (v) => v == 'BT' ? 'Bon de trezorerie' : 'Obligațiune',
          onChanged: (v) => setState(() => _manualType = v),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Data emiterii'),
              _dateButton(_manualIssue, 'alege', () => _pickDate(initial: _manualIssue ?? DateTime.now(), onPicked: (d) {
                    _manualIssue = d;
                    _purchase ??= d;
                  })),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Data scadenței'),
              _dateButton(_manualMaturity, 'alege',
                  () => _pickDate(initial: _manualMaturity ?? DateTime.now().add(const Duration(days: 182)), onPicked: (d) => _manualMaturity = d)),
            ]),
          ),
        ]),
        if (_manualType == 'OS') ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _manualCoupon,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Rata cuponului (%)', helperText: 'cupoane semestriale, calculate de la scadență'),
            validator: (v) => _manualType == 'OS' && (parseDecimal(v) ?? 0) <= 0 ? 'Obligatoriu pentru obligațiuni' : null,
          ),
        ],
      ];

  Widget _preview(Holding h) {
    final m = computeMetrics(h);
    final same = daysBetween(h.issueDate, h.purchaseDate) == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.primarySoft.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(children: [
          Expanded(child: Stat('Rata dobânzii', pct(m.nominalRate), valueColor: AppColors.primary, valueSize: 17)),
          Expanded(child: Stat('Rentabilitatea investiției', pct(m.investmentReturn), valueColor: AppColors.primary, valueSize: 17)),
        ]),
        if (same)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: InfoNote('Cumpărare la emitere: cele două rate coincid.'),
          ),
        if (m.hasEstimates)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InfoNote(
                'Dobândă flotantă: cupoanele neanunțate încă de MF sunt estimate cu ultima rată medie la BT de 182 zile'
                '${FloatingRates.reference != null ? ' (${pct(FloatingRates.reference!)})' : ''}'
                '${m.margin != null ? ' + marja ${priceFmt(m.margin!)} p.p.' : ''}. '
                'Calculul se actualizează automat pe măsură ce MF anunță ratele.'),
          ),
        const SizedBox(height: 10),
        const Divider(),
        const SizedBox(height: 4),
        KV('Suma investită', lei(m.cost)),
        if (m.accruedPerUnit > 0) KV('din care dobândă acumulată', lei(m.accruedPerUnit * h.quantity)),
        KV('La scadență (${intFmt(h.quantity)} × 100 lei)', lei(m.principalAtMaturity)),
        if (m.couponsTotal > 0) KV('Cupoane de încasat', lei(m.couponsTotal)),
        KV('Dobânda ta', lei(m.interest), strong: true),
        KV('Dobânda pe un titlu', lei(m.interest / h.quantity)),
      ]),
    );
  }
}

// --------------------------------------------------------------------------
class _IsinPicker extends StatefulWidget {
  final VmsDataset data;
  const _IsinPicker({required this.data});

  @override
  State<_IsinPicker> createState() => _IsinPickerState();
}

class _IsinPickerState extends State<_IsinPicker> {
  String q = '';
  String type = 'Toate';
  bool onlyActive = true;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final list = widget.data.securities.where((s) {
      if (onlyActive && !s.maturity.isAfter(today)) return false;
      if (type == 'BT' && !s.isBill) return false;
      if (type == 'OS' && s.isBill) return false;
      if (q.isNotEmpty) {
        final hay = '${s.isin} ${s.termLabel} ${date(s.maturity)} ${date(s.issueDate)}'.toLowerCase();
        if (!hay.contains(q.toLowerCase())) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.issueDate.compareTo(a.issueDate));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Caută ISIN, termen sau dată'),
            onChanged: (v) => setState(() => q = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: Segmented<String>(values: const ['Toate', 'BT', 'OS'], selected: type, label: (v) => v, onChanged: (v) => setState(() => type = v)),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('În circulație'),
              selected: onlyActive,
              onSelected: (v) => setState(() => onlyActive = v),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Niciun ISIN găsit', style: TextStyle(color: AppColors.textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return ListTile(
                      onTap: () => Navigator.pop(context, s),
                      leading: TypePill(s.type),
                      title: Text(s.isin, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('${s.termLabel} · emis ${date(s.issueDate)} · scadență ${date(s.maturity)}'
                          '${s.couponRate != null ? ' · cupon ${pct(s.couponRate!)}' : ''}'
                          '${s.isFloating ? ' · cupon flotant' : ''}'),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
