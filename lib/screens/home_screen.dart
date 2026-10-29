import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/navigation_provider.dart';
import '../providers/breeder_provider.dart';
import '../providers/notification_provider.dart';
import '../models/breeder.dart';
import '../models/review.dart';
import '../services/chat_service.dart';
import '../services/time_utils.dart';

import 'profile_screen.dart';
import 'chat_screen.dart';
import '../utils/system_ui_utils.dart';
import 'feedback_screen.dart';
import 'report_user_screen.dart';
import 'notification_screen.dart';
import 'smart_matching_screen.dart';
import 'animal_fun_facts_screen.dart';

import '../widgets/home/home_header.dart';
import '../widgets/home/promo_banner.dart';
import '../widgets/home/category_tile.dart';
import '../widgets/home/listing_item.dart';
import '../widgets/restricted_access_dialog.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  String _filterType = 'All'; // 'All', 'Breeder', 'Trader'
  String _searchQuery = '';
  String? _filterAnimal;
  String? _filterBreed;
  String? _filterLocation;
  int _promoIndex = 0;
  String _displayedHint = '';
  final TextEditingController _searchController = TextEditingController();

  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _userData;
  bool _isOffline = false;
  Position? _currentPosition;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _activityTimer;

  static const themeGreen = Color(0xFF2D6A4F);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadUserData();
    _getCurrentLocation();
    _startPeriodicActivityUpdate();
    _startTypingAnimation();
    _checkConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        final wasOffline = _isOffline;
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
        });
        if (wasOffline && !_isOffline) {
          _updateActivity();
          Provider.of<BreederProvider>(context, listen: false).fetchBreeders(silent: true);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<BreederProvider>(context, listen: false).fetchBreeders();
        Provider.of<NotificationProvider>(context, listen: false).fetchNotifications();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateActivity();
      Provider.of<BreederProvider>(context, listen: false).fetchBreeders(silent: true);
    }
  }

  void _startPeriodicActivityUpdate() {
    _updateActivity();
    _activityTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateActivity();
    });
  }

  void _startTypingAnimation() async {
    final hints = [
      'Search breeders...',
      'Search specific breeds...',
      'Search by location...',
      'Find trusted traders...',
      'Looking for a pet?',
      'Search for contact details...',
    ];
    int hintIndex = 0;

    while (mounted) {
      String fullText = hints[hintIndex];
      // Typing forward
      for (int i = 0; i <= fullText.length; i++) {
        if (!mounted) return;
        if (_searchController.text.isEmpty) {
          setState(() => _displayedHint = fullText.substring(0, i));
        }
        await Future.delayed(const Duration(milliseconds: 70));
      }

      // Pause at the end
      await Future.delayed(const Duration(seconds: 2));

      // Deleting
      for (int i = fullText.length; i >= 0; i--) {
        if (!mounted) return;
        if (_searchController.text.isEmpty) {
          setState(() => _displayedHint = fullText.substring(0, i));
        }
        await Future.delayed(const Duration(milliseconds: 30));
      }

      hintIndex = (hintIndex + 1) % hints.length;
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentPosition = position);
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activityTimer?.cancel();
    _connectivitySubscription.cancel();
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updateActivity() async {
    if (Provider.of<AuthProvider>(context, listen: false).isGuest) return;
    final chatService = ChatService();
    await chatService.updateLastSeen();

    // Check if user is blocked
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('create_account')
            .select('verification_status')
            .eq('id', user.id)
            .single();

        if (data['verification_status'] == 'BLOCKED') {
          if (mounted) _showBlockedDialog();
        }
      }
    } catch (e) {
      debugPrint('Error checking blocked status: $e');
    }
  }

  void _showBlockedDialog() {
    if (!mounted) return;
    _activityTimer?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        elevation: 0,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFC72C41).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.block_flipped, color: Color(0xFFC72C41), size: 56),
            ),
            const SizedBox(height: 26),
            const Text(
              'ACCOUNT BLOCKED',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFFC72C41),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Your account has been blocked by the administrator. You will be redirected to the login page.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.55),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await supabase.auth.signOut();
                  navigator.pushNamedAndRemoveUntil('/login', (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC72C41),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('OKAY', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUserData() async {
    try {
      if (Provider.of<AuthProvider>(context, listen: false).isGuest) return;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('create_account')
            .select('full_name, avatar_url, verification_status')
            .eq('id', user.id)
            .single();

        if (data['verification_status'] == 'BLOCKED') {
          if (mounted) _showBlockedDialog();
          return;
        }

        String avatarUrl = data['avatar_url'] ?? '';
        if (avatarUrl.isNotEmpty && !avatarUrl.startsWith('http')) {
          avatarUrl = supabase.storage.from('avatars').getPublicUrl(avatarUrl);
        }

        if (mounted) {
          setState(() {
            _userData = {
              'full_name': data['full_name'],
              'avatar_url': avatarUrl,
            };
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading home user data: $e');
    }
  }

  void _navigateToFeedback(BuildContext context) {
    if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
      RestrictedAccessDialog.show(context, 'send feedback');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FeedbackScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final breederProvider = Provider.of<BreederProvider>(context);
    final notificationProvider = Provider.of<NotificationProvider>(context);
    final hasData = breederProvider.breeders.isNotEmpty;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1A14) : const Color(0xFFF6F8F6),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF0F1A14) : const Color(0xFFF6F8F6),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: RefreshIndicator(
            onRefresh: () => breederProvider.fetchBreeders(),
            color: themeGreen,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              cacheExtent: 1000.0,
              slivers: [
                SliverToBoxAdapter(
                  child: HomeHeader(
                    userData: _userData,
                    unreadCount: notificationProvider.unreadCount,
                    onMapTap: () => Provider.of<NavigationProvider>(context, listen: false).setIndex(1),
                    onFeedbackTap: () => _navigateToFeedback(context),
                    onNotificationTap: () {
                      if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                        RestrictedAccessDialog.show(context, 'view notifications');
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen()));
                    },
                    onProfileTap: () {
                      if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                        RestrictedAccessDialog.show(context, 'manage your profile');
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())).then((_) => _loadUserData());
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: _buildSearchBar(isDark),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                if (_isOffline) SliverToBoxAdapter(child: _buildOfflineBanner()),
                SliverToBoxAdapter(
                  child: PromoBanner(
                    breedersCount: breederProvider.getBreedersByType('Breeder').length,
                    tradersCount: breederProvider.getBreedersByType('Trader').length,
                    promoIndex: _promoIndex,
                    onPageChanged: (i) => setState(() => _promoIndex = i),
                  ),
                ),
                SliverToBoxAdapter(child: _buildCategoriesSection(breederProvider, isDark)),
                if (breederProvider.isLoading && !hasData)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: themeGreen, strokeWidth: 2.5),
                    ),
                  )
                else if (!hasData)
                  SliverToBoxAdapter(child: _buildEmptyState(isDark))
                else
                  SliverToBoxAdapter(child: _buildContent(breederProvider, isDark)),
                const SliverToBoxAdapter(child: SizedBox(height: 36)),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 14),
          ),
          const SizedBox(width: 10),
          const Text(
            'No Internet Connection',
            style: TextStyle(
              color: Color(0xFF991B1B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2B22) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark
              ? null
              : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value.toLowerCase().trim()),
          style: TextStyle(fontSize: 14.5, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText: _displayedHint,
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[600] : Colors.grey[400],
              fontSize: 14,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.all(11),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.search_rounded, color: themeGreen, size: 18),
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: Container(
                margin: const EdgeInsets.all(11),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.close_rounded,
                    color: isDark ? Colors.grey[400] : Colors.grey[500], size: 18),
              ),
            )
                : GestureDetector(
              onTap: () => _showFilterBottomSheet(isDark),
              child: Container(
                margin: const EdgeInsets.all(11),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_filterAnimal != null || _filterBreed != null || _filterLocation != null)
                      ? themeGreen.withOpacity(0.1)
                      : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.06)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.tune_rounded,
                    color: (_filterAnimal != null || _filterBreed != null || _filterLocation != null)
                        ? themeGreen
                        : (isDark ? Colors.grey[500] : Colors.grey[500]), size: 18),
              ),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(BreederProvider provider, bool isDark) {
    final Map<String, List<Breeder>> grouped = {};
    for (final b in provider.breeders) {
      final key = b.category.trim().isNotEmpty ? b.category.trim() : 'Other';
      grouped.putIfAbsent(key, () => []).add(b);
    }
    final categories = grouped.keys.toList()
      ..sort((a, b) {
        final countA = grouped[a]!.length;
        final countB = grouped[b]!.length;
        if (countB != countA) return countB.compareTo(countA);
        return a.compareTo(b); // Alphabetical secondary sort
      });

    if (categories.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Explore Categories',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  letterSpacing: -0.4,
                ),
              ),
              const Text(
                'See All',
                style: TextStyle(color: themeGreen, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length + 1,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildSmartMatchingTile(isDark);
              }
              final category = categories[index - 1];
              final items = grouped[category]!;
              final isSelected = _searchQuery == category.toLowerCase();
              return CategoryTile(
                category: category,
                items: items,
                isDark: isDark,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _searchController.clear();
                      _searchQuery = '';
                    } else {
                      _searchController.text = category;
                      _searchQuery = category.toLowerCase();
                    }
                  });
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSmartMatchingTile(bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartMatchingScreen())),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2B22) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: themeGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.search_rounded, size: 28, color: themeGreen),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(Icons.pets_rounded, size: 10, color: themeGreen.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Find Match',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A2E),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BreederProvider provider, bool isDark) {
    final List<Breeder> allListings = provider.breeders.where((b) {
      final matchesType = _filterType == 'All' || b.type == _filterType;
      final matchesSearch = _searchQuery.isEmpty ||
          b.name.toLowerCase().contains(_searchQuery) ||
          b.address.toLowerCase().contains(_searchQuery) ||
          b.breed.toLowerCase().contains(_searchQuery) ||
          b.category.toLowerCase().contains(_searchQuery) ||
          b.contactNumber.toLowerCase().contains(_searchQuery);

      final matchesAnimal = _filterAnimal == null || b.category.toLowerCase() == _filterAnimal!.toLowerCase();
      final matchesBreed = _filterBreed == null || b.breed.toLowerCase().contains(_filterBreed!.toLowerCase());
      final matchesLocation = _filterLocation == null || b.address.toLowerCase().contains(_filterLocation!.toLowerCase());

      return matchesType && matchesSearch && matchesAnimal && matchesBreed && matchesLocation;
    }).toList();

    if (allListings.isEmpty) {
      return _buildFilteredEmptyState(isDark);
    }

    final bool showSeeMore = allListings.length >= 6;
    final List<Breeder> displayedListings = showSeeMore ? allListings.take(6).toList() : allListings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
          child: Row(
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _buildFeedLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: themeGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${allListings.length}',
                        style: const TextStyle(
                          color: themeGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildTypeToggle(isDark),
            ],
          ),
        ),
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Results for "$_searchQuery"',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: displayedListings.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (context, index) {
              final item = displayedListings[index];
              final currentUser = supabase.auth.currentUser;
              final isOwnListing = currentUser?.id == item.userId;
              final isFavorited = provider.isFavorite(item.id);
              final isTrader = item.type == 'Trader';

              return ListingItem(
                item: item,
                isDark: isDark,
                isFavorited: isFavorited,
                isOwnListing: isOwnListing,
                userPosition: _currentPosition,
                onTap: () => isTrader ? _showTraderDetails(context, item) : _showAnimalImages(context, item),
                onFavoriteTap: () {
                  if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                    RestrictedAccessDialog.show(context, 'add to favorites');
                    return;
                  }
                  provider.toggleFavorite(item.id);
                  if (!isFavorited) {
                    isTrader ? _showTraderDetails(context, item) : _showAnimalImages(context, item);
                  }
                },
                onReportTap: () {
                  if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                    RestrictedAccessDialog.show(context, 'report a user');
                    return;
                  }
                  if (item.userId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Unable to report: User ID not found')),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReportUserScreen(
                        reportedUserId: item.userId,
                        reportedUserName: item.name.isNotEmpty ? item.name : 'User',
                        listingId: item.id.isNotEmpty ? item.id : null,
                      ),
                    ),
                  );
                },
                onChatTap: () {
                  if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                    RestrictedAccessDialog.show(context, 'chat with breeders and traders');
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        breederId: item.userId,
                        breederName: item.name,
                        breederAvatarUrl: item.imageUrl,
                      ),
                    ),
                  );
                },
                onMapTap: () {
                  Provider.of<NavigationProvider>(context, listen: false)
                      .setIndex(1, breeder: item);
                },
                onProfileTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: item.userId),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (showSeeMore) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () {
                  Provider.of<NavigationProvider>(context, listen: false).setIndex(3);
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: themeGreen.withOpacity(0.4),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: isDark ? const Color(0xFF1A2B22) : themeGreen.withOpacity(0.06),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'See More',
                      style: TextStyle(
                        color: themeGreen,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: themeGreen,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        _buildFunFactsSection(isDark),
      ],
    );
  }

  Widget _buildFunFactsSection(bool isDark) {
    final funFactCards = [
      {
        'emoji': '🐶',
        'category': 'Dogs',
        'title': 'Dog Noseprints',
        'subtitle': 'Unique like human fingerprints!',
        'color': const Color(0xFFE07A5F),
      },
      {
        'emoji': '🐱',
        'category': 'Cats',
        'title': 'Cat Whiskers',
        'subtitle': 'Super sensory radar system!',
        'color': const Color(0xFF81B29A),
      },
      {
        'emoji': '🦜',
        'category': 'Birds',
        'title': 'Parrot Syrinx',
        'subtitle': 'Imitates speech with chest organ!',
        'color': const Color(0xFF118AB2),
      },
      {
        'emoji': '🐰',
        'category': 'Rabbits',
        'title': 'Rabbit Binky',
        'subtitle': 'Joyful jump & mid-air twist!',
        'color': const Color(0xFFEF476F),
      },
      {
        'emoji': '🐴',
        'category': 'Horses',
        'title': 'Standing Sleep',
        'subtitle': 'Lock leg muscles to nap standing!',
        'color': const Color(0xFF9C6644),
      },
      {
        'emoji': '🦎',
        'category': 'Reptiles',
        'title': 'Chameleon Eyes',
        'subtitle': 'Swivel eyes 360° independently!',
        'color': const Color(0xFF52B788),
      },
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: themeGreen.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lightbulb_rounded, color: themeGreen, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Animal Fun Facts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnimalFunFactsScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Explore All',
                    style: TextStyle(
                      color: themeGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 125,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: funFactCards.length,
              itemBuilder: (context, index) {
                final card = funFactCards[index];
                final Color cardColor = card['color'] as Color;

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnimalFunFactsScreen(
                          initialCategory: card['category'] as String,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 170,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A2B22) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cardColor.withOpacity(0.3),
                        width: 1.2,
                      ),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: cardColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                card['emoji'] as String,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cardColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                card['category'] as String,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: cardColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              card['subtitle'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _buildFeedLabel() {
    if (_searchQuery.isNotEmpty) return 'Search Results';
    if (_filterType != 'All') return '$_filterType Feed';
    return 'Latest Feed';
  }

  Widget _buildTypeToggle(bool isDark) {
    final filters = ['All', 'Breeder', 'Trader'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: filters.map((label) {
          final isSelected = _filterType == label;
          return GestureDetector(
            onTap: () => setState(() => _filterType = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? themeGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showFilterBottomSheet(bool isDark) {
    final provider = Provider.of<BreederProvider>(context, listen: false);
    final categories = provider.breeders
        .map((b) => b.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    String? tempAnimal = _filterAnimal;
    final TextEditingController breedController = TextEditingController(text: _filterBreed);
    final TextEditingController locationController = TextEditingController(text: _filterLocation);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Search Filters',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  if (tempAnimal != null || breedController.text.isNotEmpty || locationController.text.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          tempAnimal = null;
                          breedController.clear();
                          locationController.clear();
                        });
                      },
                      child: const Text('Clear All', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 25),
              const Text('Animal Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFilterChip('All', tempAnimal == null, isDark, onTap: () => setSheetState(() => tempAnimal = null)),
                    ...categories.map((cat) => _buildFilterChip(
                          cat,
                          tempAnimal == cat,
                          isDark,
                          onTap: () => setSheetState(() => tempAnimal = cat),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              const Text('Breed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              _buildFilterTextField(breedController, 'Search specific breed...', Icons.pets_rounded, isDark),
              const SizedBox(height: 25),
              const Text('Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              _buildFilterTextField(locationController, 'Search by city or area...', Icons.location_on_rounded, isDark),
              const SizedBox(height: 35),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _filterAnimal = tempAnimal;
                      _filterBreed = breedController.text.trim().isEmpty ? null : breedController.text.trim();
                      _filterLocation = locationController.text.trim().isEmpty ? null : locationController.text.trim();
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Apply Filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, bool isDark, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? themeGreen : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? themeGreen : (isDark ? Colors.white.withOpacity(0.06) : Colors.transparent),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTextField(TextEditingController controller, String hint, IconData icon, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100],
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 13.5),
          prefixIcon: Icon(icon, size: 18, color: themeGreen),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 84, horizontal: 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(34),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [themeGreen.withOpacity(0.12), themeGreen.withOpacity(0.02)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 64,
              color: themeGreen.withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 34),
          Text(
            'Start Your Journey',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            'Join our community to find verified\nbreeders and your next best friend.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
              fontSize: 14,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState(bool isDark) {
    final isSearching = _searchQuery.isNotEmpty;
    final hasFilters = _filterAnimal != null || _filterBreed != null || _filterLocation != null;

    String title = isSearching ? 'No results found' : 'No listings found';
    String subtitle = isSearching
        ? 'No matches for "$_searchQuery".\nTry a different search term.'
        : 'No listings match the current filters.\nTry adjusting your selection.';

    if (!isSearching && !hasFilters) {
      if (_filterType == 'Trader') {
        title = 'No Available Trader Post';
        subtitle = 'There are currently no animal posts from traders in your area.';
      } else if (_filterType == 'Breeder') {
        title = 'No Available Breeder Post';
        subtitle = 'There are currently no animal posts from breeders in your area.';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: themeGreen.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSearching ? Icons.search_off_rounded : Icons.filter_list_off_rounded,
              size: 58,
              color: themeGreen.withOpacity(0.35),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _filterType = 'All';
                _filterAnimal = null;
                _filterBreed = null;
                _filterLocation = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
              decoration: BoxDecoration(
                color: themeGreen,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: themeGreen.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: const Text(
                'Clear all filters',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Modal Sheets & Dialogs ---
  // (Keeping these in the state class for easier access to provider methods and context)

  void _showTraderDetails(BuildContext context, Breeder trader) {
    _showListingDetailsModal(context, trader);
  }

  void _showAnimalImages(BuildContext context, Breeder breeder) {
    _showListingDetailsModal(context, breeder);
  }

  Widget _buildTikTokStyleProfileCard(BuildContext context, Breeder breeder, bool isDark) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2B22) : const Color(0xFFF6F8F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: themeGreen.withValues(alpha: 0.1),
              image: breeder.imageUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(breeder.imageUrl),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    )
                  : null,
            ),
            child: breeder.imageUrl.isEmpty
                ? const Icon(Icons.person, color: themeGreen, size: 24)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  breeder.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Verified ${breeder.type.isNotEmpty ? breeder.type : "Seller"}',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (breeder.userId != currentUserId) ...[
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: () {
                      if (Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      ).isGuest) {
                        RestrictedAccessDialog.show(
                          context,
                          'report a user',
                        );
                        return;
                      }
                      if (breeder.userId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unable to report: User ID not found')),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ReportUserScreen(
                                reportedUserId:
                                    breeder.userId,
                                reportedUserName:
                                    breeder.name.isNotEmpty ? breeder.name : 'User',
                                listingId: breeder.id.isNotEmpty ? breeder.id : null,
                              ),
                        ),
                      );
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.report_gmailerrorred_rounded,
                          color: Colors.red,
                          size: 12,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Report User',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(userId: breeder.userId),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: themeGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text(
              'Visit',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTikTokDescriptionCard(bool isDark, String description) {
    if (description.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14221A) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About / Description',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF2C2C2C),
            ),
          ),
        ],
      ),
    );
  }

  void _showListingDetailsModal(BuildContext context, Breeder item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = supabase.auth.currentUser?.id;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F1A14) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // 1. PICTURE OF ANIMALS (No label, no top name, no X button)
              const SizedBox(height: 4),
              if (item.animals.isEmpty)
                Container(
                  height: 200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text('No animal photos uploaded yet.', style: TextStyle(color: Colors.grey)),
                )
              else
                SizedBox(
                  height: 280,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: item.animals.length,
                    itemBuilder: (_, i) => _buildPhotoItem(item.animals[i].imageUrl),
                  ),
                ),
              const SizedBox(height: 20),

              // 2. PRICE
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFC06C4D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFC06C4D).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Price / Fee',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC06C4D),
                      ),
                    ),
                    Text(
                      '₱${item.price}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFC06C4D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. CUSTOMER REVIEW
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSheetSection('Customer Reviews'),
                  if (item.userId != currentUserId)
                    TextButton(
                      onPressed: () {
                        if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                          RestrictedAccessDialog.show(context, 'write a review');
                          return;
                        }
                        _showAddReviewDialog(context, item);
                      },
                      child: const Text('Write a Review', style: TextStyle(color: themeGreen, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (item.reviews.isEmpty)
                const Text('No reviews yet.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
              else
                Column(
                  children: item.reviews.take(3).map((r) => _buildReviewItem(context, r, item.userId)).toList(),
                ),
              if (item.reviews.length > 3)
                TextButton(
                  onPressed: () => _showAllReviews(context, item),
                  child: const Text('View All Reviews', style: TextStyle(color: themeGreen)),
                ),
              const SizedBox(height: 20),

              // 4. POSTED BY (User + Visit button beside it)
              _buildSheetSection('Posted By'),
              const SizedBox(height: 10),
              _buildTikTokStyleProfileCard(context, item, isDark),
              const SizedBox(height: 20),

              // 5. CREDENTIALS (Only available for Trader Listing Cards)
              if (item.type == 'Trader') ...[
                _buildSheetSection('Credentials'),
                const SizedBox(height: 10),
                if (item.credentialUrls.isEmpty)
                  const Text('No credentials uploaded.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
                else
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: item.credentialUrls.length,
                      itemBuilder: (_, i) => _buildPhotoItem(item.credentialUrls[i], isCredential: true),
                    ),
                  ),
                const SizedBox(height: 20),
              ],

              // Additional Details (Breed, Description, Address, Contact)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: themeGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.type,
                      style: const TextStyle(color: themeGreen, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.breed.isNotEmpty ? item.breed : 'General Breed',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildTikTokDescriptionCard(isDark, item.description),
              const SizedBox(height: 20),

              _buildInfoCard(isDark, [
                _buildInfoRow(Icons.location_on_outlined, 'Address', item.address),
                _buildInfoRow(Icons.phone_android, 'Contact', item.contactNumber),
                _buildInfoRow(Icons.payments_outlined, 'Price / Fee', '₱${item.price}'),
                _buildInfoRow(Icons.pets, 'Breed', item.breed),
                if (item.age.isNotEmpty)
                  _buildInfoRow(Icons.cake_outlined, 'Age', item.age),
                if (item.gender.isNotEmpty)
                  _buildInfoRow(Icons.transgender, 'Gender', item.gender),
              ]),
              const SizedBox(height: 24),

              // Bottom Actions: View Map and Message
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Provider.of<NavigationProvider>(context, listen: false)
                            .setIndex(1, breeder: item);
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: themeGreen, width: 1.4),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text('View Map', style: TextStyle(color: themeGreen, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                          RestrictedAccessDialog.show(context, 'chat with breeders and traders');
                          return;
                        }
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              breederId: item.userId,
                              breederName: item.name,
                              breederAvatarUrl: item.imageUrl,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      child: const Text('Message', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetSection(String label) {
    return Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.1));
  }

  Widget _buildInfoCard(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2B22) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.13),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildPhotoItem(String url, {bool isCredential = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (url.isEmpty || !url.startsWith('http')) {
      return Container(
        width: isCredential ? 120 : 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(height: 4),
            Text(url.isEmpty ? 'Empty URL' : 'Invalid URL',
                style: const TextStyle(fontSize: 10, color: Colors.red)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
      child: Container(
        width: isCredential ? 130 : 280,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 3))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, error, __) => Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.red.withOpacity(0.08),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.red, size: 28),
                  SizedBox(height: 4),
                  Text('Load Error', style: TextStyle(fontSize: 10, color: Colors.red)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: themeGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 16, color: themeGreen),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _maskUserName(String fullName) {
    if (fullName.isEmpty) return 'Anonymous';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.map((part) {
      if (part.isEmpty) return '';
      if (part.length <= 1) return '${part[0]}*';
      final firstChar = part[0];
      int starCount = part.length > 4 ? 3 : 2;
      return '$firstChar${'*' * starCount}';
    }).join(' ');
  }

  Widget _buildReviewItem(BuildContext context, Review review, String listingOwnerId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = supabase.auth.currentUser?.id;
    final isListingOwner = currentUserId == listingOwnerId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2B22) : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundImage: review.userAvatarUrl.isNotEmpty ? NetworkImage(review.userAvatarUrl) : null,
                child: review.userAvatarUrl.isEmpty ? const Icon(Icons.person, size: 18) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maskUserName(review.userName),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: Colors.amber,
                          size: 14,
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                TimeUtils.getTimeAgo(review.createdAt),
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              if (currentUserId == review.userId) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete review',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Review'),
                        content: const Text('Are you sure you want to delete your review?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      if (!context.mounted) return;
                      try {
                        await Provider.of<BreederProvider>(context, listen: false).deleteReview(reviewId: review.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review deleted')));
                        setState(() {});
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Text(
            review.comment,
            style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[300] : Colors.grey[800], height: 1.4),
          ),
          if (review.reviewPhotos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: review.reviewPhotos.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _showFullScreenImage(context, review.reviewPhotos[index]),
                    child: Container(
                      width: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        image: DecorationImage(
                          image: NetworkImage(review.reviewPhotos[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (review.replyComment != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: themeGreen.withOpacity(0.06),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: themeGreen.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.reply_rounded, color: themeGreen, size: 14),
                      const SizedBox(width: 5),
                      const Text(
                        'Owner\'s Reply',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: themeGreen,
                        ),
                      ),
                      const Spacer(),
                      if (review.replyCreatedAt != null)
                        Text(
                          TimeUtils.getTimeAgo(review.replyCreatedAt),
                          style: TextStyle(color: Colors.grey[500], fontSize: 10),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    review.replyComment!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isListingOwner) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showReplyDialog(context, review.id),
                icon: const Icon(Icons.reply_rounded, size: 16),
                label: const Text('Reply', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: themeGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: InteractiveViewer(
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  void _showReplyDialog(BuildContext context, String reviewId) {
    final replyController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Reply to Review', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: replyController,
          maxLines: 3,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Write your reply here...',
            hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: themeGreen, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (replyController.text.trim().isEmpty) return;
              try {
                await Provider.of<BreederProvider>(context, listen: false).replyToReview(
                  reviewId: reviewId,
                  replyComment: replyController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reply posted successfully!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error posting reply: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: themeGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _showAddReviewDialog(BuildContext context, Breeder breeder) {
    double rating = 5;
    final commentController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<File> selectedImages = [];
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Write a Review', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Rate your experience:'),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: isSubmitting ? null : () => setDialogState(() => rating = index + 1.0),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  enabled: !isSubmitting,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Share your thoughts about this animal or trader...',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: themeGreen, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Add Photos (Optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      GestureDetector(
                        onTap: isSubmitting ? null : () async {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            setDialogState(() {
                              selectedImages.add(File(image.path));
                            });
                          }
                        },
                        child: Container(
                          width: 80,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200],
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined, color: themeGreen),
                        ),
                      ),
                      ...selectedImages.asMap().entries.map((entry) {
                        int index = entry.key;
                        File file = entry.value;
                        return Stack(
                          children: [
                            Container(
                              width: 80,
                              margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(11),
                                image: DecorationImage(
                                  image: FileImage(file),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            if (!isSubmitting)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () => setDialogState(() => selectedImages.removeAt(index)),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, color: Colors.white, size: 12),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                if (commentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a comment')),
                  );
                  return;
                }

                setDialogState(() { isSubmitting = true; });

                try {
                  await Provider.of<BreederProvider>(context, listen: false).addReview(
                    listingId: breeder.id,
                    rating: rating,
                    comment: commentController.text.trim(),
                    photoPaths: selectedImages.map((e) => e.path).toList(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    _showReviewSuccessDialog(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    setDialogState(() { isSubmitting = false; });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adding review: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
              child: isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewSuccessDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: themeGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  color: themeGreen,
                  size: 64,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Review Posted!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 13),
              Text(
                'Your review has been successfully added. Thank you for sharing your experience!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 34),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Great!',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllReviews(BuildContext context, Breeder breeder) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F1A14) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(3)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('All Reviews (${breeder.reviews.length})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: breeder.reviews.length,
                  itemBuilder: (context, index) => _buildReviewItem(context, breeder.reviews[index], breeder.userId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
