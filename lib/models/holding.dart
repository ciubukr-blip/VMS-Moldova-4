import 'dataset.dart';

/// O vânzare (parțială sau totală) a unei poziții pe piața secundară.
class Sale {
  final String id;
  final DateTime date; // data tranzacției (decontării)
  final int quantity; // titluri vândute
  final double price; // preț net pentru o VMS de 100 lei

  const Sale({required this.id, required this.date, required this.quantity, required this.price});

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'quantity': quantity,
        'price': price,
      };

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        quantity: (j['quantity'] as num).toInt(),
        price: (j['price'] as num).toDouble(),
      );
}

/// O poziție din portofoliu: o cumpărare de [quantity] unități ale unui ISIN.
///
/// Datele titlului (tip, emitere, scadență, cupon) sunt copiate din baza de
/// date la salvare, astfel încât poziția rămâne calculabilă chiar dacă ISIN-ul
/// dispare ulterior din setul de date.
class Holding {
  final String id;
  final String isin;
  final String type; // BT / OS
  final String termLabel;
  final DateTime issueDate;
  final DateTime maturity;
  final double? couponRate;
  final List<DateTime> couponDates;
  final DateTime purchaseDate;
  final double price; // preț net pentru o VMS de 100 lei
  final int quantity; // număr de unități
  final bool manual; // ISIN introdus manual (nu din baza de date)
  final String? couponType; // 'flotant' = dobândă flotantă
  final double? margin; // p.p. peste rata medie BT 182 zile
  final Map<DateTime, double> couponHistory; // ratele cupoanelor anunțate (copie la salvare)
  final String? note; // notiță liberă a utilizatorului (ex. „banii mamei”)
  final List<Sale> sales; // vânzările pe piața secundară (cele mai vechi primele)

  Holding({
    required this.id,
    required this.isin,
    required this.type,
    required this.termLabel,
    required this.issueDate,
    required this.maturity,
    required this.purchaseDate,
    required this.price,
    required this.quantity,
    this.couponRate,
    this.couponDates = const [],
    this.manual = false,
    this.couponType,
    this.margin,
    this.couponHistory = const {},
    String? note,
    List<Sale> sales = const [],
  })  : note = (note == null || note.trim().isEmpty) ? null : note.trim(),
        sales = List.unmodifiable([...sales]..sort((a, b) => a.date.compareTo(b.date)));

  bool get hasNote => note != null;

  /// Titluri vândute în total.
  int get soldQuantity => sales.fold(0, (t, s) => t + s.quantity);

  /// Titluri rămase în portofoliu ([quantity] = cât s-a cumpărat).
  int get remaining => quantity - soldQuantity;

  bool get fullySold => remaining <= 0;

  /// Copie cu lista de vânzări înlocuită.
  Holding withSales(List<Sale> list) => Holding(
        id: id,
        isin: isin,
        type: type,
        termLabel: termLabel,
        issueDate: issueDate,
        maturity: maturity,
        purchaseDate: purchaseDate,
        price: price,
        quantity: quantity,
        couponRate: couponRate,
        couponDates: couponDates,
        manual: manual,
        couponType: couponType,
        margin: margin,
        couponHistory: couponHistory,
        note: note,
        sales: list,
      );

  bool get isBill => type == 'BT';
  bool get isFloating => !isBill && couponType == 'flotant';
  String get typeName => isBill ? 'Bon de trezorerie' : 'Obligațiune de stat';
  bool isMatured(DateTime today) => !dayOnly(maturity).isAfter(dayOnly(today));

  Holding copyWith({
    String? isin,
    String? type,
    String? termLabel,
    DateTime? issueDate,
    DateTime? maturity,
    double? couponRate,
    List<DateTime>? couponDates,
    DateTime? purchaseDate,
    double? price,
    int? quantity,
    bool? manual,
    String? couponType,
    double? margin,
    Map<DateTime, double>? couponHistory,
    String? note,
  }) =>
      Holding(
        id: id,
        isin: isin ?? this.isin,
        type: type ?? this.type,
        termLabel: termLabel ?? this.termLabel,
        issueDate: issueDate ?? this.issueDate,
        maturity: maturity ?? this.maturity,
        couponRate: couponRate ?? this.couponRate,
        couponDates: couponDates ?? this.couponDates,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        price: price ?? this.price,
        quantity: quantity ?? this.quantity,
        manual: manual ?? this.manual,
        couponType: couponType ?? this.couponType,
        margin: margin ?? this.margin,
        couponHistory: couponHistory ?? this.couponHistory,
        note: note ?? this.note,
        sales: sales,
      );

