/// A user's profile row from the `profiles` table.
class Profile {
  final String id;
  final String? fullName;
  final String plan;

  /// Included monthly renders left this billing cycle (reset each cycle).
  final int rendersLeft;

  /// Purchased top-up renders — consumed only after [rendersLeft] hits 0, and
  /// carried forward across billing cycles until used.
  final int topupRendersLeft;

  /// 'device' (Type 1 — bought a SPACIO tablet, subscription preloaded) or
  /// 'byod' (Type 2 — own device, purchases the subscription).
  final String merchantType;

  /// When the BYOD subscription lapses; null for device/preloaded or none.
  final DateTime? subscriptionActiveUntil;

  const Profile({
    required this.id,
    required this.fullName,
    required this.plan,
    required this.rendersLeft,
    this.topupRendersLeft = 0,
    this.merchantType = 'byod',
    this.subscriptionActiveUntil,
  });

  /// Total renders available now (monthly + top-up).
  int get totalRendersLeft => rendersLeft + topupRendersLeft;

  /// Type 1 — subscription is preloaded with the SPACIO device.
  bool get isDeviceMerchant => merchantType == 'device';

  /// Type 2 — uses their own device and buys the subscription.
  bool get isByodMerchant => !isDeviceMerchant;

  /// Device merchants are always active (preloaded); BYOD is active while the
  /// paid period hasn't lapsed.
  bool get subscriptionActive {
    if (isDeviceMerchant) return true;
    final until = subscriptionActiveUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      plan: _cleanPlan(map['plan'] as String?),
      rendersLeft: (map['renders_left'] as num?)?.toInt() ?? 0,
      topupRendersLeft: (map['topup_renders_left'] as num?)?.toInt() ?? 0,
      merchantType: (map['merchant_type'] as String?) ?? 'byod',
      subscriptionActiveUntil:
          DateTime.tryParse(map['subscription_active_until'] as String? ?? '')
              ?.toLocal(),
    );
  }

  /// Normalize a plan value so a malformed DB entry never reaches the UI —
  /// e.g. a pasted Postgres default like `'Basic'::text` becomes `Basic`.
  static String _cleanPlan(String? raw) {
    var p = (raw ?? 'Free').trim();
    // Drop a trailing cast such as ::text / ::varchar.
    final cast = p.indexOf('::');
    if (cast != -1) p = p.substring(0, cast).trim();
    // Strip surrounding single or double quotes.
    if (p.length >= 2) {
      final f = p[0], l = p[p.length - 1];
      if ((f == "'" && l == "'") || (f == '"' && l == '"')) {
        p = p.substring(1, p.length - 1).trim();
      }
    }
    return p.isEmpty ? 'Free' : p;
  }

  /// First name (or a sensible fallback) for greetings/avatars.
  String displayName(String? email) {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'there';
  }
}
