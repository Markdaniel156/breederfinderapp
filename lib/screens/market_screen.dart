import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/breeder_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/breeder.dart';
import '../models/animal.dart';
import '../models/review.dart';
import '../services/time_utils.dart';
import 'report_user_screen.dart';
import 'trader_postings_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import '../widgets/restricted_access_dialog.dart';
import '../widgets/home/category_tile.dart';
import '../widgets/home/listing_item.dart';
import '../providers/auth_provider.dart';
import '../utils/system_ui_utils.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  Position? _currentPosition;
  String _selectedCategory = 'All';
  String _filterType = 'All'; // 'All', 'Breeder', 'Trader'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showAllCategories = false;
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _checkConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (mounted) {
        setState(() {
          _isOffline =
              results.contains(ConnectivityResult.none) || results.isEmpty;
        });
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline =
            results.contains(ConnectivityResult.none) || results.isEmpty;
      });
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = position;
    });
  }

  @override
  Widget build(BuildContext context) {
    final breederProvider = Provider.of<BreederProvider>(context);
    final breeders = breederProvider.breeders;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);
    final userRole = authProvider.role;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF121212) : Colors.white,
        ),
        child: RefreshIndicator(
          color: const Color(0xFF2D6A4F),
          onRefresh: () => breederProvider.fetchBreeders(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            cacheExtent: 1000.0,
            slivers: [
              SliverAppBar(
                floating: false,
                pinned: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: theme.scaffoldBackgroundColor.withValues(
                  alpha: 0.8,
                ),
                surfaceTintColor: Colors.transparent,
                title: const Text(
                  'AniMarket',
                  style: TextStyle(
                    color: Color(0xFF2D6A4F),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                actions: [
                  if (userRole?.toLowerCase().contains('trader') ?? false)
                    Container(
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.add_rounded,
                          color: Color(0xFF2D6A4F),
                          size: 24,
                        ),
                        onPressed: () {
                          if (Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          ).isGuest) {
                            RestrictedAccessDialog.show(
                              context,
                              'post animals for sale',
                            );
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const TraderPostingsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              if (_isOffline) SliverToBoxAdapter(child: _buildOfflineBanner()),
              SliverToBoxAdapter(child: _buildSearchBar(isDark)),
              SliverToBoxAdapter(child: _buildCategories(breeders, isDark)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Layer 1: Explore Animals Title
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6A4F),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Explore Animals',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Layer 2: Filter Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filter by Seller',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          _buildTypeToggle(isDark),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _buildAnimalGrid(breeders, isDark),
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value.trim();
            });
          },
          decoration: InputDecoration(
            hintText: 'Search for animals, breeds...',
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[600] : Colors.grey[500],
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF2D6A4F),
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle(bool isDark) {
    final filters = ['All', 'Breeder', 'Trader'];
    const themeGreen = Color(0xFF2D6A4F);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: filters.map((label) {
          final isSelected = _filterType == label;
          return GestureDetector(
            onTap: () => setState(() {
              _filterType = label;
              _selectedCategory = 'All';
            }),
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

  Widget _buildCategories(List<Breeder> breeders, bool isDark) {
    final filteredListings = breeders
        .where(
          (breeder) =>
              (_filterType == 'All' || breeder.type == _filterType) &&
              breeder.animals.isNotEmpty,
        )
        .toList();
    final categoryListings = <String, List<Breeder>>{};
    for (final listing in filteredListings) {
      final category = listing.category.trim();
      if (category.isNotEmpty) {
        categoryListings.putIfAbsent(category, () => []).add(listing);
      }
    }
    final categories = categoryListings.keys.toList()
      ..sort((a, b) {
        final countDifference =
            categoryListings[b]!.length - categoryListings[a]!.length;
        return countDifference != 0 ? countDifference : a.compareTo(b);
      });
    final visibleCategories = _showAllCategories
        ? categories
        : categories.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Explore Categories',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              if (categories.length > 3)
                TextButton(
                  onPressed: () =>
                      setState(() => _showAllCategories = !_showAllCategories),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2D6A4F),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _showAllCategories ? 'Show Less' : 'See All',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleCategories.length + 1,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.12,
            ),
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final category = isAll ? 'All' : visibleCategories[index - 1];
              final isSelected = _selectedCategory == category;
              final listings = isAll
                  ? filteredListings
                  : (categoryListings[category] ?? []);
              return CategoryTile(
                category: category,
                items: listings,
                isDark: isDark,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedCategory = category),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnimalGrid(List<Breeder> breeders, bool isDark) {
    final breederProvider = Provider.of<BreederProvider>(context);

    final List<Breeder> filteredListings = breeders.where((breeder) {
      final matchesType = _filterType == 'All' || breeder.type == _filterType;
      final matchesCategory =
          _selectedCategory == 'All' || breeder.category == _selectedCategory;

      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatches = breeder.name.toLowerCase().contains(q);
        final breedMatches = breeder.breed.toLowerCase().contains(q);
        final categoryMatches = breeder.category.toLowerCase().contains(q);
        final animalMatches = breeder.animals.any((a) =>
            a.name.toLowerCase().contains(q) ||
            a.breed.toLowerCase().contains(q));
        matchesSearch =
            nameMatches || breedMatches || categoryMatches || animalMatches;
      }

      return matchesType &&
          matchesCategory &&
          matchesSearch &&
          breeder.animals.isNotEmpty;
    }).toList();

    if (filteredListings.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 80,
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'No animals found',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Try selecting a different category or filter\nor check back later for new listings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.62,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = filteredListings[index];
            final currentUser = Supabase.instance.client.auth.currentUser;
            final isOwnListing = currentUser?.id == item.userId;
            final isFavorited = breederProvider.isFavorite(item.id);

            final firstAnimal =
                item.animals.isNotEmpty ? item.animals[0] : null;

              return ListingItem(
                item: item,
                isDark: isDark,
                isFavorited: isFavorited,
                isOwnListing: isOwnListing,
                userPosition: _currentPosition,
                specificAnimal: firstAnimal,
                onTap: () {
                  if (firstAnimal != null) {
                    _showAnimalDetails(context, item, firstAnimal);
                  } else {
                    _showAnimalDetails(
                      context,
                      item,
                      Animal(
                        id: '',
                        name: item.name,
                        breed: item.breed,
                        price: double.tryParse(item.price) ?? 0.0,
                        imageUrl: item.imageUrl,
                        description: item.description,
                      ),
                    );
                  }
                },
                onFavoriteTap: () {
                  if (Provider.of<AuthProvider>(context, listen: false).isGuest) {
                    RestrictedAccessDialog.show(context, 'add to favorites');
                    return;
                  }
                  breederProvider.toggleFavorite(item.id);
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
                  RestrictedAccessDialog.show(
                    context,
                    'chat with breeders and traders',
                  );
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
          childCount: filteredListings.length,
        ),
      ),
    );
  }

  void _showAnimalDetails(
    BuildContext context,
    Breeder breeder,
    Animal animal,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const themeGreen = Color(0xFF2D6A4F);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

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
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Animal Details',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Animal Photos Section
                    _buildSheetLabel('Animal Photos'),
                    const SizedBox(height: 12),
                    if (breeder.animals.isEmpty)
                      const Text('No photos available.')
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: breeder.animals.length,
                          itemBuilder: (_, i) => _buildDetailPhotoItem(
                            context,
                            breeder.animals[i].imageUrl,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Reviews Section moved here
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _buildSheetLabel('Reviews'),
                            if (breeder.reviews.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
                                size: 18,
                              ),
                              Text(
                                ' ${breeder.averageRating.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                ' (${breeder.reviews.length})',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (breeder.userId != currentUserId)
                          TextButton(
                            onPressed: () {
                              if (Provider.of<AuthProvider>(
                                context,
                                listen: false,
                              ).isGuest) {
                                RestrictedAccessDialog.show(
                                  context,
                                  'write a review',
                                );
                                return;
                              }
                              _showAddReviewDialog(context, breeder);
                            },
                            child: const Text(
                              'Write a Review',
                              style: TextStyle(
                                color: themeGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (breeder.reviews.isEmpty)
                      Center(
                        child: Text(
                          'No reviews yet. Be the first to review!',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      Column(
                        children: breeder.reviews
                            .take(3)
                            .map(
                              (review) => _buildReviewItem(
                                context,
                                review,
                                breeder.userId,
                              ),
                            )
                            .toList(),
                      ),
                    if (breeder.reviews.length > 3)
                      TextButton(
                        onPressed: () => _showAllReviews(context, breeder),
                        child: const Text(
                          'View All Reviews',
                          style: TextStyle(color: themeGreen),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Basic Information
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                animal.name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                breeder.gender.isNotEmpty
                                    ? '${animal.breed} • ${breeder.gender}'
                                    : animal.breed,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '₱${animal.price.toInt()}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: themeGreen,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Credentials Section (Only for Trader listings)
                    if (breeder.type == 'Trader') ...[
                      _buildSheetLabel('Trader Credentials'),
                      const SizedBox(height: 12),
                      if (breeder.credentialUrls.isEmpty)
                        const Text('No credentials uploaded.')
                      else
                        SizedBox(
                          height: 150,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: breeder.credentialUrls.length,
                            itemBuilder: (_, i) => _buildDetailPhotoItem(
                              context,
                              breeder.credentialUrls[i],
                              isCredential: true,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],

                    _buildSheetLabel(breeder.type == 'Trader' ? 'Trader Information' : 'Breeder Information'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[900] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 25,
                                backgroundImage: breeder.imageUrl.isNotEmpty
                                    ? NetworkImage(breeder.imageUrl)
                                    : null,
                                child: breeder.imageUrl.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      breeder.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
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
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow(
                            Icons.location_on_rounded,
                            'Address',
                            breeder.address,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.phone_rounded,
                            'Contact',
                            breeder.contactNumber,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Provider.of<NavigationProvider>(
                                context,
                                listen: false,
                              ).setIndex(1, breeder: breeder);
                            },
                            icon: const Icon(Icons.map_rounded),
                            label: const Text('View on Map'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: themeGreen,
                              side: const BorderSide(color: themeGreen),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),
                        if (breeder.userId != currentUserId) ...[
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (Provider.of<AuthProvider>(
                                  context,
                                  listen: false,
                                ).isGuest) {
                                  RestrictedAccessDialog.show(
                                    context,
                                    'chat with breeders and traders',
                                  );
                                  return;
                                }
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                      breederId: breeder.userId,
                                      breederName: breeder.name,
                                      breederAvatarUrl: breeder.imageUrl,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_rounded),
                              label: const Text('Contact Now'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themeGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetLabel(String label) {
    return Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDetailPhotoItem(
    BuildContext context,
    String url, {
    bool isCredential = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: Container(
        width: isCredential ? 150 : 200,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(
            url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Center(child: Icon(Icons.pets, color: Colors.grey)),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF2D6A4F)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _maskUserName(String fullName) {
    if (fullName.isEmpty) return 'Anonymous';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts
        .map((part) {
          if (part.isEmpty) return '';
          if (part.length <= 1) return '${part[0]}*';
          final firstChar = part[0];
          int starCount = part.length > 4 ? 3 : 2;
          return '$firstChar${'*' * starCount}';
        })
        .join(' ');
  }

  Widget _buildReviewItem(
    BuildContext context,
    Review review,
    String listingOwnerId,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isListingOwner = currentUserId == listingOwnerId;
    const themeGreen = Color(0xFF2D6A4F);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundImage: review.userAvatarUrl.isNotEmpty
                    ? NetworkImage(review.userAvatarUrl)
                    : null,
                child: review.userAvatarUrl.isEmpty
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maskUserName(review.userName),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < review.rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
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
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete review',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Review'),
                        content: const Text(
                          'Are you sure you want to delete your review?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      if (!context.mounted) return;
                      try {
                        await Provider.of<BreederProvider>(
                          context,
                          listen: false,
                        ).deleteReview(reviewId: review.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Review deleted')),
                        );
                        setState(() {});
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.comment,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
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
                    onTap: () => _showFullScreenImage(
                      context,
                      review.reviewPhotos[index],
                    ),
                    child: Container(
                      width: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeGreen.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: themeGreen.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.reply_rounded,
                        color: themeGreen,
                        size: 14,
                      ),
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
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
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
            const SizedBox(height: 8),
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
    const themeGreen = Color(0xFF2D6A4F);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Reply to Review',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: replyController,
          maxLines: 3,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Write your reply here...',
            hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
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
                await Provider.of<BreederProvider>(
                  context,
                  listen: false,
                ).replyToReview(
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
    const themeGreen = Color(0xFF2D6A4F);
    List<File> selectedImages = [];
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Write a Review',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
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
                          index < rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () => setDialogState(() => rating = index + 1.0),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    hintText:
                        'Share your thoughts about this animal or trader...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
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
                        onTap: isSubmitting
                            ? null
                            : () async {
                                final picker = ImagePicker();
                                final XFile? image = await picker.pickImage(
                                  source: ImageSource.gallery,
                                );
                                if (image != null) {
                                  setDialogState(() {
                                    selectedImages.add(File(image.path));
                                  });
                                }
                              },
                        child: Container(
                          width: 80,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.add_a_photo_outlined,
                            color: themeGreen,
                          ),
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
                                borderRadius: BorderRadius.circular(10),
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
                                  onTap: () => setDialogState(
                                    () => selectedImages.removeAt(index),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 12,
                                    ),
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
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (commentController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a comment'),
                          ),
                        );
                        return;
                      }

                      setDialogState(() {
                        isSubmitting = true;
                      });

                      try {
                        await Provider.of<BreederProvider>(
                          context,
                          listen: false,
                        ).addReview(
                          listingId: breeder.id,
                          rating: rating,
                          comment: commentController.text.trim(),
                          photoPaths: selectedImages
                              .map((e) => e.path)
                              .toList(),
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showReviewSuccessDialog(context);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setDialogState(() {
                            isSubmitting = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Error adding review: ${e.toString()}',
                              ),
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewSuccessDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const themeGreen = Color(0xFF2D6A4F);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: themeGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  color: themeGreen,
                  size: 64,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Review Posted!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Your review has been successfully added. Thank you for sharing your experience!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Great!',
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
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All Reviews (${breeder.reviews.length})',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: breeder.reviews.length,
                  itemBuilder: (context, index) => _buildReviewItem(
                    context,
                    breeder.reviews[index],
                    breeder.userId,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 16),
          SizedBox(width: 8),
          Text(
            'No Internet Connection',
            style: TextStyle(
              color: Color(0xFF991B1B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
