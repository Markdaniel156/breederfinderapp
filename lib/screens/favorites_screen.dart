import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/breeder_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/breeder.dart';
import 'chat_screen.dart';
import 'report_user_screen.dart';
import '../services/time_utils.dart';
import '../providers/navigation_provider.dart';
import 'profile_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final breederProvider = Provider.of<BreederProvider>(context);
    final favorites = breederProvider.favoriteBreeders;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const themeGreen = Color(0xFF2D6A4F);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('My Favorites', style: TextStyle(fontWeight: FontWeight.bold, color: themeGreen)),
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: themeGreen),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: favorites.isEmpty
          ? _buildEmptyState(isDark, themeGreen)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                return _buildFavoriteItem(context, favorites[index], isDark, themeGreen);
              },
            ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color themeGreen) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_outline_rounded, size: 80, color: themeGreen.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text(
            'No Favorites Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Start hearting listings to see them here!',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteItem(BuildContext context, Breeder item, bool isDark, Color themeGreen) {
    final accentColor = item.type == 'Trader' ? const Color(0xFFE67E22) : themeGreen;
    
    return GestureDetector(
      onTap: () => _showPostDetails(context, item, isDark, themeGreen),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image
                SizedBox(
                  width: 120,
                  child: item.animals.isNotEmpty
                      ? Image.network(
                          item.animals[0].imageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: double.infinity,
                          height: double.infinity,
                          color: Colors.grey[300],
                          child: const Icon(Icons.pets, color: Colors.white, size: 40),
                        ),
                ),
                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.type.toUpperCase(),
                                style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Provider.of<BreederProvider>(context, listen: false).toggleFavorite(item.id),
                              child: const Icon(Icons.favorite_rounded, color: Colors.red, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item.gender.isNotEmpty ? '${item.breed} • ${item.gender}' : item.breed,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                        if (item.createdAt != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 12, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                TimeUtils.getTimeAgo(item.createdAt),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: themeGreen),
                              onPressed: () {
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
                            ),
                            IconButton(
                              icon: const Icon(Icons.map_outlined, size: 20, color: Colors.blueGrey),
                              onPressed: () {
                                Provider.of<NavigationProvider>(context, listen: false).setIndex(1, breeder: item);
                                Navigator.pop(context); // Go back to profile
                                Navigator.pop(context); // Go back to home/map
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPostDetails(BuildContext context, Breeder item, bool isDark, Color themeGreen) {
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
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                        Row(
                          children: [
                            Text(item.type, style: TextStyle(color: themeGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 8),
                            if (item.userId != Supabase.instance.client.auth.currentUser?.id)
                              GestureDetector(
                                onTap: () {
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
                                    Icon(Icons.report_gmailerrorred_rounded, color: Colors.red, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Report',
                                      style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Listing Owner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: item.userId),
                    ),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: themeGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: themeGreen.withValues(alpha: 0.2)),
                      ),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: themeGreen.withValues(alpha: 0.1),
                        backgroundImage: item.imageUrl.isNotEmpty ? NetworkImage(item.imageUrl) : null,
                        child: item.imageUrl.isEmpty ? Icon(Icons.person, size: 28, color: themeGreen) : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              const Text('About', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text(item.description.isNotEmpty ? item.description : 'No description provided.', 
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.5)),
              const SizedBox(height: 25),
              const Text('Animal Photos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              if (item.animals.isEmpty)
                const Center(child: Text('No photos available.'))
              else
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: item.animals.length,
                    itemBuilder: (_, i) => _buildPhotoItem(context, item.animals[i].imageUrl, isDark),
                  ),
                ),
              const SizedBox(height: 25),
              const Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.pets, 'Breed', item.breed, isDark),
              if (item.gender.isNotEmpty)
                _buildDetailRow(Icons.transgender, 'Gender', item.gender, isDark),
              if (item.age.isNotEmpty)
                _buildDetailRow(Icons.cake_outlined, 'Age', item.age, isDark),
              _buildDetailRow(Icons.category, 'Category', item.category, isDark),
              _buildDetailRow(Icons.location_on, 'Location', item.address, isDark),
              _buildDetailRow(Icons.phone, 'Contact', item.contactNumber, isDark),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                          breederId: item.userId,
                          breederName: item.name,
                          breederAvatarUrl: item.imageUrl,
                        )));
                      },
                      icon: const Icon(Icons.chat_bubble_rounded),
                      label: const Text('Contact Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
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

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value.isNotEmpty ? value : 'N/A', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),
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
              Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
            ],
          ),
        ),
      ),
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        ),
      ),
    );
  }
}
