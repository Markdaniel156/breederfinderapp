import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification.dart';
import '../services/notification_service.dart';

class _ArrivalContent {
  final String title;
  final String message;
  const _ArrivalContent(this.title, this.message);
}

class NotificationProvider with ChangeNotifier {
  final _supabase = Supabase.instance.client;
  List<NotificationItem> _notifications = [];
  bool _isLoading = false;
  DateTime? _lastViewedAt;
  StreamSubscription? _authSubscription;
  StreamSubscription? _hostArrivalSubscription;
  StreamSubscription? _visitorArrivalSubscription;
  String? _currentUserId;

  List<NotificationItem> get notifications => _notifications;
  bool get isLoading => _isLoading;

  int get unreadCount {
    if (_notifications.isEmpty) return 0;
    if (_lastViewedAt == null) return _notifications.length;
    final count =
        _notifications.where((n) => n.timestamp.isAfter(_lastViewedAt!)).length;
    debugPrint(
        'Notification Unread Count: $count (Total: ${_notifications.length}, Last Viewed: $_lastViewedAt)');
    return count;
  }

  bool get hasUnread => unreadCount > 0;

  NotificationProvider() {
    _loadLastViewedAt();
    // Only init from auth listener to avoid double-init during startup
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        if (_currentUserId != user.id) {
          _currentUserId = user.id;
          _initArrivalListeners();
          fetchNotifications();
        }
      } else {
        _currentUserId = null;
        _hostArrivalSubscription?.cancel();
        _visitorArrivalSubscription?.cancel();
        _hostArrivalSubscription = null;
        _visitorArrivalSubscription = null;
        _notifications.clear();
        notifyListeners();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Shared arrival text. Only the 4 valid statuses produce a notification.
  // Anything else returns null (so it can never show "has arrived" by mistake).
  // ---------------------------------------------------------------------------
  _ArrivalContent? _buildArrivalContent({
    required bool isHost,
    required String status,
    required String visitorName,
    required String hostName,
  }) {
    if (isHost) {
      switch (status) {
        case 'pending':
          return _ArrivalContent('Arrival Request',
              '$visitorName wants to arrive at your location.');
        case 'accepted':
          return _ArrivalContent('Arrival Accepted',
              'You accepted $visitorName\'s arrival request.');
        case 'declined':
          return _ArrivalContent('Arrival Declined',
              'You declined $visitorName\'s arrival request.');
        case 'arrived':
          return _ArrivalContent(
              'Visitor Arrived', '$visitorName arrived at your location');
        default:
          return null;
      }
    } else {
      switch (status) {
        case 'pending':
          return _ArrivalContent('Arrival Request Sent',
              'Waiting for $hostName to accept your arrival request.');
        case 'accepted':
          return _ArrivalContent('Arrival Accepted',
              '$hostName accepted your arrival request! Geofencing is now active.');
        case 'declined':
          return _ArrivalContent('Arrival Declined',
              '$hostName declined your arrival request.');
        case 'arrived':
          return _ArrivalContent(
              'Arrival Recorded', 'You arrived at $hostName\'s location');
        default:
          return null;
      }
    }
  }

  /// Which side gets a push for which status.
  /// Visitor 'arrived' is NOT pushed here: the geofence service already shows
  /// the "You have arrived!" banner locally (avoids a duplicate).
  bool _shouldPush({required bool isHost, required String status}) {
    if (isHost) return status == 'pending' || status == 'arrived';
    return status == 'accepted' || status == 'declined';
  }

  void _initArrivalListeners() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _hostArrivalSubscription?.cancel();
    _visitorArrivalSubscription?.cancel();

    debugPrint('Initializing Arrival Streams for ${user.id}');

    // Listen as Host
    _hostArrivalSubscription = _supabase
        .from('arrivals')
        .stream(primaryKey: ['id'])
        .eq('host_id', user.id)
        .listen((data) => _processArrivalStream(data, isHostStream: true));

    // Listen as Visitor
    _visitorArrivalSubscription = _supabase
        .from('arrivals')
        .stream(primaryKey: ['id'])
        .eq('visitor_id', user.id)
        .listen((data) => _processArrivalStream(data, isHostStream: false));
  }

