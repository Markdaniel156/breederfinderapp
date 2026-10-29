import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/navigation_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import 'restricted_access_dialog.dart';
import '../screens/apply_seller_screen.dart';

class AestheticBottomBar {
  static const themeGreen = Color(0xFF2D6A4F);

  /// Raised center button (icon on top, label below) with a ring that
  /// matches the bar color, so it looks "cut into" the bar.
  static Widget buildFloatingActionButton(BuildContext context, bool isDark, String? userRole) {
    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final roleUpper = userRole?.toUpperCase() ?? 'CUSTOMER';
    final isCustomer = roleUpper == 'CUSTOMER' || roleUpper.isEmpty;
    final isTraderOnly = roleUpper == 'TRADER';
    final isBreederAndTrader = roleUpper.contains('BREEDER') && roleUpper.contains('TRADER');

    return Tooltip(
      message: isCustomer ? 'Apply to Post' : (isTraderOnly ? 'Trader Registration' : 'Breeder Registration'),
      child: Container(
        height: 68,
        width: 68,
        decoration: BoxDecoration(
          color: themeGreen,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? const Color(0xFF14241B) : Colors.white,
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: themeGreen.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              if (authProvider.isGuest) {
                RestrictedAccessDialog.show(context, 'post animals for sale');
                return;
              }
              if (isCustomer) {
                _handleCustomerPostAction(context);
                return;
              }
              if (isBreederAndTrader) {
                _showRegistrationOptions(context, isDark);
              } else if (isTraderOnly) {
                navProvider.setIndex(5);
              } else {
                navProvider.setIndex(2);
              }
            },
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 26),
                SizedBox(height: 1),
                Text(
                  'Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _handleCustomerPostAction(BuildContext context) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: themeGreen),
      ),
    );

    Map<String, dynamic>? pendingApp;
    try {
      pendingApp = await Supabase.instance.client
          .from('seller_applications')
          .select('role_applied, status')
          .eq('user_id', user.id)
          .eq('status', 'PENDING')
          .maybeSingle();
    } catch (e) {
      debugPrint('Error fetching application status: $e');
    }

    if (context.mounted) {
      Navigator.pop(context); // Dismiss loading

      if (pendingApp != null) {
        final appliedRole = pendingApp['role_applied']?.toString() ?? 'Breeder or Trader';
        _showPendingApplicationDialog(context, appliedRole);
      } else {
        _showCustomerCannotPostDialog(context);
      }
    }
  }

  static void _showPendingApplicationDialog(BuildContext context, String appliedRole) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        backgroundColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        content: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 60),
              ),
              const SizedBox(height: 25),
              const Text(
                '⏳ Application Under Review',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B4332),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                'Your application to become a $appliedRole has been submitted and is currently being reviewed by the admin. Once approved, you will be able to post listings.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text(
                    'Got It',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showCustomerCannotPostDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        backgroundColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        content: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: themeGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded, color: themeGreen, size: 60),
              ),
              const SizedBox(height: 25),
              const Text(
                '🔒 Posting Restricted',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B4332),
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                'Customer accounts cannot post listings directly. To start posting animals for sale, please apply to become a Breeder or Trader.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ApplySellerScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text(
                    'Apply as Breeder or Trader',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showRegistrationOptions(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Select Posting Category',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ListTile(
              onTap: () {
                Navigator.pop(context);
                Provider.of<NavigationProvider>(context, listen: false).setIndex(2);
              },
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: themeGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.pets_rounded, color: themeGreen),
              ),
              title: const Text('Breeder Posting', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Post listings as a breeder', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ),
            const SizedBox(height: 12),
            ListTile(
              onTap: () {
                Navigator.pop(context);
                Provider.of<NavigationProvider>(context, listen: false).setIndex(5);
              },
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shopping_cart_rounded, color: Colors.orange),
              ),
              title: const Text('Trader Posting', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Post listings as a trader', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Flat, full-width bar with rounded top corners.
  static Widget buildBottomNavigationBar(BuildContext context, bool isDark) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14241B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Expanded(child: _buildNavItem(context, 0, Icons.home_rounded, Icons.home_outlined, 'Home')),
            Expanded(child: _buildNavItem(context, 1, Icons.map_rounded, Icons.map_outlined, 'Map')),
            const SizedBox(width: 76), // space for the raised center button
            Expanded(child: _buildNavItem(context, 3, Icons.storefront_rounded, Icons.storefront_outlined, 'AniMarket')),
            Expanded(child: _buildNavItem(context, 4, Icons.forum_rounded, Icons.forum_outlined, 'Chat')),
          ],
        ),
      ),
    );
  }

  static Widget _buildNavItem(
      BuildContext context,
      int index,
      IconData selectedIcon,
      IconData unselectedIcon,
      String label,
      ) {
    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = navProvider.selectedIndex == index;
    final inactive = isDark ? Colors.grey[500]! : Colors.grey[500]!;

    return GestureDetector(
      onTap: () {
        if (index == 4 && Provider.of<AuthProvider>(context, listen: false).isGuest) {
          RestrictedAccessDialog.show(context, 'chat with breeders and traders');
          return;
        }
        navProvider.setIndex(index);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? selectedIcon : unselectedIcon,
                  key: ValueKey(isSelected),
                  color: isSelected ? themeGreen : inactive,
                  size: 24,
                ),
              ),
              if (index == 4)
                Consumer<ChatProvider>(
                  builder: (context, chatProvider, _) {
                    if (chatProvider.unreadCount == 0) return const SizedBox.shrink();
                    return Positioned(
                      top: -4,
                      right: -7,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF14241B) : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          chatProvider.unreadCount > 9 ? '9+' : '${chatProvider.unreadCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? themeGreen : inactive,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
