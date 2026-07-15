import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Razorpay configuration, loaded from `.env` (see `.env.example`).
///
/// Only the **Key ID** belongs in the app. The **Key Secret** must never be
/// shipped in the client — it lives server-side (`supabase/.env`, pushed with
/// `supabase secrets set --env-file supabase/.env`) to create orders and
/// verify payment signatures.
///
/// Get your keys from: Razorpay Dashboard → Settings → API Keys.
class RazorpayConfig {
  RazorpayConfig._();

  /// Publishable key id (safe for the client). Use the `rzp_test_…` key while
  /// developing and switch to `rzp_live_…` for production.
  static String get keyId => dotenv.maybeGet('RAZORPAY_KEY_ID') ?? '';

  /// Display name shown in the Razorpay checkout sheet.
  static const String businessName = 'Spacio';

  /// Accent color for the checkout sheet (matches the app's cream highlight).
  static const String themeColor = '#F6F4EC';

  /// True once a real key id has been filled in.
  static bool get isConfigured =>
      keyId.isNotEmpty && !keyId.startsWith('rzp_test_YOUR');
}
