import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/breeder.dart';
import '../../models/animal.dart';
import '../../services/time_utils.dart';

class ListingItem extends StatefulWidget {
  final Breeder item;
  final bool isDark;
  final bool isFavorited;
  final bool isOwnListing;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onChatTap;
  final VoidCallback onMapTap;
  final VoidCallback onProfileTap;
  final VoidCallback? onReportTap;
  final Animal? specificAnimal;
  final Position? userPosition;

  const ListingItem({
    super.key,
    required this.item,
    required this.isDark,
    required this.isFavorited,
    required this.isOwnListing,
    required this.onTap,
    required this.onFavoriteTap,
    required this.onChatTap,
    required this.onMapTap,
    required this.onProfileTap,
    this.onReportTap,
    this.specificAnimal,
    this.userPosition,
  });

  @override
  State<ListingItem> createState() => _ListingItemState();
}

class _ListingItemState extends State<ListingItem> {
  late PageController _pageController;
  int _currentPage = 0;

  static const themeGreen = Color(0xFF2D6A4F);
  static const designOrange = Color(0xFFC06C4D);
  static const designGrey = Color(0xFF757575);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animal? animal = widget.specificAnimal;
    final List<String> imageUrls = widget.item.animals.isNotEmpty
        ? widget.item.animals.map((a) => a.imageUrl).toList()
        : [];
    
    if (imageUrls.isEmpty && widget.item.imageUrl.isNotEmpty) {
      imageUrls.add(widget.item.imageUrl);
    }

    String displayPrice = "";
    if (animal != null) {
      displayPrice = "₱${animal.price.toStringAsFixed(0)}";
    } else if (widget.item.animals.isNotEmpty) {
      final prices = widget.item.animals.map((a) => a.price).toList();
      final minPrice = prices.reduce((a, b) => a < b ? a : b);
      final maxPrice = prices.reduce((a, b) => a > b ? a : b);
      if (minPrice == maxPrice) {
        displayPrice = "₱${minPrice.toStringAsFixed(0)}";
      } else {
        displayPrice = "₱${minPrice.toStringAsFixed(0)} - ₱${maxPrice.toStringAsFixed(0)}";
      }
    } else {
      displayPrice = "₱${widget.item.price}";
    }

    final animalName = animal != null ? animal.name : widget.item.name;
    final timeAgo = TimeUtils.getTimeAgo(widget.item.createdAt);

    String distanceText = '';
    if (widget.userPosition != null) {
      double distanceInMeters = Geolocator.distanceBetween(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
        widget.item.location.latitude,
        widget.item.location.longitude,
      );
      double distanceInKm = distanceInMeters / 1000;
      distanceText = '${distanceInKm.toStringAsFixed(1)} km';
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1A2B22) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: widget.isDark ? 0.2 : 0.05),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section (Carousel)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: imageUrls.isNotEmpty
                          ? Stack(
                              children: [
                                PageView.builder(
                                  controller: _pageController,
                                  itemCount: imageUrls.length,
                                  onPageChanged: (index) {
                                    setState(() => _currentPage = index);
                                  },
                                  itemBuilder: (context, index) {
                                    return Image.network(
                                      imageUrls[index],
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: widget.isDark ? Colors.black26 : Colors.grey[100],
                                        child: const Icon(Icons.pets, color: Colors.grey, size: 36),
                                      ),
                                    );
                                  },
                                ),
                              // Page Indicators (Dots)
                              if (imageUrls.length > 1)
                                Positioned(
                                  bottom: 8,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(imageUrls.length, (index) {
                                      return AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        height: 5,
                                        width: _currentPage == index ? 14 : 5,
                                        decoration: BoxDecoration(
                                          color: _currentPage == index
                                              ? Colors.white
                                              : Colors.white.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(2.5),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                            ],
                          )
                        : Container(
                            color: widget.isDark ? Colors.black26 : Colors.grey[100],
                            child: const Icon(Icons.pets, color: Colors.grey, size: 36),
                          ),
                  ),
                  // Gender Badge
                  if (widget.item.gender.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.item.gender.toLowerCase() == 'male'
                                  ? Icons.male_rounded
                                  : widget.item.gender.toLowerCase() == 'female'
                                      ? Icons.female_rounded
                                      : Icons.transgender_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              widget.item.gender,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Favorite Button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: widget.onFavoriteTap,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isFavorited ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                          color: widget.isFavorited ? Colors.red : Colors.grey[600],
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info Section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title & Report Icon (Placed cleanly inside card body)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                animalName,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                  color: widget.isDark ? Colors.white : const Color(0xFF1A1A2E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!widget.isOwnListing && widget.onReportTap != null)
                              GestureDetector(
                                onTap: widget.onReportTap,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.report_gmailerrorred_rounded,
                                    color: Colors.red.shade400,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Type & Time Ago (Facebook Style)
                        Row(
                          children: [
                            Text(
                              widget.item.type,
                              style: TextStyle(
                                color: widget.item.type == 'Trader' ? designOrange : themeGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (timeAgo.isNotEmpty) ...[
                              const Text(' • ', style: TextStyle(color: designGrey, fontSize: 11)),
                              Flexible(
                                child: Text(
                                  timeAgo,
                                  style: const TextStyle(
                                    color: designGrey,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Breed, Gender & Age
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.item.breed.isNotEmpty ? widget.item.breed : 'Unknown Breed',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: designGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.item.gender.isNotEmpty) ...[
                              const Text(' • ', style: TextStyle(color: designGrey, fontSize: 11)),
                              Text(
                                widget.item.gender,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: designGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (widget.item.age.isNotEmpty) ...[
                              const Text(' • ', style: TextStyle(color: designGrey, fontSize: 11)),
                              Text(
                                widget.item.age,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: designGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Rating & Distance
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: designOrange, size: 14),
                            const SizedBox(width: 3),
                            Text(
                              widget.item.averageRating.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: widget.isDark ? Colors.white : const Color(0xFF1A1A2E),
                              ),
                            ),
                            if (distanceText.isNotEmpty) ...[
                              const Spacer(),
                              Text(
                                distanceText,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: designGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Location & Price
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 13, color: designGrey),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      widget.item.address,
                                      style: const TextStyle(
                                        color: designGrey,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              displayPrice,
                              style: const TextStyle(
                                color: designOrange,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
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
  );
  }
}
