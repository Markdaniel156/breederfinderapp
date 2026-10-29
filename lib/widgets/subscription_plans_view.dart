import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../services/paymongo_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/restricted_access_dialog.dart';
import '../widgets/solo_plan_transparency_card.dart';
import '../screens/subscription_screen.dart'; // For PayMongoWebView and dialogs

class SubscriptionPlansView extends StatefulWidget {
  final VoidCallback? onBack;
  const SubscriptionPlansView({super.key, this.onBack});

  @override
  State<SubscriptionPlansView> createState() => _SubscriptionPlansViewState();
}

class _SubscriptionPlansViewState extends State<SubscriptionPlansView> {
  bool _isLoading = false;
  int _selectedPlanIndex = 0;

  // Palette
  static const themeGreen = Color(0xFF2D6A4F);
  static const darkGreen = Color(0xFF1B4332);
  static const softGreen = Color(0xFFF1F7F3);
  static const lineGrey = Color(0xFFE5E9E7);
  static const textMuted = Color(0xFF6B7570);

  // Price is stored as a number so we never have to parse it from a string.
  final List<Map<String, dynamic>> _plans = [
    {
      'title': 'Solo',
      'subtitle': 'For individual sellers',
      'price': 499,
      'period': 'per month',
      'features': ['10 postings', 'Priority support', 'Verified badge'],
      'isPopular': true,
    },
    {
      'title': 'Organization',
      'subtitle': 'For teams and groups',
      'price': 999,
      'period': '1 time only',
      'features': ['Unlimited postings', 'Priority support', 'Verified badge'],
      'isPopular': false,
    },
  ];

  // ───────────────────────── Payment logic (unchanged) ─────────────────────────

  Future<void> _handlePayment() async {
    if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
      RestrictedAccessDialog.show(context, 'subscribe to a plan');
      return;
    }
    setState(() => _isLoading = true);

    try {
      final plan = _plans[_selectedPlanIndex];
      final int amountCentavos = (plan['price'] as int) * 100;

      final session = await PayMongoService.createCheckoutSession(
        name: '${plan['title']} Plan Subscription',
        amountInCentavos: amountCentavos,
        successUrl: 'https://success.com',
        cancelUrl: 'https://cancel.com',
      );

      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PayMongoWebView(
            checkoutUrl: session['checkout_url'],
            sessionId: session['id'],
          ),
        ),
      );

      if (result == 'success') {
        await _finalizeSubscription();
      } else if (result == 'cancel') {
        _showSnack('Payment cancelled');
      } else if (result == 'error') {
        _showSnack(
          'Payment verification failed. Please check your transaction or contact support.',
          isError: true,
        );
      }
    } catch (e) {
      _showSnack('Payment error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finalizeSubscription() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final plan = _plans[_selectedPlanIndex];
      final double amount = (plan['price'] as int).toDouble();
      final expiryDate = DateTime.now().add(const Duration(days: 30));

      await Supabase.instance.client.from('subscriptions').insert({
        'user_id': user.id,
        // Keeps the same value your database stored before ("Solo Plan", etc.)
        'plan_name': '${plan['title']} Plan',
        'amount': amount,
        'expires_at': expiryDate.toIso8601String(),
      });

      if (mounted) _showSuccessDialog();
    } catch (e) {
      _showSnack('Error recording subscription: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ───────────────────────────── UI ─────────────────────────────

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: softGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: themeGreen, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'You’re subscribed',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: darkGreen,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your posting limit has been reset. You can add new listings now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textMuted, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.pop(context, true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Continue posting',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SoloPlanTransparencyCard(margin: EdgeInsets.zero),
        const SizedBox(height: 4),
        const Text(
          'Choose your plan',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: darkGreen,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'You’ve reached your posting limit. Pick a plan to keep listing.',
          style: TextStyle(fontSize: 15, color: textMuted, height: 1.4),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _plans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _buildPlanCard(
              _plans[index],
              _selectedPlanIndex == index,
                  () => setState(() => _selectedPlanIndex = index),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildPaymentButton(),
        if (widget.onBack != null)
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: widget.onBack,
              child: const Text(
                'Maybe later',
                style: TextStyle(color: textMuted, fontWeight: FontWeight.w500),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlanCard(
      Map<String, dynamic> plan,
      bool isSelected,
      VoidCallback onTap,
      ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? softGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? themeGreen : lineGrey,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRadio(isSelected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan['title'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: darkGreen,
                            ),
                          ),
                          if (plan['isPopular'] == true) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: themeGreen,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Popular',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan['subtitle'],
                        style: const TextStyle(fontSize: 13, color: textMuted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${plan['price']}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: darkGreen,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (plan['period'] != null)
                      Text(
                        plan['period'],
                        style: const TextStyle(fontSize: 12, color: textMuted),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...(plan['features'] as List<String>).map(
                  (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_rounded, color: themeGreen, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      feature,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2E3A34),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadio(bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? themeGreen : Colors.transparent,
        border: Border.all(
          color: isSelected ? themeGreen : const Color(0xFFC3CCC7),
          width: 1.8,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
          : null,
    );
  }

  Widget _buildPaymentButton() {
    final plan = _plans[_selectedPlanIndex];
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handlePayment,
        style: ElevatedButton.styleFrom(
          backgroundColor: themeGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: themeGreen.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        )
            : Text(
          'Pay ₱${plan['price']} with GCash',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}