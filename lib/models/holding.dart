import 'dataset.dart';

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
  });

  bool get isBill => type == 'BT';
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

  factory Holding.fromSecurity(Security s, {required String id, required DateTime purchaseDate, required double price, required int quantity}) =>
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
      );
}
