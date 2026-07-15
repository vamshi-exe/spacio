/// A tiling cost estimate computed from an area and a per-sq-ft price.
///
/// `materialCost`   = area × price/sq ft
/// `approxTotalCost` = material + the flat cartage (transport) fee
class Estimate {
  /// Standard Indian GST slabs offered for tile work (tiles are usually 18%).
  static const gstSlabs = <double>[5, 12, 18, 28];

  /// Floor/wall area to be tiled, in square feet.
  final double areaSqFt;

  /// Price of the tile per square foot.
  final double pricePerSqFt;

  /// Flat transport/delivery charge, in rupees, entered with the other
  /// tile details. 0 when the user didn't enter one.
  final double cartageFee;

  /// GST rate to apply on the pre-tax subtotal. 0 means a non-GST quotation.
  final double gstPercent;

  /// Area of a single tile in sq ft, used to estimate the piece count.
  final double? tileAreaSqFt;

  const Estimate({
    required this.areaSqFt,
    required this.pricePerSqFt,
    this.cartageFee = 0,
    this.gstPercent = 0,
    this.tileAreaSqFt,
  });

  /// Pieces required to cover the area.
  int? get tilesNeeded {
    final a = tileAreaSqFt;
    if (a == null || a <= 0) return null;
    return (areaSqFt / a).ceil();
  }

  double get materialCost => areaSqFt * pricePerSqFt;

  /// Material + cartage, before tax — the "without GST" total.
  double get approxTotalCost => materialCost + cartageFee;

  bool get hasGst => gstPercent > 0;

  /// GST charged on the pre-tax subtotal.
  double get gstAmount => approxTotalCost * (gstPercent / 100);

  /// Pre-tax subtotal + GST — the "with GST" grand total.
  double get totalWithGst => approxTotalCost + gstAmount;

  /// Copy with a different GST rate (used for the with/without-GST downloads).
  Estimate withGst(double percent) => Estimate(
    areaSqFt: areaSqFt,
    pricePerSqFt: pricePerSqFt,
    cartageFee: cartageFee,
    gstPercent: percent,
    tileAreaSqFt: tileAreaSqFt,
  );

  /// Format a rupee amount with Indian-style grouping, e.g. ₹1,23,456.
  /// PDF output passes `symbol: 'Rs. '` because the built-in PDF font has no
  /// ₹ glyph.
  static String formatCurrency(double amount, {String symbol = '₹'}) =>
      '$symbol${_grouped(amount)}';

  static String _grouped(double amount) {
    final rounded = amount.round();
    final negative = rounded < 0;
    var digits = rounded.abs().toString();

    // Indian numbering: last 3 digits, then groups of 2.
    final buffer = StringBuffer();
    if (digits.length > 3) {
      final last3 = digits.substring(digits.length - 3);
      var rest = digits.substring(0, digits.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      buffer.write(parts.join(','));
      buffer.write(',');
      buffer.write(last3);
    } else {
      buffer.write(digits);
    }
    return '${negative ? '-' : ''}$buffer';
  }
}
