import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/breeder_provider.dart';
import '../screens/subscription_screen.dart';

class SoloPlanTransparencyCard extends StatefulWidget {
  final EdgeInsetsGeometry? margin;
  const SoloPlanTransparencyCard({super.key, this.margin});

  @override
  State<SoloPlanTransparencyCard> createState() => _SoloPlanTransparencyCardState();
}

class _SoloPlanTransparencyCardState extends State<SoloPlanTransparencyCard> {
  bool _isLoading = true;
  String? _planName;
  int _postCount = 0;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final provider = Provider.of<BreederProvider>(context, listen: false);
    final plan = await provider.getUserPlan(userId);
    final count = await provider.getSoloPlanPostCount(userId);

    if (mounted) {
      setState(() {
        _planName = plan;
        _postCount = count;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();
    // Only show if user is on the Solo Plan
    if (_planName != 'Solo Plan') return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const themeGreen = Color(0xFF2D6A4F);
    const darkGreen = Color(0xFF1B4332);
    
    final remaining = (10 - _postCount).clamp(0, 10);
    final progress = (_postCount / 10.0).clamp(0.0, 1.0);
    final isFull = _postCount >= 10;

    return Container(
      margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2B22) : const Color(0xFFF4F9F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFull 
              ? Colors.orange.shade700 
              : (isDark ? const Color(0xFF2E4D3E) : themeGreen.withValues(alpha: 0.25)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: (isFull ? Colors.orange : themeGreen).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isFull ? Icons.warning_amber_rounded : Icons.workspace_premium_rounded,
                      color: isFull ? Colors.orange.shade800 : themeGreen,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Solo Plan Usage',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : darkGreen,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isFull ? Colors.orange : themeGreen).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_postCount / 10 Used',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isFull ? Colors.orange.shade800 : themeGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: isDark ? const Color(0xFF2A3C32) : const Color(0xFFE2EFE7),
              valueColor: AlwaysStoppedAnimation<Color>(
                isFull ? Colors.orange.shade700 : themeGreen,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isFull 
                  ? 'Limit reached (10/10 active posts)'
                  : '$remaining listing${remaining == 1 ? '' : 's'} remaining',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isFull 
                      ? Colors.orange.shade800 
                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                ),
              ),
              if (isFull)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
                    );
                  },
                  child: const Text(
                    'Upgrade Plan',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: themeGreen,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
