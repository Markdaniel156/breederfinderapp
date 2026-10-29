import 'package:flutter/material.dart';

class HomeHeader extends StatelessWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback onMapTap;
  final VoidCallback onFeedbackTap;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;
  final int unreadCount;

  static const themeGreen = Color(0xFF2D6A4F);
  static const themeGold = Color(0xFFFFB703);

  const HomeHeader({
    super.key,
    required this.userData,
    required this.onMapTap,
    required this.onFeedbackTap,
    required this.onNotificationTap,
    required this.onProfileTap,
    required this.unreadCount,
  });

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fullName = userData?['full_name'] ?? 'User';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                GestureDetector(
                  onTap: onProfileTap,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: themeGreen.withOpacity(0.4), width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: themeGreen.withOpacity(0.1),
                      backgroundImage: userData?['avatar_url'] != null
                          ? NetworkImage(userData!['avatar_url'])
                          : null,
                      child: userData?['avatar_url'] == null
                          ? const Icon(Icons.person_rounded, color: themeGreen, size: 22)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_timeGreeting()},',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$fullName 👋',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              GestureDetector(
                onTap: onFeedbackTap,
                child: Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: themeGreen.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: themeGreen.withOpacity(0.2)),
                  ),
                  child: const Center(
                    child: Icon(Icons.rate_review_rounded, color: themeGreen, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Stack(
                children: [
                  _buildHeaderAction(
                    icon: Icons.notifications_none_rounded,
                    onTap: onNotificationTap,
                    isDark: isDark,
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: unreadCount > 0
                          ? Container(
                              key: const ValueKey('badge_active'),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? const Color(0xFF0F1A14) : const Color(0xFFF6F8F6),
                                  width: 1.5,
                                ),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 15,
                                minHeight: 15,
                              ),
                              child: Center(
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('badge_empty')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction({required IconData icon, required VoidCallback onTap, required bool isDark}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.1),
          ),
        ),
        child: Icon(
          icon,
          color: isDark ? Colors.white70 : const Color(0xFF1A1A2E),
          size: 19,
        ),
      ),
    );
  }
}
