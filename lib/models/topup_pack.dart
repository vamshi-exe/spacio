/// A render top-up pack the user can buy when their monthly quota runs low.
/// Top-up renders are added instantly after payment and carry forward until
/// consumed (they don't expire with the billing cycle).
class TopupPack {
  final String id;
  final String name;
  final int renders;

  /// Price in whole rupees.
  final int priceInr;

  const TopupPack({
    required this.id,
    required this.name,
    required this.renders,
    required this.priceInr,
  });

  /// Razorpay charges in the smallest currency unit (paise).
  int get amountPaise => priceInr * 100;

  /// Formatted price, e.g. "₹1,799".
  String get priceLabel => '₹${_grouped(priceInr)}';

  static const all = <TopupPack>[
    TopupPack(id: 'starter', name: 'Starter', renders: 50, priceInr: 999),
    TopupPack(id: 'growth', name: 'Growth', renders: 100, priceInr: 1799),
    TopupPack(id: 'business', name: 'Business', renders: 250, priceInr: 3999),
  ];

  static String _grouped(int amount) {
    final digits = amount.toString();
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }
}