  void _processArrivalStream(List<Map<String, dynamic>> data,
      {required bool isHostStream}) {
    if (data.isEmpty) return;

    final now = DateTime.now();
    bool changed = false;

    for (final row in data) {
      final String status = row['status']?.toString() ?? '';
      final content = _buildArrivalContent(
        isHost: isHostStream,
        status: status,
        visitorName: row['visitor_name'] ?? 'A visitor',
        hostName: row['host_name'] ?? 'the host',
      );
      if (content == null) continue; // unknown status -> no notification

      final DateTime createdAt =
          DateTime.tryParse(row['created_at'] ?? '') ?? DateTime(2000);
      final String notificationId = 'arrival_${row['id']}';
      final int existingIndex =
      _notifications.indexWhere((n) => n.id == notificationId);

      final item = NotificationItem(
        id: notificationId,
        type: NotificationType.arrival,
        title: content.title,
        message: content.message,
        timestamp: createdAt,
        data: {
          'visitor_id': row['visitor_id'],
          'host_id': row['host_id'],
          'is_visitor': !isHostStream,
          'arrival_id': row['id'],
        },
        status: status,
      );

      bool shouldPush = false;

      if (existingIndex != -1) {
        // Known arrival: react to ANY status change (e.g. pending -> accepted),
        // no matter how old the request is.
        if (_notifications[existingIndex].status == status) continue;
        _notifications[existingIndex] = item;
        shouldPush = true;
        changed = true;
      } else {
        // Unknown arrival: only add recent ones (last hour)
        if (now.difference(createdAt) > const Duration(hours: 1)) continue;
        _notifications.insert(0, item);
        // Only push if it is genuinely fresh
        shouldPush = now.difference(createdAt).inSeconds < 120;
        changed = true;
      }

      if (shouldPush && _shouldPush(isHost: isHostStream, status: status)) {
        NotificationService.showVerifiedNotification(
          id: row['id'].hashCode,
          title: item.title,
          body: item.message,
          payload:
          'arrival_${isHostStream ? row['visitor_id'] : row['host_id']}',
        );
      }
    }

    if (changed) {
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _hostArrivalSubscription?.cancel();
    _visitorArrivalSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLastViewedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString('notifications_last_viewed');
    if (timestamp != null) {
      _lastViewedAt = DateTime.tryParse(timestamp);
    }
    notifyListeners();
  }

  /// Host accepts/declines. The realtime stream updates the list,
  /// so we do NOT remove the notification here.
  Future<void> updateArrivalStatus(String arrivalId, String status) async {
    try {
      await _supabase
          .from('arrivals')
          .update({'status': status}).eq('id', arrivalId);
      debugPrint(
          'Arrival status updated to $status for arrival ID: $arrivalId');
    } catch (e) {
      debugPrint('Error updating arrival status: $e');
    }
  }

  Future<void> deleteNotification(NotificationItem notification) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Optimistic UI update
    _notifications.removeWhere((n) => n.id == notification.id);
    notifyListeners();

    try {
      if (notification.type == NotificationType.arrival ||
          notification.type == NotificationType.onTheWay) {
        final String arrivalId =
        notification.id.replaceFirst('arrival_', '');
        await _supabase.from('arrivals').delete().eq('id', arrivalId);
        debugPrint('Arrival record $arrivalId deleted from database');
      } else {
        await _supabase.from('dismissed_notifications').insert({
          'user_id': user.id,
          'notification_id': notification.id,
        });
        debugPrint(
            'Notification ${notification.id} marked as dismissed for user ${user.id}');
      }
    } catch (e) {
      debugPrint('Error deleting/dismissing notification from database: $e');
    }
  }

