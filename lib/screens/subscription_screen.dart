import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/razorpay_config.dart';
import '../models/profile.dart';
import '../models/subscription_plan.dart';
import '../models/topup_pack.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Settings → Subscription. Shows the current plan and remaining renders, and
/// lets the user buy top-up render packs via Razorpay.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final Razorpay _razorpay;
  Profile? _profile;
  bool _loading = true;

  /// What's currently being paid for, so the success handler knows what to do.
  TopupPack? _pendingPack;
  SubscriptionPlan? _pendingPlan;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _load();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await SupabaseService.instance.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Buy flow ────────────────────────────────────────────────────────────

  void _openPacksSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PacksSheet(onBuy: _startPayment),
    );
  }

  void _startPayment(TopupPack pack) {
    Navigator.of(context).pop(); // close the sheet
    if (!_ensureConfigured()) return;
    _pendingPlan = null;
    _pendingPack = pack;
    _openCheckout(
      amountPaise: pack.amountPaise,
      description: '${pack.renders} renders — ${pack.name} pack',
    );
  }

  void _startSubscriptionPayment(SubscriptionPlan plan) {
    if (!_ensureConfigured()) return;
    _pendingPack = null;
    _pendingPlan = plan;
    _openCheckout(
      amountPaise: plan.amountPaise,
      description: '${plan.name} subscription — 1 month',
    );
  }

  bool _ensureConfigured() {
    if (RazorpayConfig.isConfigured) return true;
    _toast('Payments aren\'t configured yet — add your Razorpay key id.');
    return false;
  }

  void _openCheckout({required int amountPaise, required String description}) {
    final email = SupabaseService.instance.currentEmail;
    try {
      _razorpay.open({
        'key': RazorpayConfig.keyId,
        'amount': amountPaise,
        'currency': 'INR',
        'name': RazorpayConfig.businessName,
        'description': description,
        'prefill': {'email': ?email},
        'theme': {'color': RazorpayConfig.themeColor},
      });
    } catch (e) {
      _toast('Could not start payment: $e');
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final pack = _pendingPack;
    final plan = _pendingPlan;
    _pendingPack = null;
    _pendingPlan = null;
    if (pack == null && plan == null) return;
    setState(() => _processing = true);
    try {
      // NOTE: For production, verify response.signature server-side before
      // crediting/activating. Here we update directly via the Supabase RPC.
      if (pack != null) {
        await SupabaseService.instance.addTopupRenders(
          pack: pack,
          paymentId: response.paymentId,
          orderId: response.orderId,
        );
        await _load();
        if (mounted) _toast('${pack.renders} renders added to your account.');
      } else if (plan != null) {
        await SupabaseService.instance.activateByodSubscription(
          plan: plan,
          paymentId: response.paymentId,
          orderId: response.orderId,
        );
        await _load();
        if (mounted) _toast('${plan.name} activated for 1 month.');
      }
    } catch (e) {
      if (!mounted) return;
      _toast(
        'Payment succeeded (${response.paymentId}) but updating your account '
        'failed. Contact support.',
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    _pendingPack = null;
    _pendingPlan = null;
    final msg = response.message?.trim();
    _toast(
      msg == null || msg.isEmpty ? 'Payment cancelled or failed.' : msg,
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _toast('Selected wallet: ${response.walletName ?? 'external'}');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Subscription'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cream),
            )
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  _planCard(profile),
                  const SizedBox(height: 14),
                  _subscriptionSection(profile),
                  const SizedBox(height: 14),
                  _rendersRow(
                    'Remaining monthly renders',
                    '${profile?.rendersLeft ?? 0} of '
                        '${SubscriptionPlan.includedRendersFor(profile?.plan)}',
                    Icons.calendar_month_rounded,
                  ),
                  const SizedBox(height: 10),
                  _rendersRow(
                    'Top-up renders',
                    '${profile?.topupRendersLeft ?? 0}',
                    Icons.add_circle_outline_rounded,
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Monthly renders are used first; top-up renders are used '
                      'after and carry forward until consumed.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _processing ? null : _openPacksSheet,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.cream,
                        foregroundColor: AppColors.onCream,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _processing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onCream,
                              ),
                            )
                          : const Icon(Icons.add_shopping_cart_rounded,
                              size: 20),
                      label: Text(
                        _processing ? 'Adding renders…' : 'Buy More Renders',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Device merchants (Type 1) see a preloaded note; BYOD merchants (Type 2)
  /// see their subscription status and a subscribe/renew button.
  Widget _subscriptionSection(Profile? profile) {
    if (profile == null) return const SizedBox.shrink();

    if (profile.isDeviceMerchant) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_rounded, color: Colors.green, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Subscription active — included with your SPACIO device.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // BYOD (Type 2) — must purchase / renew.
    final plan = SubscriptionPlan.byod;
    final active = profile.subscriptionActive;
    final until = profile.subscriptionActiveUntil;
    final statusText = active
        ? 'Active until ${_fmtDate(until!)}'
        : (until == null
            ? 'No active subscription'
            : 'Expired on ${_fmtDate(until)}');
    final statusColor =
        active ? Colors.green : Theme.of(context).colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${plan.name} · ${plan.priceLabel}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _processing ? null : () => _startSubscriptionPayment(plan),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cream,
                foregroundColor: AppColors.onCream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.workspace_premium_rounded, size: 20),
              label: Text(
                active
                    ? 'Renew (${plan.priceLabel})'
                    : 'Subscribe (${plan.priceLabel})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _planCard(Profile? profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MONTHLY PLAN',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppColors.cream, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.plan ?? 'Free',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (SubscriptionPlan.byId(profile?.plan) case final plan?)
                      Text(
                        '${plan.priceLabel} · ${plan.monthlyRenders} renders/mo',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${profile?.totalRendersLeft ?? 0} left',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rendersRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom sheet listing the three top-up packs.
class _PacksSheet extends StatelessWidget {
  final void Function(TopupPack) onBuy;
  const _PacksSheet({required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Buy more renders',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 19,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Top-up renders never expire — they carry forward until used.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ...TopupPack.all.map((p) => _PackCard(pack: p, onBuy: onBuy)),
          ],
        ),
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  final TopupPack pack;
  final void Function(TopupPack) onBuy;
  const _PackCard({required this.pack, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${pack.renders} Renders',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pack.name} · ${pack.priceLabel}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => onBuy(pack),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cream,
              foregroundColor: AppColors.onCream,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Buy Now',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
