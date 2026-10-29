import 'package:flutter/material.dart';
import '../../models/breeder.dart';

class CategoryTile extends StatelessWidget {
  final String category;
  final List<Breeder> items;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;

  static const themeGreen = Color(0xFF2D6A4F);

  const CategoryTile({
    super.key,
    required this.category,
    required this.items,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color catColor = _getCategoryColor(category);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2B22) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
                ? themeGreen 
                : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.12)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(isDark ? 0.2 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _getCategoryEmoji(category),
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: themeGreen,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isDark ? const Color(0xFF1A2B22) : Colors.white,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              category,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? themeGreen
                    : (isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF1A1A2E)),
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _getCategoryEmoji(String category) {
    final name = category.toLowerCase();
    if (name.contains('dog')) return '🐶';
    if (name.contains('cat')) return '🐱';
    if (name.contains('pig')) return '🐷';
    if (name.contains('goat')) return '🐐';
    if (name.contains('cow')) return '🐮';
    if (name.contains('horse')) return '🐴';
    if (name.contains('rabbit')) return '🐰';
    if (name.contains('chicken')) return '🐔';
    if (name.contains('fish')) return '🐠';
    if (name.contains('sheep')) return '🐑';
    if (name.contains('carabao')) return '🐃';
    return '🐾';
  }

  Color _getCategoryColor(String category) {
    final name = category.toLowerCase();
    if (name.contains('dog')) return Colors.orange;
    if (name.contains('cat')) return Colors.blue;
    if (name.contains('pig')) return Colors.pinkAccent;
    if (name.contains('goat')) return Colors.brown;
    if (name.contains('cow')) return Colors.blueGrey;
    if (name.contains('horse')) return Colors.deepOrange;
    if (name.contains('rabbit')) return Colors.purple;
    if (name.contains('chicken')) return Colors.redAccent;
    if (name.contains('fish')) return Colors.cyan;
    return themeGreen;
  }
}
