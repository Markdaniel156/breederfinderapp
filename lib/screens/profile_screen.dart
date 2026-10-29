import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/theme_provider.dart';
import '../providers/breeder_provider.dart';
import '../models/breeder.dart';
import 'chat_screen.dart';
import 'report_user_screen.dart';
import 'breeder_postings_screen.dart';
import 'trader_postings_screen.dart';
import 'privacy_policy_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_privacy_screen.dart';
import 'help_center_screen.dart';
import 'apply_seller_screen.dart';
import 'subscription_screen.dart';
import '../widgets/restricted_access_dialog.dart';
import '../providers/auth_provider.dart';
import '../widgets/limit_reached_card.dart';
import '../widgets/solo_plan_transparency_card.dart';
import '../utils/location_utils.dart';
import '../utils/system_ui_utils.dart';

// ─── Design tokens ──────────────────────────────────────────────────────────
const _green = Color(0xFF2D6A4F);
const _bgLight = Color(0xFFFAFAF7);
const _bgDark = Color(0xFF121212);
const _surfaceLight = Color(0xFFF1F3EE);
const _surfaceDark = Color(0xFF1E1E1E);

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _userData;
  bool _loading = true;
  bool _isLimitReached = false;
  late TabController _tabController;
  late bool _isCurrentUser;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _isCurrentUser = !authProvider.isGuest &&
        (widget.userId == null ||
            widget.userId == supabase.auth.currentUser?.id);
    _tabController = TabController(length: _isCurrentUser ? 2 : 1, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final targetId = widget.userId ?? supabase.auth.currentUser?.id;
      if (targetId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final data = await supabase
          .from('create_account')
          .select()
          .eq('id', targetId)
          .single();

      bool hasLimit = false;
      if (_isCurrentUser && mounted) {
        final provider = Provider.of<BreederProvider>(context, listen: false);
        hasLimit = await provider.hasReachedListingLimit(targetId);
      }

      if (!mounted) return;
      setState(() {
        _userData = data;
        _isLimitReached = hasLimit;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _bgDark : _bgLight;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: _green)),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      endDrawer: _isCurrentUser
          ? _buildEndDrawer(context, themeProvider, isDark, _green)
          : null,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiUtils.getOverlayStyle(isDark: isDark, navBarColor: bg),
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: false,
              floating: true,
              backgroundColor: bg,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Colors.white : Colors.black87, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              actions: _isCurrentUser
                  ? [
                Builder(
                  builder: (context) => IconButton(
                    icon: Icon(Icons.menu_rounded,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 26),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
                const SizedBox(width: 4),
              ]
                  : null,
            ),
            SliverToBoxAdapter(child: _buildProfileHeader(isDark, _green)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: _green,
                  indicatorWeight: 2,
                  dividerColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  labelColor: _green,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 14),
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: [
                    const Tab(text: 'Listings'),
                    if (_isCurrentUser) const Tab(text: 'Favorites'),
                  ],
                ),
                isDark,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildMyListingsTab(context, _green, isDark),
              if (_isCurrentUser) _buildMyFavoritesTab(context, _green, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildProfileHeader(bool isDark, Color themeGreen) {
    final role = _userData?['role']?.toString() ?? 'Customer';
    final location = LocationUtils.sanitizeAddress(
        '${_userData?['barangay'] ?? 'N/A'}, ${_userData?['city_municipality'] ?? 'N/A'}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: isDark ? _surfaceDark : _surfaceLight,
                backgroundImage: _userData?['avatar_url'] != null
                    ? NetworkImage(_userData!['avatar_url'])
                    : null,
                child: _userData?['avatar_url'] == null
                    ? Icon(Icons.person_rounded,
                    size: 48, color: Colors.grey[500])
                    : null,
              ),
              if (_isCurrentUser)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () async {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfileScreen(
                            currentName: _userData?['full_name'] ?? '',
                            currentAvatarUrl: _userData?['avatar_url'],
                          ),
                        ),
                      );
                      if (updated == true) _loadUserData();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: themeGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: isDark ? _bgDark : _bgLight, width: 3),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _userData?['full_name'] ?? 'Guest User',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 15, color: Colors.grey[600]),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  location,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: themeGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role.isEmpty ? 'Customer' : _titleCase(role),
              style: TextStyle(
                  color: themeGreen, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          if (!_isCurrentUser) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (Provider.of<AuthProvider>(context, listen: false)
                      .isGuest) {
                    RestrictedAccessDialog.show(
                        context, 'chat with breeders and traders');
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        breederId: _userData?['id'] ?? '',
                        breederName: _userData?['full_name'] ?? 'User',
                        breederAvatarUrl: _userData?['avatar_url'] ?? '',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Message',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _titleCase(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  // ─── Drawer ───────────────────────────────────────────────────────────────

  Widget _buildEndDrawer(BuildContext context, ThemeProvider themeProvider,
      bool isDark, Color themeGreen) {
    final verified = _userData?['verification_status'] == 'VERIFIED';

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      backgroundColor: isDark ? _bgDark : _bgLight,
      child: Column(
        children: [
          _buildDrawerHeader(isDark, themeGreen),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _buildSectionTitle('General'),
                _buildSettingsItem(
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark mode',
                  themeGreen: themeGreen,
                  trailing: Text(
                    themeProvider.themeMode == ThemeMode.dark
                        ? 'On'
                        : (themeProvider.themeMode == ThemeMode.light
                        ? 'Off'
                        : 'System'),
                    style: TextStyle(
                        color: themeGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  onTap: () => _showDarkModeDialog(themeProvider, isDark),
                ),
                _buildSettingsItem(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit profile',
                  themeGreen: themeGreen,
                  onTap: () async {
                    Navigator.pop(context);
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditProfileScreen(
                          currentName: _userData?['full_name'] ?? '',
                          currentAvatarUrl: _userData?['avatar_url'],
                        ),
                      ),
                    );
                    if (updated == true) _loadUserData();
                  },
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('Account safety'),
                _buildSettingsItem(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change password',
                  themeGreen: themeGreen,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/change-password');
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.shield_outlined,
                  title: 'Map privacy',
                  themeGreen: themeGreen,
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsPrivacyScreen(
                          initialPrivacyMode:
                          _userData?['privacy_mode'] ?? 'Exact',
                        ),
                      ),
                    );
                    if (result == true) _loadUserData();
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.verified_user_outlined,
                  title: 'Identity verification',
                  themeGreen: themeGreen,
                  trailing: Text(
                    verified
                        ? 'Verified'
                        : _titleCase(
                        _userData?['verification_status'] ?? 'Pending'),
                    style: TextStyle(
                      color: verified ? _green : Colors.orange,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_isCurrentUser &&
                    _userData?['role']?.toString().toUpperCase() == 'CUSTOMER')
                  _buildSettingsItem(
                    icon: Icons.storefront_outlined,
                    title: 'Become a seller',
                    themeGreen: themeGreen,
                    onTap: () async {
                      Navigator.pop(context);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ApplySellerScreen()),
                      );
                      if (result == true) _loadUserData();
                    },
                  ),
                const SizedBox(height: 12),
                _buildSectionTitle('Support'),
                _buildSettingsItem(
                  icon: Icons.help_outline_rounded,
                  title: 'Help center',
                  themeGreen: themeGreen,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const HelpCenterScreen()));
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.policy_outlined,
                  title: 'Privacy policy',
                  themeGreen: themeGreen,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const PrivacyPolicyScreen()));
                  },
                ),
              ],
            ),
          ),
          _buildLogoutButton(context, themeGreen, isDark),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(bool isDark, Color themeGreen) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 28, 24, 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: themeGreen.withValues(alpha: 0.1),
            backgroundImage: _userData?['avatar_url'] != null
                ? NetworkImage(_userData!['avatar_url'])
                : null,
            child: _userData?['avatar_url'] == null
                ? Icon(Icons.person_rounded, color: themeGreen, size: 26)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userData?['full_name'] ?? 'User',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  _userData?['email'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Text(
        title,
        style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey[500]),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required Color themeGreen,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: themeGreen, size: 22),
      title: Text(title,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[400]),
    );
  }

  Widget _buildLogoutButton(
      BuildContext context, Color themeGreen, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: TextButton.icon(
        onPressed: () async {
          final confirm = await _showLogoutConfirmation();
          if (confirm == true) {
            await supabase.auth.signOut();
            if (mounted && context.mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            }
          }
        },
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text('Log out',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        style: TextButton.styleFrom(
          foregroundColor: Colors.redAccent,
          backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
          minimumSize: const Size(double.infinity, 50),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ─── Posting flow (logic unchanged) ───────────────────────────────────────

  void _showRegistrationOptions(
      BuildContext context, Color themeGreen, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? _surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(isDark),
            const Text('New listing',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _buildRegistrationOption(
              context,
              Icons.pets_rounded,
              'Breeder listing',
              'Post as a professional breeder',
              themeGreen,
                  () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const BreederPostingsScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            _buildRegistrationOption(
              context,
              Icons.shopping_bag_outlined,
              'Trader listing',
              'Post as an animal trader',
              Colors.orange,
                  () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const TraderPostingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHandle(bool isDark) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: isDark ? Colors.white24 : Colors.grey[300],
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _buildRegistrationOption(
      BuildContext context,
      IconData icon,
      String title,
      String subtitle,
      Color color,
      VoidCallback onTap,
      ) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }

  void _handleAddNewListing(
      BuildContext context, Color themeGreen, bool isDark) {
    final role = _userData?['role']?.toString().toUpperCase();

    if (role == 'CUSTOMER' || role == null || role.isEmpty) {
      _handleCustomerAction(context, themeGreen);
    } else if (role == 'BREEDER AND TRADER') {
      _showRegistrationOptions(context, themeGreen, isDark);
    } else if (role == 'BREEDER') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const BreederPostingsScreen()),
      );
    } else if (role == 'TRADER') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TraderPostingsScreen()),
      );
    } else {
      _handleCustomerAction(context, themeGreen);
    }
  }

  Future<void> _handleCustomerAction(
      BuildContext context, Color themeGreen) async {
    final userId = widget.userId ?? supabase.auth.currentUser?.id;
    if (userId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          Center(child: CircularProgressIndicator(color: themeGreen)),
    );

    Map<String, dynamic>? pendingApp;
    try {
      pendingApp = await supabase
          .from('seller_applications')
          .select('role_applied, status')
          .eq('user_id', userId)
          .eq('status', 'PENDING')
          .maybeSingle();
    } catch (e) {
      debugPrint('Error checking seller application: $e');
    }

    if (context.mounted) {
      Navigator.pop(context); // Dismiss loading

      if (pendingApp != null) {
        final appliedRole =
            pendingApp['role_applied']?.toString() ?? 'Breeder or Trader';
        _showPendingApplicationDialog(context, themeGreen, appliedRole);
      } else {
        _showCustomerCannotPostDialog(context, themeGreen);
      }
    }
  }

  /// One simple dialog layout shared by the status dialogs.
  void _showStatusDialog({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required String primaryLabel,
    required VoidCallback onPrimary,
    String? secondaryLabel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? _surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: isDark ? Colors.white70 : Colors.black54)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(primaryLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              if (secondaryLabel != null)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(secondaryLabel,
                      style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPendingApplicationDialog(
      BuildContext context, Color themeGreen, String appliedRole) {
    _showStatusDialog(
      context: context,
      icon: Icons.hourglass_top_rounded,
      color: Colors.amber,
      title: 'Application under review',
      message:
      'Your application to become a $appliedRole is being reviewed. Once approved, you can start posting listings.',
      primaryLabel: 'Got it',
      onPrimary: () => Navigator.pop(context),
    );
  }

  void _showCustomerCannotPostDialog(BuildContext context, Color themeGreen) {
    _showStatusDialog(
      context: context,
      icon: Icons.lock_outline_rounded,
      color: themeGreen,
      title: 'Posting is for sellers',
      message:
      'Customer accounts can\'t post listings. Apply to become a Breeder or Trader to start posting animals for sale.',
      primaryLabel: 'Apply as seller',
      secondaryLabel: 'Not now',
      onPrimary: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ApplySellerScreen()),
        );
      },
    );
  }

  // ─── Tabs ─────────────────────────────────────────────────────────────────

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    childAspectRatio: 0.8,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
  );

  Widget _listingImage(Breeder item, bool isDark) {
    if (item.animals.isNotEmpty) {
      return Image.network(
        item.animals.first.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imagePlaceholder(isDark),
      );
    }
    return _imagePlaceholder(isDark);
  }

  Widget _imagePlaceholder(bool isDark) => Container(
    color: isDark ? _surfaceDark : _surfaceLight,
    child: Icon(Icons.pets_rounded, color: Colors.grey[400]),
  );

  Widget _buildMyListingsTab(
      BuildContext context, Color themeGreen, bool isDark) {
    final provider = Provider.of<BreederProvider>(context);
    final targetId = widget.userId ?? supabase.auth.currentUser?.id;
    final myListings =
    provider.breeders.where((b) => b.userId == targetId).toList();
    final isCustomer =
        _userData?['role']?.toString().toUpperCase() == 'CUSTOMER';
    final showAddButton = _isCurrentUser && !isCustomer;

    return CustomScrollView(
      cacheExtent: 1000.0,
      slivers: [
        if (_isCurrentUser)
          const SliverToBoxAdapter(
            child: SoloPlanTransparencyCard(
              margin: EdgeInsets.fromLTRB(16, 16, 16, 4),
            ),
          ),
        if (_isLimitReached)
          SliverToBoxAdapter(
            child: LimitReachedCard(
              margin: const EdgeInsets.all(16),
              onUpgrade: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SubscriptionScreen()),
                );
                if (result == true) await _loadUserData();
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: _gridDelegate,
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                if (showAddButton && index == 0) {
                  return GestureDetector(
                    onTap: () =>
                        _handleAddNewListing(context, themeGreen, isDark),
                    child: Container(
                      decoration: BoxDecoration(
                        color: themeGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 30, color: themeGreen),
                          const SizedBox(height: 4),
                          Text('New',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: themeGreen)),
                        ],
                      ),
                    ),
                  );
                }

                final listing = myListings[showAddButton ? index - 1 : index];
                return GestureDetector(
                  onTap: () =>
                      _showPostDetails(context, listing, isDark, themeGreen),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _listingImage(listing, isDark),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '₱${listing.price}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount:
              showAddButton ? myListings.length + 1 : myListings.length,
            ),
          ),
        ),
        if (myListings.isEmpty && !showAddButton)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(Icons.pets_outlined, 'No listings yet',
                'Listings will show up here once they are posted.'),
          ),
      ],
    );
  }

  Widget _buildMyFavoritesTab(
      BuildContext context, Color themeGreen, bool isDark) {
    final breederProvider = Provider.of<BreederProvider>(context);
    final favorites = breederProvider.favoriteBreeders;

    if (favorites.isEmpty) {
      return _buildEmptyState(Icons.favorite_border_rounded, 'No favorites yet',
          'Tap the heart on a listing to save it here.');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: _gridDelegate,
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index];
        return GestureDetector(
          onTap: () => _showPostDetails(context, item, isDark, themeGreen),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _listingImage(item, isDark),
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.favorite_rounded,
                      color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ─── Post details sheet ───────────────────────────────────────────────────

  void _showPostDetails(
      BuildContext context, Breeder item, bool isDark, Color themeGreen) {
    final isOwner = item.userId == supabase.auth.currentUser?.id;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? _surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(child: _sheetHandle(isDark)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 22)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(item.type,
                                style: TextStyle(
                                    color: themeGreen,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            const SizedBox(width: 12),
                            if (!isOwner)
                              GestureDetector(
                                onTap: () {
                                  if (Provider.of<AuthProvider>(context,
                                      listen: false)
                                      .isGuest) {
                                    RestrictedAccessDialog.show(
                                        context, 'report a user');
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ReportUserScreen(
                                        reportedUserId: item.userId,
                                        reportedUserName: item.name,
                                        listingId: item.id,
                                      ),
                                    ),
                                  );
                                },
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.flag_outlined,
                                        color: Colors.red, size: 14),
                                    SizedBox(width: 3),
                                    Text('Report',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),
              _detailHeading('About'),
              const SizedBox(height: 8),
              Text(
                  item.description.isNotEmpty
                      ? item.description
                      : 'No description provided.',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.5)),
              const SizedBox(height: 24),
              _detailHeading('Photos'),
              const SizedBox(height: 12),
              if (item.animals.isEmpty)
                const Center(child: Text('No photos available.'))
              else
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: item.animals.length,
                    itemBuilder: (_, i) => _buildPhotoItem(
                        context, item.animals[i].imageUrl, isDark),
                  ),
                ),
              const SizedBox(height: 24),
              _detailHeading('Details'),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.pets_outlined, 'Breed', item.breed, isDark),
              if (item.gender.isNotEmpty)
                _buildDetailRow(
                    Icons.transgender_rounded, 'Gender', item.gender, isDark),
              if (item.age.isNotEmpty)
                _buildDetailRow(Icons.cake_outlined, 'Age', item.age, isDark),
              _buildDetailRow(
                  Icons.category_outlined, 'Category', item.category, isDark),
              _buildDetailRow(
                  Icons.location_on_outlined, 'Location', item.address, isDark),
              _buildDetailRow(
                  Icons.phone_outlined, 'Contact', item.contactNumber, isDark),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final isGuest =
                            Provider.of<AuthProvider>(context, listen: false)
                                .isGuest;
                        if (isOwner && !isGuest) {
                          Navigator.pop(context);
                          if (item.type == 'Breeder') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      BreederPostingsScreen(initialData: item)),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      TraderPostingsScreen(initialData: item)),
                            );
                          }
                        } else {
                          if (isGuest) {
                            RestrictedAccessDialog.show(
                                context, 'chat with breeders and traders');
                            return;
                          }
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    breederId: item.userId,
                                    breederName: item.name,
                                    breederAvatarUrl: item.imageUrl,
                                  )));
                        }
                      },
                      icon: Icon(
                          isOwner
                              ? Icons.edit_outlined
                              : Icons.chat_bubble_outline_rounded,
                          size: 18),
                      label: Text(isOwner ? 'Edit listing' : 'Contact seller'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  if (isOwner) ...[
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () async {
                        final breederProvider = Provider.of<BreederProvider>(
                            context,
                            listen: false);
                        final itemType = item.type;
                        final itemId = item.id;

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            title: const Text('Delete listing'),
                            content: Text(
                                'Are you sure you want to delete your $itemType post?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          if (!context.mounted) return;
                          try {
                            await breederProvider.deleteListing(
                                itemId, itemType);
                            if (!context.mounted) return;
                            Navigator.pop(context); // Close details sheet
                            _showStatusDialog(
                              context: context,
                              icon: Icons.check_rounded,
                              color: Colors.green,
                              title: 'Listing deleted',
                              message:
                              'Your $itemType post and its images have been removed.',
                              primaryLabel: 'OK',
                              onPrimary: () => Navigator.of(context).pop(),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                        padding: const EdgeInsets.all(13),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailHeading(String text) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17));

  Widget _buildDetailRow(
      IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Text('$label  ',
              style: TextStyle(
                  fontWeight: FontWeight.w500, color: Colors.grey[600])),
          Expanded(
            child: Text(value.isNotEmpty ? value : 'N/A',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoItem(BuildContext context, String url, bool isDark) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              InteractiveViewer(child: Center(child: Image.network(url))),
              Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context))),
            ],
          ),
        ),
      ),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        ),
      ),
    );
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showDarkModeDialog(ThemeProvider provider, bool isDark) {
    Widget option(String label, ThemeMode mode, BuildContext ctx) =>
        RadioListTile<ThemeMode>(
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          value: mode,
          groupValue: provider.themeMode,
          activeColor: _green,
          onChanged: (val) {
            if (val != null) provider.setThemeMode(val);
            Navigator.pop(ctx);
          },
        );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? _surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Dark mode',
            style: TextStyle(fontWeight: FontWeight.w700)),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option('Off', ThemeMode.light, context),
            option('On', ThemeMode.dark, context),
            option('System', ThemeMode.system, context),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showLogoutConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
        const Text('Log out', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar, this.isDark);

  final TabBar _tabBar;
  final bool isDark;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? _bgDark : _bgLight,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) =>
      oldDelegate.isDark != isDark;
}