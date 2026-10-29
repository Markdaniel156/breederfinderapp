import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../models/notification.dart';
import '../services/time_utils.dart';
import 'profile_screen.dart';
import '../utils/system_ui_utils.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  static const _themeGreen = Color(0xFF2D6A4F);
  bool _markedAsRead = false;
  Timer? _resetTimer;
  final Map<String, String> _optimisticStatuses = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<NotificationProvider>().fetchNotifications();
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notificationProvider = context.watch<NotificationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F1A14) : const Color(0xFFF5F7F5);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110.0,
            floating: false,
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 2,
            surfaceTintColor: bgColor,
            backgroundColor: bgColor,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : Colors.black87,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
              title: Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              centerTitle: false,
            ),
            systemOverlayStyle: SystemUiUtils.getOverlayStyle(
              isDark: isDark,
              navBarColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
            ),
          ),
          if (notificationProvider.notifications.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECENT UPDATES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Colors.grey.withValues(alpha: 0.55),
                      ),
                    ),
                    GestureDetector(
                      onTap: _markedAsRead
                          ? null
                          : () {
                              setState(() {
                                _markedAsRead = true;
                              });
                              notificationProvider.markAsRead();
                              _resetTimer?.cancel();
                              _resetTimer = Timer(const Duration(seconds: 2), () {
                                if (mounted) {
                                  setState(() {
                                    _markedAsRead = false;
                                  });
                                }
                              });
                            },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) => ScaleTransition(
                          scale: animation,
                          child: FadeTransition(opacity: animation, child: child),
                        ),
                        child: _markedAsRead
                            ? Container(
                                key: const ValueKey('read_success'),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _themeGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_rounded,
                                        color: _themeGreen, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Read ✓',
                                      style: TextStyle(
                                        color: _themeGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                key: const ValueKey('read_button'),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _themeGreen.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Mark as read',
                                  style: TextStyle(
                                    color: _themeGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          notificationProvider.isLoading
              ? const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(color: _themeGreen),
            ),
          )
              : notificationProvider.notifications.isEmpty
              ? SliverFillRemaining(child: _buildEmptyState(isDark))
              : SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final notification =
                  notificationProvider.notifications[index];
                  return _buildDismissibleCard(
                      context, notification, isDark, notificationProvider);
                },
                childCount: notificationProvider.notifications.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _themeGreen.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 56,
                color: _themeGreen.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No notifications yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stay tuned for updates on your subscriptions and new postings in your area.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.grey.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDismissibleCard(
      BuildContext context,
      NotificationItem notification,
      bool isDark,
      NotificationProvider notificationProvider,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey(notification.hashCode),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade400,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.delete_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        confirmDismiss: (_) => _confirmDelete(context),
        onDismissed: (_) {
          notificationProvider.deleteNotification(notification);
        },
        child: _buildNotificationCard(context, notification, isDark, notificationProvider),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text('This notification will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildNotificationCard(
      BuildContext context,
      NotificationItem notification,
      bool isDark,
      NotificationProvider notificationProvider,
      ) {
    IconData icon;
    Color color;

    switch (notification.type) {
      case NotificationType.subscription:
        icon = Icons.receipt_long_rounded;
        color = _themeGreen;
        break;
      case NotificationType.posting:
        icon = Icons.new_releases_rounded;
        color = const Color(0xFFFFB703);
        break;
      case NotificationType.arrival:
        icon = Icons.location_on_rounded;
        color = Colors.blue.shade700;
        break;
      case NotificationType.onTheWay:
        icon = Icons.moped_rounded;
        color = Colors.orange.shade700;
        break;
    }

    return InkWell(
      onTap: () => _handleTap(context, notification),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey.withValues(alpha: 0.06),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: Colors.grey.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        TimeUtils.getTimeAgo(notification.timestamp),
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (notification.type == NotificationType.arrival)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFF2D6A4F).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white12
                              : const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        notification.message,
                        style: TextStyle(
                          color: isDark ? Colors.grey[200] : Colors.black87,
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    Text(
                      notification.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  if (notification.type == NotificationType.arrival)
                    _buildArrivalStatusWidget(
                        context, notification, isDark, notificationProvider),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: Colors.grey.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivalStatusWidget(
    BuildContext context,
    NotificationItem notification,
    bool isDark,
    NotificationProvider notificationProvider,
  ) {
    final currentStatus =
        _optimisticStatuses[notification.id] ?? notification.status;
    final isVisitor = notification.data?['is_visitor'] ?? false;

    Widget statusContent;

    if (currentStatus == 'pending' && !isVisitor) {
      statusContent = Container(
        key: ValueKey('pending_${notification.id}'),
        margin: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _optimisticStatuses[notification.id] = 'declined';
                  });
                  final arrivalId = notification.data?['arrival_id']?.toString() ??
                      notification.id.replaceFirst('arrival_', '');
                  notificationProvider.updateArrivalStatus(arrivalId, 'declined');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.cancel_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Arrival request declined.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
                icon: const Icon(Icons.cancel_rounded, size: 16),
                label: const Text('Decline',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _optimisticStatuses[notification.id] = 'accepted';
                  });
                  final arrivalId = notification.data?['arrival_id']?.toString() ??
                      notification.id.replaceFirst('arrival_', '');
                  notificationProvider.updateArrivalStatus(arrivalId, 'accepted');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Arrival accepted! Geofencing enabled for visitor.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF2D6A4F),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text('Accept',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      );
    } else if (currentStatus == 'accepted') {
      statusContent = Container(
        key: ValueKey('accepted_${notification.id}'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D6A4F).withValues(alpha: isDark ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF2D6A4F).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 15,
              color: Color(0xFF2D6A4F),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Accepted • Geofencing Active',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFF52B788)
                      : const Color(0xFF2D6A4F),
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (currentStatus == 'declined') {
      statusContent = Container(
        key: ValueKey('declined_${notification.id}'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: isDark ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cancel_outlined,
              size: 15,
              color: Colors.red.shade700,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Arrival Declined',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (currentStatus == 'arrived') {
      statusContent = Container(
        key: ValueKey('arrived_${notification.id}'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: isDark ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 15,
              color: Colors.blue.shade700,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Visitor Arrived at Destination',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      statusContent = SizedBox.shrink(key: ValueKey('empty_${notification.id}'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: animation,
            child: child,
          ),
        );
      },
      child: statusContent,
    );
  }

  void _handleTap(BuildContext context, NotificationItem notification) {
    if (notification.type == NotificationType.posting &&
        notification.data != null) {
      final ownerId = notification.data!['owner_id'];
      if (ownerId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfileScreen(userId: ownerId)),
        );
      }
    } else if ((notification.type == NotificationType.arrival ||
        notification.type == NotificationType.onTheWay) &&
        notification.data != null) {
      final isVisitor = notification.data!['is_visitor'] ?? false;
      final targetUserId =
      isVisitor ? notification.data!['host_id'] : notification.data!['visitor_id'];

      if (targetUserId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfileScreen(userId: targetUserId)),
        );
      }
    } else if (notification.type == NotificationType.subscription) {
      Navigator.pushNamed(context, '/subscription');
    }
  }
}