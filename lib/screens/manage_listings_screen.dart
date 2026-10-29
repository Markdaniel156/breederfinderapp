import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/breeder_provider.dart';
import '../models/breeder.dart';
import '../services/time_utils.dart';
import 'breeder_postings_screen.dart';
import 'trader_postings_screen.dart';
import 'subscription_screen.dart';
import '../widgets/limit_reached_card.dart';
import '../widgets/solo_plan_transparency_card.dart';
import '../utils/system_ui_utils.dart';

class ManageListingsScreen extends StatefulWidget {
  const ManageListingsScreen({super.key});

  @override
  State<ManageListingsScreen> createState() => _ManageListingsScreenState();
}

class _ManageListingsScreenState extends State<ManageListingsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isLimitReached = false;
  List<Breeder> _myListings = [];

  @override
  void initState() {
    super.initState();
    _fetchMyListings();
  }

  Future<void> _fetchMyListings() async {
    setState(() => _isLoading = true);
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final provider = Provider.of<BreederProvider>(context, listen: false);
    // Refresh to get latest
    await provider.fetchBreeders(silent: true);
    
    if (!mounted) return;
    
    setState(() {
      _myListings = provider.breeders.where((b) => b.userId == userId).toList();
      _isLoading = false;
    });

    // Check limit
    final hasLimit = await provider.hasReachedListingLimit(userId);
    if (mounted) {
      setState(() => _isLimitReached = hasLimit);
    }
  }

  Future<void> _deleteListing(Breeder listing) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Listing'),
        content: Text('Are you sure you want to delete your ${listing.type} post?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        final provider = Provider.of<BreederProvider>(context, listen: false);
        await provider.deleteListing(listing.id, listing.type);
        
        if (!mounted) return;
        
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 30),
                  SizedBox(width: 10),
                  Text('Success', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text('Your ${listing.type} posting and associated images have been removed successfully.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK', style: TextStyle(color: Color(0xFF2D6A4F), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        _fetchMyListings();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showEditModal(Breeder listing) {
    const themeGreen = Color(0xFF2D6A4F);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Edit Your Listing',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'To keep things simple, editing your ${listing.category} listing will take you back to the registration form where all your current details are already pre-filled for you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close modal
                  if (listing.type == 'Breeder') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => BreederPostingsScreen(initialData: listing)),
                    ).then((_) => _fetchMyListings());
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => TraderPostingsScreen(initialData: listing)),
                    ).then((_) => _fetchMyListings());
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('Proceed to Edit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeGreen = Color(0xFF2D6A4F);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiUtils.getOverlayStyle(
        isDark: isDark,
        navBarColor: theme.scaffoldBackgroundColor,
      ),
      child: Scaffold(
        body: RefreshIndicator(
          color: themeGreen,
          onRefresh: _fetchMyListings,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                floating: true,
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: themeGreen),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text(
                  'My Listings',
                  style: TextStyle(
                    color: themeGreen,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                centerTitle: false,
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: themeGreen)),
                )
              else ...[
                const SliverToBoxAdapter(
                  child: SoloPlanTransparencyCard(
                    margin: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  ),
                ),
                if (_isLimitReached)
                  SliverToBoxAdapter(
                    child: LimitReachedCard(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      onUpgrade: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
                        );
                        if (result == true) {
                          await _fetchMyListings();
                        }
                      },
                    ),
                  ),
                if (_myListings.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final listing = _myListings[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      image: listing.animals.isNotEmpty
                                          ? DecorationImage(
                                              image: NetworkImage(listing.animals.first.imageUrl),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                      color: Colors.grey[200],
                                    ),
                                    child: listing.animals.isEmpty ? const Icon(Icons.pets) : null,
                                  ),
                                  title: Text(listing.category, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${listing.type}${listing.breed.isNotEmpty ? " • ${listing.breed}" : ""}${listing.gender.isNotEmpty ? " • ${listing.gender}" : ""} • ₱${listing.price}'),
                                      if (listing.createdAt != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time_rounded, size: 12, color: Colors.grey[500]),
                                            const SizedBox(width: 4),
                                            Text(
                                              TimeUtils.getTimeAgo(listing.createdAt),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[500],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: themeGreen.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      listing.type.toUpperCase(),
                                      style: const TextStyle(color: themeGreen, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _showEditModal(listing),
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        label: const Text('Edit'),
                                        style: TextButton.styleFrom(foregroundColor: themeGreen),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () => _deleteListing(listing),
                                        icon: const Icon(Icons.delete_outline, size: 18),
                                        label: const Text('Delete'),
                                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        childCount: _myListings.length,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No active listings found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Register as a breeder or trader to see your posts here.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