  Future<void> markAsRead() async {
    _lastViewedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'notifications_last_viewed', _lastViewedAt!.toIso8601String());
    notifyListeners();
  }

  Future<void> fetchNotifications() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final List<NotificationItem> newNotifications = [];
      final userId = user.id;
      debugPrint('Fetching notifications for user: $userId');

      // 0. Dismissed notification IDs
      List<String> dismissedIds = [];
      try {
        final dismissedResponse = await _supabase
            .from('dismissed_notifications')
            .select('notification_id')
            .eq('user_id', userId);
        dismissedIds = (dismissedResponse as List)
            .map((d) => d['notification_id'].toString())
            .toList();
      } catch (e) {
        debugPrint(
            'Note: dismissed_notifications table might not exist yet. Error: $e');
      }

      // 1. Current month's subscriptions
      try {
        final now = DateTime.now();
        final firstDayOfMonth = DateTime(now.year, now.month, 1);

        final subResponse = await _supabase
            .from('subscriptions')
            .select('*')
            .eq('user_id', userId)
            .gte('created_at', firstDayOfMonth.toIso8601String());

        debugPrint('Subscriptions: ${subResponse.length}');

        for (var sub in subResponse) {
          final String id = 'sub_${sub['id']}';
          if (dismissedIds.contains(id)) continue;

          newNotifications.add(NotificationItem(
            id: id,
            type: NotificationType.subscription,
            title: 'Payment Successful',
            message:
            'Your payment of ₱${sub['amount']} for the ${sub['plan_name']} plan was recorded.',
            timestamp:
            DateTime.tryParse(sub['created_at'] ?? '') ?? DateTime.now(),
          ));
        }
      } catch (e) {
        debugPrint('Error fetching subscriptions: $e');
      }

      // 1.5. Solo Plan posting usage
      try {
        final nowStr = DateTime.now().toIso8601String();
        final activeSub = await _supabase
            .from('subscriptions')
            .select('plan_name, created_at')
            .eq('user_id', userId)
            .gt('expires_at', nowStr)
            .maybeSingle();

        if (activeSub != null && activeSub['plan_name'] == 'Solo Plan') {
          final breederCountRes = await _supabase
              .from('breeder_postings')
              .select('id')
              .eq('user_id', userId);
          final traderCountRes = await _supabase
              .from('trader_postings')
              .select('id')
              .eq('user_id', userId);

          final int postCount =
              (breederCountRes as List).length + (traderCountRes as List).length;
          final int remaining = (10 - postCount).clamp(0, 10);
          final String soloNotifId =
              'solo_plan_usage_${userId}_${DateTime.now().year}_${DateTime.now().month}_${DateTime.now().day}';

          if (!dismissedIds.contains(soloNotifId)) {
            newNotifications.add(NotificationItem(
              id: soloNotifId,
              type: NotificationType.subscription,
              title: 'Solo Plan Posting Transparency',
              message:
              'You have used $postCount of 10 postings on your Solo Plan ($remaining remaining).',
              timestamp: DateTime.tryParse(activeSub['created_at'] ?? '') ??
                  DateTime.now(),
            ));
          }
        }
      } catch (e) {
        debugPrint('Error checking Solo Plan notification: $e');
      }

      // 2. New postings (last 7 days) from others
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

      try {
        final breederResponse = await _supabase
            .from('breeder_postings')
            .select('id, breed, name, created_at, user_id')
            .neq('user_id', userId)
            .eq('is_registered', true)
            .gte('created_at', sevenDaysAgo.toIso8601String());

        debugPrint('Breeder postings: ${breederResponse.length}');

        for (var post in breederResponse) {
          final String id = 'post_breeder_${post['id']}';
          if (dismissedIds.contains(id)) continue;

          newNotifications.add(NotificationItem(
            id: id,
            type: NotificationType.posting,
            title: 'New Breeder Listing',
            message:
            '${post['name']} just posted a new listing for ${post['breed']}.',
            timestamp:
            DateTime.tryParse(post['created_at'] ?? '') ?? DateTime.now(),
            data: {
              'listing_id': post['id'],
              'listing_type': 'breeder',
              'owner_id': post['user_id']
            },
          ));
        }
      } catch (e) {
        debugPrint('Error fetching breeder postings: $e');
      }

      try {
        final traderResponse = await _supabase
            .from('trader_postings')
            .select('id, category, name, created_at, user_id')
            .neq('user_id', userId)
            .eq('is_registered', true)
            .gte('created_at', sevenDaysAgo.toIso8601String());

        debugPrint('Trader postings: ${traderResponse.length}');

        for (var post in traderResponse) {
          final String id = 'post_trader_${post['id']}';
          if (dismissedIds.contains(id)) continue;

          newNotifications.add(NotificationItem(
            id: id,
            type: NotificationType.posting,
            title: 'New Trader Listing',
            message: '${post['name']} is looking for ${post['category']}.',
            timestamp:
            DateTime.tryParse(post['created_at'] ?? '') ?? DateTime.now(),
            data: {
              'listing_id': post['id'],
              'listing_type': 'trader',
              'owner_id': post['user_id']
            },
          ));
        }
      } catch (e) {
        debugPrint('Error fetching trader postings: $e');
      }

      // 3. Arrivals where current user is Host OR Visitor
      try {
        debugPrint('Querying arrivals for user: $userId');
        final arrivalResponse = await _supabase
            .from('arrivals')
            .select('*')
            .or('host_id.eq.$userId,visitor_id.eq.$userId')
            .order('created_at', ascending: false)
            .limit(50);

        debugPrint('Arrivals raw count: ${arrivalResponse.length}');

        for (var arrival in arrivalResponse) {
          final String hostId = arrival['host_id']?.toString() ?? '';
          final String visitorId = arrival['visitor_id']?.toString() ?? '';
          final String status = arrival['status']?.toString() ?? '';
          final bool isHost = hostId == userId;

          final content = _buildArrivalContent(
            isHost: isHost,
            status: status,
            visitorName: arrival['visitor_name'] ?? 'A visitor',
            hostName: arrival['host_name'] ?? 'the host',
          );
          if (content == null) continue; // unknown status -> skip

          newNotifications.add(NotificationItem(
            id: 'arrival_${arrival['id']}',
            type: NotificationType.arrival,
            title: content.title,
            message: content.message,
            timestamp:
            DateTime.tryParse(arrival['created_at'] ?? '') ?? DateTime.now(),
            data: {
              'visitor_id': visitorId,
              'host_id': hostId,
              'is_visitor': !isHost,
              'arrival_id': arrival['id'],
            },
            status: status,
          ));
        }
      } catch (e) {
        debugPrint('Error fetching arrivals: $e');
      }

      newNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _notifications = newNotifications;

      debugPrint('Total notifications processed: ${_notifications.length}');
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}