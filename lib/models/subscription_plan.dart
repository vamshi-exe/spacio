/// The SPACIO subscription plans and their included monthly render quota.
/// This is the client-side source of truth; the same numbers live in
/// `plan_included_renders()` in supabase/schema.sql for cycle resets.
class SubscriptionPlan {
  /// Value stored in `profiles.plan`.
  final String id;
  final String name;

  /// AI visualizations included each billing cycle.
  final int monthlyRenders;

  /// Price per month in whole rupees.
  final int priceInr;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.monthlyRenders,
    required this.priceInr,
  });

  String get priceLabel => '₹${_grouped(priceInr)}/mo';

  /// Razorpay charges in the smallest currency unit (paise).
  int get amountPaise => priceInr * 100;

  static const byod = SubscriptionPlan(
    id: 'SPACIO BYOD',
    name: 'SPACIO BYOD',
    monthlyRenders: 300,
    priceInr: 4999,
  );
  static const standard = SubscriptionPlan(
    id: 'SPACIO Standard',
    name: 'SPACIO Standard',
    monthlyRenders: 300,
    priceInr: 7999,
  );
  static const pro = SubscriptionPlan(
    id: 'SPACIO Pro',
    name: 'SPACIO Pro',
    monthlyRenders: 400,
    priceInr: 9999,
  );

  static const all = <SubscriptionPlan>[byod, standard, pro];

  /// Renders included for a stored plan name. Falls back to the free trial
  /// allowance (50) for unknown / 'Free' plans.
  static int includedRendersFor(String? plan) {
    for (final p in all) {
      if (p.id == plan) return p.monthlyRenders;
    }
    return 50;
  }

  static SubscriptionPlan? byId(String? plan) {
    for (final p in all) {
      if (p.id == plan) return p;
    }
    return null;
  }

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
