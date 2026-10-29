import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/breeder.dart';

class GeofencingService {
  // ---------------------------------------------------------------------------
  // SINGLETON: every `GeofencingService()` in your app now returns the SAME
  // object, so the watcher and monitorGeofences() always share state.
  // ---------------------------------------------------------------------------
  static final GeofencingService _instance = GeofencingService._internal();
  factory GeofencingService() => _instance;
  GeofencingService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static const double _arrivalRadiusMeters = 200;

  final Map<String, DateTime> _lastCheck = {};
  final Set<String> _checking = {};

  // Optional manual target (breeder id). Nothing is recorded until the
  // arrival row in Supabase has status == 'accepted'.
  String? activeTargetId;

  // Hosts (user ids) that ACCEPTED this visitor's request.
  final Set<String> _acceptedHostIds = {};

  StreamSubscription? _authSub;
  StreamSubscription? _acceptedSub;
  Timer? _recheckTimer;
  List<Breeder> _lastBreeders = [];
  String? _visitorId;
  String? _visitorName;
  String? _visitorRole;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Geofence Notification tapped: ${response.payload}');
      },
    );

    final androidImplementation =
    _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'geofence_channel',
      'Breeder Finder Alerts',
      description: 'Notifications for breeder proximity and arrivals',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _listenToAuth();

    debugPrint('Geofencing Service Initialized');
  }

  // Auto-start / auto-stop the watcher with login / logout.
  void _listenToAuth() {
    final auth = Supabase.instance.client.auth;

    final current = auth.currentUser;
    if (current != null) {
      startAcceptedArrivalWatcher(visitorId: current.id);
    }

    _authSub?.cancel();
    _authSub = auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        if (_visitorId != user.id || _acceptedSub == null) {
          startAcceptedArrivalWatcher(visitorId: user.id);
        }
      } else {
        stopAcceptedArrivalWatcher();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Watcher: starts geofencing as soon as the host accepts, even if the
  // visitor is already standing inside the zone.
  // ---------------------------------------------------------------------------
  void startAcceptedArrivalWatcher({
    required String visitorId,
    String? visitorName,
    String? visitorRole,
  }) {
    _visitorId = visitorId;
    _visitorName = visitorName ?? _visitorName;
    _visitorRole = visitorRole ?? _visitorRole;

    debugPrint('Accepted-arrival watcher started for visitor $visitorId');

    _acceptedSub?.cancel();
    _acceptedSub = Supabase.instance.client
        .from('arrivals')
        .stream(primaryKey: ['id'])
        .eq('visitor_id', visitorId)
        .listen((rows) {
      _acceptedHostIds
        ..clear()
        ..addAll(rows
            .where((r) => r['status'] == 'accepted')
            .map((r) => r['host_id'].toString()));

      debugPrint('Accepted hosts being tracked: $_acceptedHostIds');
      if (_acceptedHostIds.isNotEmpty) _checkNow();
    });

    _recheckTimer?.cancel();
    _recheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_acceptedHostIds.isNotEmpty || activeTargetId != null) _checkNow();
    });
  }

  void stopAcceptedArrivalWatcher() {
    _acceptedSub?.cancel();
    _recheckTimer?.cancel();
    _acceptedSub = null;
    _recheckTimer = null;
    _acceptedHostIds.clear();
    activeTargetId = null;
    _visitorId = null;
  }

  Future<void> _checkNow() async {
    if (_visitorId == null || _lastBreeders.isEmpty) {
      debugPrint(
          'Geofence check skipped: visitorId=$_visitorId breeders=${_lastBreeders.length} '
              '(monitorGeofences() must be called with the breeder list)');
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      monitorGeofences(
        pos,
        _lastBreeders,
        currentUserId: _visitorId,
        currentUserName: _visitorName,
        currentUserRole: _visitorRole,
      );
    } catch (e) {
      debugPrint('Geofence recheck error: $e');
    }
  }

  void monitorGeofences(
      Position userPosition,
      List<Breeder> breeders, {
        String? currentUserId,
        String? currentUserName,
        String? currentUserRole,
      }) {
    _lastBreeders = breeders;
    _visitorId ??= currentUserId;
    _visitorName ??= currentUserName;
    _visitorRole ??= currentUserRole;

    if (currentUserId == null) return;

    for (final breeder in breeders) {
      if (breeder.userId == currentUserId || breeder.id == currentUserId) {
        continue;
      }

      final bool isTarget = breeder.id == activeTargetId ||
          _acceptedHostIds.contains(breeder.userId);
      if (!isTarget) continue;

      final double distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        breeder.location.latitude,
        breeder.location.longitude,
      );

      debugPrint('Distance to ${breeder.name}: ${distance.round()}m');

      if (distance >= _arrivalRadiusMeters) continue;

      if (_checking.contains(breeder.id)) continue;
      final lastCheck = _lastCheck[breeder.id];
      if (lastCheck != null &&
          DateTime.now().difference(lastCheck).inSeconds < 5) {
        continue;
      }

      _checking.add(breeder.id);
      _lastCheck[breeder.id] = DateTime.now();

      _tryConfirmArrival(
        visitorId: currentUserId,
        hostId: breeder.userId,
        hostName: breeder.name,
        breederId: breeder.id,
      );
    }
  }

  /// Only marks the arrival as 'arrived' if the host already ACCEPTED it.
  Future<void> _tryConfirmArrival({
    required String visitorId,
    required String hostId,
    required String hostName,
    required String breederId,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      final latest = await supabase
          .from('arrivals')
          .select('id, status')
          .eq('visitor_id', visitorId)
          .eq('host_id', hostId)
          .order('created_at', ascending: false)
          .limit(1);

      if (latest.isEmpty) return;

      final String arrivalId = latest.first['id'].toString();
      final String status = latest.first['status']?.toString() ?? '';

      if (status == 'declined') {
        debugPrint('Arrival declined by host, stopping geofence for $breederId');
        _acceptedHostIds.remove(hostId);
        if (activeTargetId == breederId) activeTargetId = null;
        return;
      }

      if (status != 'accepted') {
        debugPrint(
            'Inside 200m but arrival status is "$status"; waiting for host acceptance');
        return;
      }

      final updated = await supabase
          .from('arrivals')
          .update({'status': 'arrived'})
          .eq('id', arrivalId)
          .eq('status', 'accepted')
          .select('id');

      if (updated.isEmpty) return;

      debugPrint('Arrival $arrivalId confirmed inside geofence');

      _acceptedHostIds.remove(hostId);
      if (activeTargetId == breederId) activeTargetId = null;

      await _sendArrivalNotification(hostName, breederId, isTarget: true);
    } catch (e) {
      debugPrint('Error confirming arrival: $e');
    } finally {
      _checking.remove(breederId);
    }
  }

  void setActiveTarget(String? id) {
    activeTargetId = id;
    if (id != null) {
      debugPrint('Precision tracking activated for target: $id');
    }
  }

  /// "Arrive Here" button: creates a PENDING request only.
  Future<void> recordManualArrival({
    required String visitorId,
    required String visitorName,
    required String visitorRole,
    required String hostId,
    required String hostName,
  }) async {
    debugPrint('Manual Arrival request triggered for host: $hostId');
    final supabase = Supabase.instance.client;

    _visitorId = visitorId;
    _visitorName = visitorName;
    _visitorRole = visitorRole;

    try {
      await supabase
          .from('arrivals')
          .delete()
          .eq('visitor_id', visitorId)
          .eq('host_id', hostId)
          .or('status.eq.pending,status.eq.accepted');
      _acceptedHostIds.remove(hostId);
    } catch (e) {
      debugPrint('Error cleaning up stale arrival requests: $e');
    }

    try {
      await supabase.from('arrivals').insert({
        'visitor_id': visitorId,
        'host_id': hostId,
        'visitor_name': visitorName,
        'visitor_role': visitorRole,
        'host_name': hostName,
        'status': 'pending',
      });
      debugPrint('Pending arrival created: $visitorName -> $hostName');
    } catch (e) {
      debugPrint('Error creating arrival request: $e');
    }
  }

  Future<void> _sendArrivalNotification(String hostName, String breederId,
      {bool isTarget = false}) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'geofence_channel',
      'Geofence Notifications',
      channelDescription: 'Notifications for arrival status',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/launcher_icon',
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    final String title = isTarget ? 'You have arrived!' : 'Nearby Discovery!';
    final String body = isTarget
        ? 'You have arrived at $hostName\'s location.'
        : 'You are within 200m of $hostName.';

    await _notificationsPlugin.show(
      breederId.hashCode + 1,
      title,
      body,
      platformChannelSpecifics,
      payload: 'arrival_$breederId',
    );
  }

  void dispose() {
    _authSub?.cancel();
    stopAcceptedArrivalWatcher();
  }
}