  static String _ds(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'isin': isin,
        'type': type,
        'termLabel': termLabel,
        'issueDate': _ds(issueDate),
        'maturity': _ds(maturity),
        'couponRate': couponRate,
        'couponDates': couponDates.map(_ds).toList(),
        'purchaseDate': _ds(purchaseDate),
        'price': price,
        'quantity': quantity,
        'manual': manual,
        if (couponType != null) 'couponType': couponType,
        if (margin != null) 'margin': margin,
        if (note != null) 'note': note,
        if (sales.isNotEmpty) 'sales': [for (final x in sales) x.toJson()],
        if (couponHistory.isNotEmpty) 'couponHistory': {for (final e in couponHistory.entries) _ds(e.key): e.value},
      };

  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
        id: j['id'] as String,
        isin: j['isin'] as String,
        type: j['type'] as String,
        termLabel: (j['termLabel'] as String?) ?? '',
        issueDate: DateTime.parse(j['issueDate'] as String),
        maturity: DateTime.parse(j['maturity'] as String),
        couponRate: (j['couponRate'] as num?)?.toDouble(),
        couponDates: ((j['couponDates'] as List?) ?? const []).map((e) => DateTime.parse(e as String)).toList()..sort(),
        purchaseDate: DateTime.parse(j['purchaseDate'] as String),
        price: (j['price'] as num).toDouble(),
        quantity: (j['quantity'] as num).toInt(),
        manual: (j['manual'] as bool?) ?? false,
        couponType: j['couponType'] as String?,
        margin: (j['margin'] as num?)?.toDouble(),
        couponHistory: {
          for (final e in ((j['couponHistory'] as Map?) ?? const {}).entries)
            dayOnly(DateTime.parse(e.key as String)): (e.value as num).toDouble(),
        },
        note: j['note'] as String?,
        sales: [for (final x in (j['sales'] as List?) ?? const []) Sale.fromJson(x as Map<String, dynamic>)],
      );

  /// Migrare din formatul v2 (nominal total + cost total, fără ISIN).
  static Holding? fromV2(Map<String, dynamic> j) {
    try {
      final nominal = (j['nominal'] as num).toDouble();
      final cost = (j['purchasePrice'] as num).toDouble();
      final qty = (nominal / 100).round();
      if (qty <= 0) return null;
      final purchase = DateTime.parse(j['purchaseDate'] as String);
      final kind = (j['kind'] as String?) ?? '';
      final coupon = (j['annualCoupon'] as num?)?.toDouble();
      return Holding(
        id: j['id'] as String,
        isin: (j['name'] as String?)?.trim().isNotEmpty == true ? (j['name'] as String).trim() : 'Fără ISIN',
        type: kind.toLowerCase().contains('oblig') ? 'OS' : 'BT',
        termLabel: '',
        issueDate: purchase,
        maturity: DateTime.parse(j['maturity'] as String),
        purchaseDate: purchase,
        price: cost / qty,
        quantity: qty,
        couponRate: (coupon != null && coupon > 0) ? coupon : null,
        manual: true,
      );
    } catch (_) {
      return null;
    }
  }

  factory Holding.fromSecurity(Security s,
          {required String id,
          required DateTime purchaseDate,
          required double price,
          required int quantity,
          String? note,
          List<Sale> sales = const []}) =>
      Holding(
        id: id,
        isin: s.isin,
        type: s.type,
        termLabel: s.termLabel,
        issueDate: s.issueDate,
        maturity: s.maturity,
        couponRate: s.couponRate,
        couponDates: s.couponDates,
        purchaseDate: purchaseDate,
        price: price,
        quantity: quantity,
        couponType: s.couponType,
        margin: s.margin,
        couponHistory: s.couponHistory,
        note: note,
        sales: sales,
      );
}
