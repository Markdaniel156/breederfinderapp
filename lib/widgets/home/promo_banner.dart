import 'dart:async';
import 'package:flutter/material.dart';

class PromoBanner extends StatefulWidget {
  final int breedersCount;
  final int tradersCount;
  final int promoIndex;
  final ValueChanged<int> onPageChanged;

  static const themeGreen = Color(0xFF2D6A4F);
  static const themeGreenLight = Color(0xFF40916C);
  static const themeGreenDark = Color(0xFF1B4332);
  static const themeGold = Color(0xFFFFB703);

  const PromoBanner({
    super.key,
    required this.breedersCount,
    required this.tradersCount,
    required this.promoIndex,
    required this.onPageChanged,
  });

  @override
  State<PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends State<PromoBanner> {
  late PageController _pageController;
  Timer? _timer;
  final int _slideCount = 3;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.promoIndex);
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients) {
        int nextPage = widget.promoIndex + 1;
        if (nextPage >= _slideCount) {
          nextPage = 0;
          _pageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOutCubic,
          );
        } else {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = [
      {
        'title': 'Every Pet Deserves\nA Loving Home',
        'subtitle': '${widget.breedersCount} verified breeders ready to help',
        'icon': Icons.favorite_rounded,
        'image': 'assets/logo/loving_home.jpg',
      },
      {
        'title': 'Trusted Traders,\nHonest Prices',
        'subtitle': '${widget.tradersCount} active traders near you',
        'icon': Icons.verified_rounded,
        'image': 'assets/logo/trusted_traders.jpg',
      },
      {
        'title': 'Find Your Next\nBest Friend Today',
        'subtitle': 'Browse, chat, and meet in person',
        'icon': Icons.pets_rounded,
        'image': 'assets/logo/animal_friends.jpg',
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: SizedBox(
        height: 160,
        child: PageView.builder(
          controller: _pageController,
          itemCount: slides.length,
          onPageChanged: (index) {
            widget.onPageChanged(index);
            // Optional: Restart timer on manual swipe to avoid immediate auto-scroll
            _startAutoScroll();
          },
          itemBuilder: (context, index) {
            final slide = slides[index];
            return Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    PromoBanner.themeGreenDark,
                    PromoBanner.themeGreen,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    // Decorative Background Circles
                    Positioned(
                      top: -20,
                      right: -20,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.04),
                        ),
                      ),
                    ),
                    
                    // Main Content Row
                    Row(
                      children: [
                        // Left side: Content
                        Expanded(
                          flex: 50,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: PromoBanner.themeGold,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'BREEDER FINDER',
                                    style: TextStyle(
                                      color: PromoBanner.themeGreenDark,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  slide['title'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  slide['subtitle'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Right side: Image
                        Expanded(
                          flex: 50,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.white.withOpacity(0.1),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Image.asset(
                                    slide['image'] as String,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.white.withOpacity(0.1),
                                      child: Icon(
                                        slide['icon'] as IconData,
                                        size: 40,
                                        color: Colors.white.withOpacity(0.2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Page Indicators
                    Positioned(
                      bottom: 10,
                      left: 20,
                      child: Row(
                        children: List.generate(slides.length, (i) {
                          final active = i == widget.promoIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.only(right: 4),
                            width: active ? 12 : 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(active ? 0.9 : 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
