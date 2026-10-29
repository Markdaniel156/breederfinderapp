import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/breeder_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/breeder.dart';
import '../models/review.dart';
import '../services/geofencing_service.dart';
import '../services/time_utils.dart';
import 'chat_screen.dart';
import '../widgets/restricted_access_dialog.dart';
import '../providers/auth_provider.dart';
import '../utils/system_ui_utils.dart';

// ─── Design tokens ──────────────────────────────────────────────────────────
const _green = Color(0xFF2D6A4F);
const _surfaceLight = Colors.white;
const _surfaceDark = Color(0xFF1E1E1E);
const _chipLight = Color(0xFFF1F3EE);
const _chipDark = Color(0xFF2A2A2A);

Color _roleColor(String role) => role == 'Breeder' ? _green : Colors.orange;

class MapScreen extends StatefulWidget {
  final GeofencingService? geofenceService;
  const MapScreen({super.key, this.geofenceService});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  LatLng? _currentPosition;
  bool _isInitialLoad = true;
  final Map<String, BitmapDescriptor> _markerIcons = {}; // Key: userId
  final Map<String, String> _markerImageUrls = {}; // Key: userId, Value: imageUrl
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _currentUserData;
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription? _visitorArrivalMapSubscription;
  final Set<String> _processedArrivalIds = {};
  BitmapDescriptor? _userMarkerIcon;
  double _userBearing = 0;
  bool _shouldFollowUser = true;
  DateTime? _lastGeofenceCheck;
  DateTime? _lastLocationSync;
  bool _isLoadingMarkers = false;

  // Search State
  final SearchController _searchController = SearchController();

  // Light style: same map, minus the business/transit clutter.
  final String _lightMapStyle = '''
[
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]}
]
''';

  final String _darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#242f3e"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#242f3e"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#746855"}]},
  {"featureType": "administrative", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "poi", "elementType": "labels.icon", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.business", "elementType": "labels.text.fill", "stylers": [{"color": "#f1c40f"}]},
  {"featureType": "poi.place_of_worship", "elementType": "labels.text.fill", "stylers": [{"color": "#f1c40f"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#263c3f"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6b9a76"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#38414e"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212a37"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca5b3"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#746855"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#1f2835"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#f3d19c"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2f3948"}]},
  {"featureType": "transit.station", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17263c"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#515c6d"}]},
  {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#17263c"}]}
]
''';

  Set<Circle> _getUserArrivalCircle(List<Breeder> breeders) {
    // Only show the arrival zone if we are actively tracking a target
    final targetId = widget.geofenceService?.activeTargetId;
    if (targetId == null) return {};

    final targetBreeder = breeders.where((b) => b.id == targetId).firstOrNull;
    if (targetBreeder == null) return {};

    return {
      Circle(
        circleId: const CircleId('arrival_zone'),
        center: targetBreeder.location,
        radius: 200, // 200 meters
        fillColor: _green.withValues(alpha: 0.15),
        strokeColor: _green,
        strokeWidth: 2,
      ),
    };
  }

  Circle _approxCircle(String id, LatLng center, Color color) => Circle(
    circleId: CircleId(id),
    center: center,
    radius: 500,
    fillColor: color.withValues(alpha: 0.15),
    strokeColor: color.withValues(alpha: 0.5),
    strokeWidth: 2,
  );

  /// Picks the single best listing to represent a user on the map.
  ///
  /// A user can have listings in both breeder_postings and trader_postings.
  /// We always prefer:
  ///   1. A listing that actually has a pinned location (non-zero lat/lng)
  ///      over one that doesn't.
  ///   2. Among listings that are equally "has a location or not", the most
  ///      recently created/updated one.
  void _considerBreederForMap(Map<String, Breeder> uniqueBreeders, Breeder breeder) {
    final key = breeder.userId;
    final existing = uniqueBreeders[key];

    if (existing == null) {
      uniqueBreeders[key] = breeder;
      return;
    }

    bool hasLoc(Breeder b) => b.location.latitude != 0 || b.location.longitude != 0;
    final existingHasLoc = hasLoc(existing);
    final newHasLoc = hasLoc(breeder);

    if (!existingHasLoc && newHasLoc) {
      uniqueBreeders[key] = breeder;
    } else if (existingHasLoc == newHasLoc) {
      final existingDate = existing.createdAt ?? DateTime(2000);
      final newDate = breeder.createdAt ?? DateTime(2000);
      if (newDate.isAfter(existingDate)) {
        uniqueBreeders[key] = breeder;
      }
    }
  }

  void _loadMarkerIcons() {
    if (_isLoadingMarkers) return;

    final breederProvider = Provider.of<BreederProvider>(context, listen: false);
    final currentUserId = _supabase.auth.currentUser?.id;
    bool foundChanges = false;

    // Filter unique breeders for icon generation
    final Map<String, Breeder> uniqueBreeders = {};
    for (var b in breederProvider.breeders) {
      if (b.location.latitude == 0 || b.animals.isEmpty || b.userId == currentUserId) continue;
      _considerBreederForMap(uniqueBreeders, b);
    }

    for (var breeder in uniqueBreeders.values) {
      final cachedUrl = _markerImageUrls[breeder.userId];
      if (!_markerIcons.containsKey(breeder.userId) || cachedUrl != breeder.imageUrl) {
        foundChanges = true;
        break;
      }
    }

    if (foundChanges) {
      _isLoadingMarkers = true;
      Future.microtask(() async {
        for (var breeder in uniqueBreeders.values) {
          final cachedUrl = _markerImageUrls[breeder.userId];
          if (!_markerIcons.containsKey(breeder.userId) || cachedUrl != breeder.imageUrl) {
            await _generateCustomMarker(breeder);
          }
        }
        if (mounted) {
          setState(() {
            _isLoadingMarkers = false;
          });
        }
      });
    }
  }

  Future<void> _generateCustomMarker(Breeder breeder) async {
    final Color markerColor = _roleColor(breeder.role);
    final String roleInitial = breeder.role == 'Breeder' ? 'B' : 'T';

    final icon = await _createMarkerIcon(
      imageUrl: breeder.imageUrl,
      name: breeder.name,
      color: markerColor,
      roleInitial: roleInitial,
    );

    if (mounted) {
      setState(() {
        _markerIcons[breeder.userId] = icon;
        _markerImageUrls[breeder.userId] = breeder.imageUrl;
      });
    }
  }

  // Marker size is controlled here. All drawing coordinates below are
  // multiplied by `scale`.
  static const double _markerScale = 0.50;

  Future<BitmapDescriptor> _createMarkerIcon({
    required String imageUrl,
    required String name,
    required Color color,
    required String roleInitial,
    bool pointTop = false,
  }) async {
    try {
      const double scale = _markerScale;

      final PictureRecorder pictureRecorder = PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);

      // Circle center depends on pointer direction
      final Offset center = Offset(60 * scale, pointTop ? 80 * scale : 60 * scale);

      // Draw shadow
      final Paint shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3 * scale);
      canvas.drawCircle(center, 52 * scale, shadowPaint);

      // Draw pointer (triangle)
      final Paint paint = Paint()..color = color;
      final Path path = Path();
      if (pointTop) {
        path.moveTo(45 * scale, 35 * scale);
        path.lineTo(60 * scale, 10 * scale);
        path.lineTo(75 * scale, 35 * scale);
      } else {
        path.moveTo(45 * scale, 105 * scale);
        path.lineTo(60 * scale, 130 * scale);
        path.lineTo(75 * scale, 105 * scale);
      }
      path.close();
      canvas.drawPath(path, paint);

      // Draw outer circle
      canvas.drawCircle(center, 50 * scale, paint);

      // Draw inner white circle
      final Paint whitePaint = Paint()..color = Colors.white;
      canvas.drawCircle(center, 46 * scale, whitePaint);

      // Draw Image circle
      final Rect imageRect = Rect.fromLTWH(
          center.dx - 42 * scale, center.dy - 42 * scale, 84 * scale, 84 * scale);
      canvas.save();
      canvas.clipPath(Path()..addOval(imageRect));

      if (imageUrl.isNotEmpty) {
        try {
          final HttpClient httpClient = HttpClient();
          final HttpClientRequest request = await httpClient.getUrl(Uri.parse(imageUrl));
          final HttpClientResponse response = await request.close();
          final Uint8List bytes = await consolidateHttpClientResponseBytes(response);

          final codec = await instantiateImageCodec(bytes, targetWidth: 300, targetHeight: 300);
          final frame = await codec.getNextFrame();
          canvas.drawImageRect(
            frame.image,
            Rect.fromLTWH(0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
            imageRect,
            Paint()..filterQuality = FilterQuality.high,
          );
        } catch (e) {
          canvas.drawRect(imageRect, Paint()..color = color.withValues(alpha: 0.2));
          _drawFallbackInitial(canvas, name, color, scale, center);
        }
      } else {
        canvas.drawRect(imageRect, Paint()..color = color.withValues(alpha: 0.2));
        _drawFallbackInitial(canvas, name, color, scale, center);
      }
      canvas.restore();

      // Role Badge at bottom right of circle
      final Offset badgeCenter = Offset(center.dx + 35 * scale, center.dy + 35 * scale);
      canvas.drawCircle(badgeCenter, 18 * scale, whitePaint);
      canvas.drawCircle(badgeCenter, 15 * scale, paint);

      TextPainter rolePainter = TextPainter(textDirection: TextDirection.ltr);
      rolePainter.text = TextSpan(
        text: roleInitial,
        style: TextStyle(fontSize: 16 * scale, color: Colors.white, fontWeight: FontWeight.bold),
      );
      rolePainter.layout();
      rolePainter.paint(
        canvas,
        Offset(badgeCenter.dx - rolePainter.width / 2, badgeCenter.dy - rolePainter.height / 2),
      );

      final int w = (120 * scale).round();
      final int h = (140 * scale).round();
      final img = await pictureRecorder.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ImageByteFormat.png);

      return BitmapDescriptor.bytes(data!.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error creating custom marker: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  void _drawFallbackInitial(Canvas canvas, String name, Color color, double scale, Offset center) {
    TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
    painter.text = TextSpan(
      text: name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(fontSize: 40 * scale, color: color, fontWeight: FontWeight.bold),
    );
    painter.layout();
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
  }

  // ─── Shared UI helpers ────────────────────────────────────────────────────

  void _showSnack(
      ScaffoldMessengerState messenger, {
        required IconData icon,
        required String title,
        String? subtitle,
        Color color = _green,
      }) {
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.white)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ],
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  BoxDecoration _floatingDecoration(bool isDark, {double radius = 30}) => BoxDecoration(
    color: isDark ? _surfaceDark : _surfaceLight,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Widget _roundButton({
    required IconData icon,
    required VoidCallback? onTap,
    required bool isDark,
    String? tooltip,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: _floatingDecoration(isDark, radius: 24),
      child: IconButton(
        icon: Icon(icon, color: isDark ? Colors.white : Colors.black87, size: 22),
        onPressed: onTap,
        tooltip: tooltip,
      ),
    );
  }

  // ─── Arrival listener (logic unchanged) ───────────────────────────────────

  void _initVisitorArrivalListener() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    _visitorArrivalMapSubscription?.cancel();
    _visitorArrivalMapSubscription = _supabase
        .from('arrivals')
        .stream(primaryKey: ['id'])
        .eq('visitor_id', user.id)
        .listen((data) {
      if (data.isEmpty) return;

      // Only consider arrival requests created within the last 30 minutes
      final thirtyMinsAgo = DateTime.now().subtract(const Duration(minutes: 30));
      final recentData = data.where((item) {
        final createdAt = DateTime.tryParse(item['created_at'] ?? '') ?? DateTime(2000);
        return createdAt.isAfter(thirtyMinsAgo);
      }).toList();

      if (recentData.isEmpty) {
        if (widget.geofenceService?.activeTargetId != null) {
          widget.geofenceService?.setActiveTarget(null);
          if (mounted) setState(() {});
        }
        return;
      }

      recentData.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });

      final latest = recentData.first;
      final String arrivalId = latest['id']?.toString() ?? '';
      final String status = latest['status']?.toString() ?? '';
      final String hostId = latest['host_id']?.toString() ?? '';

      if (status == 'accepted') {
        if (hostId.isNotEmpty && widget.geofenceService?.activeTargetId != hostId) {
          widget.geofenceService?.setActiveTarget(hostId);
          if (mounted) {
            setState(() {});
            if (!_processedArrivalIds.contains('${arrivalId}_accepted')) {
              _processedArrivalIds.add('${arrivalId}_accepted');
              _showSnack(
                ScaffoldMessenger.of(context),
                icon: Icons.verified_rounded,
                title: 'Arrival accepted',
                subtitle:
                '${latest['host_name'] ?? 'The host'} accepted your request. Geofencing is now active.',
              );
            }
          }
        }
      } else if (status == 'declined') {
        if (widget.geofenceService?.activeTargetId == hostId) {
          widget.geofenceService?.setActiveTarget(null);
        }
        if (mounted) {
          setState(() {});
          if (!_processedArrivalIds.contains('${arrivalId}_declined')) {
            _processedArrivalIds.add('${arrivalId}_declined');
            _showSnack(
              ScaffoldMessenger.of(context),
              icon: Icons.block_rounded,
              title: 'Arrival declined',
              subtitle: '${latest['host_name'] ?? 'The host'} declined your request.',
              color: Colors.red[700]!,
            );
          }
        }
      } else if (status == 'pending') {
        // Geofencing stays off while waiting for acceptance
        if (widget.geofenceService?.activeTargetId == hostId) {
          widget.geofenceService?.setActiveTarget(null);
          if (mounted) setState(() {});
        }
      } else if (status == 'arrived') {
        // Deactivate geofencing once arrival is complete
        if (widget.geofenceService?.activeTargetId == hostId) {
          widget.geofenceService?.setActiveTarget(null);
          if (mounted) setState(() {});
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _loadCurrentUserData().then((_) {
      _loadUserMarkerIcon();
      _startLocationStreaming();
      _initVisitorArrivalListener();
    });
    _checkConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMarkerIcons();
    });
  }

  Future<void> _loadUserMarkerIcon() async {
    if (_currentUserData == null) return;

    String avatarUrl = _currentUserData!['avatar_url'] ?? '';
    if (avatarUrl.isNotEmpty && !avatarUrl.startsWith('http')) {
      avatarUrl = _supabase.storage.from('avatars').getPublicUrl(avatarUrl);
    }

    final icon = await _createMarkerIcon(
      imageUrl: avatarUrl,
      name: _currentUserData!['full_name'] ?? 'Me',
      color: _green,
      roleInitial: 'Me',
      pointTop: true, // User marker points forward (up)
    );

    if (mounted) {
      setState(() {
        _userMarkerIcon = icon;
      });
    }
  }

  void _startLocationStreaming() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // Update every 1 meter
      ),
    ).listen((Position position) {
      if (mounted) {
        final newLatLng = LatLng(position.latitude, position.longitude);

        if (_currentPosition != null) {
          double distance = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          // Only update bearing if movement is significant (> 2m) to avoid jitters
          if (distance > 2) {
            _userBearing = Geolocator.bearingBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              position.latitude,
              position.longitude,
            );
          }
        }

        setState(() {
          _currentPosition = newLatLng;
        });

        // Real-time location sync (10s throttle to Supabase)
        if (_currentUserData != null &&
            (_lastLocationSync == null ||
                DateTime.now().difference(_lastLocationSync!).inSeconds > 10)) {
          _lastLocationSync = DateTime.now();
          Provider.of<BreederProvider>(context, listen: false).updateUserLocation(
            userId: _currentUserData!['id'],
            location: newLatLng,
            role: _currentUserData!['role'] ?? 'Breeder',
          );
        }

        // Geofence check with 3-second throttle to save CPU
        if (widget.geofenceService != null &&
            (_lastGeofenceCheck == null ||
                DateTime.now().difference(_lastGeofenceCheck!).inSeconds > 3)) {
          _lastGeofenceCheck = DateTime.now();
          final breeders = Provider.of<BreederProvider>(context, listen: false).breeders;
          widget.geofenceService!.monitorGeofences(
            position,
            breeders,
            currentUserId: _currentUserData?['id'],
            currentUserName: _currentUserData?['full_name'],
            currentUserRole: _currentUserData?['role'],
          );
        }

        // Auto-follow camera if enabled
        if (_shouldFollowUser && mapController != null) {
          mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: newLatLng,
                zoom: 18,
                tilt: 60,
                bearing: _userBearing,
              ),
            ),
          );
        }
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
      });
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _positionStreamSubscription?.cancel();
    _visitorArrivalMapSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final data = await _supabase.from('create_account').select().eq('id', user.id).single();
        if (mounted) {
          setState(() {
            _currentUserData = data;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<LatLng?> _determinePosition({bool triggerGeofence = false}) async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled. Please enable them.')),
          );
        }
        return null;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied.')),
            );
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are permanently denied.')),
          );
        }
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Trigger geofence check when user manually "pins" or updates their location
      if (triggerGeofence && widget.geofenceService != null && mounted) {
        final breeders = Provider.of<BreederProvider>(context, listen: false).breeders;
        widget.geofenceService!.monitorGeofences(
          position,
          breeders,
          currentUserId: _currentUserData?['id'],
          currentUserName: _currentUserData?['full_name'],
          currentUserRole: _currentUserData?['role'],
        );
      }

      final latLng = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentPosition = latLng;
        });

        if (mapController != null) {
          mapController!.animateCamera(
            CameraUpdate.newCameraPosition(CameraPosition(target: latLng, zoom: 15)),
          );
        }
      }
      return latLng;
    } catch (e) {
      debugPrint('Error determining position: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
      return null;
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _handleNavigationFocus();
  }

  void _handleNavigationFocus() {
    if (mapController == null) return;

    final navProvider = Provider.of<NavigationProvider>(context, listen: false);
    final selectedBreeder = navProvider.selectedBreeder;

    if (selectedBreeder != null) {
      mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: selectedBreeder.location, zoom: 15),
        ),
      );
      // Automatically show details for the selected breeder
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showBreederDetails(
            context, selectedBreeder, Theme.of(context).brightness == Brightness.dark);
      });
    } else if (_currentPosition != null && _isInitialLoad) {
      mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: _currentPosition!, zoom: 12)),
      );
      _isInitialLoad = false;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final breederProvider = Provider.of<BreederProvider>(context);
    final navProvider = Provider.of<NavigationProvider>(context);
    final selectedBreeder = navProvider.selectedBreeder;

    final breeders = breederProvider.breeders;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.of(context).padding.top;

    // Pick up marker icons whenever new breeders arrive (no-op if nothing changed)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMarkerIcons();
    });

    final Set<Marker> markers = {};
    final Set<Circle> circles = _getUserArrivalCircle(breeders);

    if (selectedBreeder != null) {
      if (selectedBreeder.mapPrivacy == 'Approximate') {
        circles.add(_approxCircle('approx_${selectedBreeder.userId}', selectedBreeder.location,
            _roleColor(selectedBreeder.role)));
      }

      if (selectedBreeder.mapPrivacy != 'Hidden') {
        markers.add(
          Marker(
            markerId: MarkerId(selectedBreeder.userId),
            position: selectedBreeder.location,
            icon: _markerIcons[selectedBreeder.userId] ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            anchor: const Offset(0.5, 0.93),
            alpha: selectedBreeder.mapPrivacy == 'Approximate' ? 0.4 : 1.0,
            infoWindow: InfoWindow(title: selectedBreeder.name, snippet: selectedBreeder.role),
          ),
        );
      }
    } else {
      final Map<String, Breeder> uniqueBreeders = {};
      final currentUserId = _supabase.auth.currentUser?.id;

      for (var breeder in breeders) {
        if (breeder.location.latitude == 0 || breeder.animals.isEmpty) continue;
        if (breeder.userId == currentUserId) continue;
        _considerBreederForMap(uniqueBreeders, breeder);
      }

      for (var breeder in uniqueBreeders.values) {
        if (breeder.mapPrivacy == 'Hidden') continue;

        if (breeder.mapPrivacy == 'Approximate') {
          circles.add(
              _approxCircle('approx_${breeder.userId}', breeder.location, _roleColor(breeder.role)));
        }

        markers.add(
          Marker(
            markerId: MarkerId(breeder.userId),
            position: breeder.location,
            icon: _markerIcons[breeder.userId] ??
                (breeder.role == 'Breeder'
                    ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
                    : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)),
            anchor: const Offset(0.5, 0.93),
            alpha: breeder.mapPrivacy == 'Approximate' ? 0.4 : 1.0,
            infoWindow: InfoWindow(
              title: breeder.name,
              snippet: breeder.role,
              onTap: () => _showBreederDetails(context, breeder, isDark),
            ),
          ),
        );
      }
    }

    // Check if current user is registered but hasn't set their location
    final currentUserId = _supabase.auth.currentUser?.id;
    final currentUserRegistration =
        breeders.where((b) => b.userId == currentUserId).firstOrNull;
    final currentUserHasPosts =
        currentUserRegistration != null && currentUserRegistration.animals.isNotEmpty;
    final needsLocationSetup =
        currentUserRegistration != null && currentUserRegistration.location.latitude == 0;

    final String currentUserPrivacy = currentUserRegistration?.mapPrivacy ??
        _currentUserData?['privacy_mode'] ??
        'Exact';

    // Current user marker: visible to regular viewers, or businesses with at
    // least one post, and only when privacy mode is not 'Hidden'.
    if (_currentPosition != null && currentUserPrivacy != 'Hidden') {
      final bool shouldShowSelf = currentUserRegistration == null || currentUserHasPosts;

      if (shouldShowSelf) {
        if (currentUserPrivacy == 'Approximate') {
          circles.add(_approxCircle('approx_current_user', _currentPosition!, _green));
        }

        markers.add(
          Marker(
            markerId: const MarkerId('current_user'),
            position: _currentPosition!,
            icon: _userMarkerIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            rotation: 0,
            anchor: const Offset(0.5, 0.07), // Tip of top pointer
            flat: false,
            alpha: currentUserPrivacy == 'Approximate' ? 0.4 : 1.0,
            zIndexInt: 10,
            infoWindow: const InfoWindow(title: 'My location'),
          ),
        );
      }
    }

    final bool isTracking = widget.geofenceService?.activeTargetId != null;
    final String? statusText = _currentPosition == null
        ? 'Finding your location…'
        : (isTracking ? 'Tracking your arrival' : null);

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: isDark ? const Color(0xFF121212) : Colors.white,
        ),
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              onCameraMoveStarted: () {
                // Stop auto-following when user manually moves the map
                if (_shouldFollowUser) {
                  setState(() {
                    _shouldFollowUser = false;
                  });
                }
                if (_searchController.isOpen) {
                  _searchController.closeView('');
                }
              },
              initialCameraPosition: const CameraPosition(
                target: LatLng(10.18, 122.96),
                zoom: 10.0,
              ),
              style: isDark ? _darkMapStyle : _lightMapStyle,
              markers: markers,
              circles: circles,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              padding: EdgeInsets.only(top: topPad + 70),
            ),

            // Top row: back (when focused) · search · refresh
            Positioned(
              top: topPad + 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  if (selectedBreeder != null) ...[
                    _roundButton(
                      icon: Icons.arrow_back_rounded,
                      isDark: isDark,
                      tooltip: 'Back',
                      onTap: () => navProvider.clearSelectedBreeder(),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: _buildSearchBar(breeders, isDark)),
                  if (selectedBreeder == null) ...[
                    const SizedBox(width: 10),
                    breederProvider.isLoading
                        ? Container(
                      width: 48,
                      height: 48,
                      decoration: _floatingDecoration(isDark, radius: 24),
                      padding: const EdgeInsets.all(14),
                      child: const CircularProgressIndicator(
                          color: _green, strokeWidth: 2),
                    )
                        : _roundButton(
                      icon: Icons.refresh_rounded,
                      isDark: isDark,
                      tooltip: 'Refresh',
                      onTap: () => breederProvider.fetchBreeders(),
                    ),
                  ],
                ],
              ),
            ),

            // Status chip / offline notice, stacked under the search row
            Positioned(
              top: topPad + 70,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if (_isOffline) _buildOfflineBanner(),
                  if (statusText != null && selectedBreeder == null) ...[
                    if (_isOffline) const SizedBox(height: 8),
                    _buildStatusChip(statusText, isDark),
                  ],
                ],
              ),
            ),

            // Focused-listing card
            if (selectedBreeder != null)
              Positioned(
                bottom: 24,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _floatingDecoration(isDark, radius: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedBreeder.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('Showing this location only',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () => navProvider.clearSelectedBreeder(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Show all breeders',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),

            // Pin-your-business prompt
            if (needsLocationSetup && selectedBreeder == null)
              Positioned(
                bottom: 96,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _floatingDecoration(isDark, radius: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, color: _green, size: 22),
                          const SizedBox(width: 8),
                          Text('Pin your business',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : Colors.black87)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You\'re registered but not on the map yet. Pin your current location so buyers can find you.',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: _isOffline
                            ? null
                            : () async {
                          LatLng? targetPos = _currentPosition;
                          targetPos ??= await _determinePosition(triggerGeofence: true);

                          if (targetPos != null) {
                            try {
                              await breederProvider.updateBusinessLocation(targetPos);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Business location pinned.')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to pin location: $e')),
                                );
                              }
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(_isOffline ? 'Offline — reconnect to pin' : 'Pin my business here',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: selectedBreeder == null
          ? Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FloatingActionButton(
          onPressed: () {
            setState(() {
              _shouldFollowUser = true;
            });
            _determinePosition(triggerGeofence: true);
          },
          backgroundColor: isDark ? _surfaceDark : _surfaceLight,
          foregroundColor: _green,
          elevation: 3,
          shape: const CircleBorder(),
          child: Icon(_shouldFollowUser ? Icons.my_location_rounded : Icons.location_searching_rounded),
        ),
      )
          : null,
    );
  }

  Widget _buildStatusChip(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: _floatingDecoration(isDark),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: _green, size: 8),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 16),
          SizedBox(width: 8),
          Text(
            'No internet connection',
            style: TextStyle(
                color: Color(0xFF991B1B), fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ─── Breeder details sheet ────────────────────────────────────────────────

  Future<void> _onArrivalPressed(
      BuildContext sheetContext, Breeder breeder, bool isTarget) async {
    if (Provider.of<AuthProvider>(sheetContext, listen: false).isGuest) {
      RestrictedAccessDialog.show(sheetContext, 'use arrival tracking');
      return;
    }
    final service = widget.geofenceService;
    if (service == null) return;

    final messenger = ScaffoldMessenger.of(sheetContext);
    final navigator = Navigator.of(sheetContext);

    if (isTarget) {
      service.setActiveTarget(null);
      if (mounted) setState(() {});
      navigator.pop();
      _showSnack(messenger,
          icon: Icons.location_off_rounded,
          title: 'Arrival tracking cancelled',
          color: Colors.red[700]!);
    } else {
      // Clear any active target so geofencing stays inactive while pending
      service.setActiveTarget(null);
      try {
        await service.recordManualArrival(
          visitorId: _currentUserData?['id'] ?? '',
          visitorName: _currentUserData?['full_name'] ?? 'A user',
          visitorRole: _currentUserData?['role'] ?? 'Breeder',
          hostId: breeder.userId,
          hostName: breeder.name,
        );
      } catch (e) {
        debugPrint('Error sending arrival request: $e');
      }

      if (mounted) setState(() {});
      navigator.pop();
      _showSnack(messenger,
          icon: Icons.send_rounded,
          title: 'Arrival request sent',
          subtitle: 'Waiting for ${breeder.name} to accept.');
    }
  }

  void _showBreederDetails(BuildContext context, Breeder breeder, bool isDark) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isOwnListing = breeder.userId == currentUserId;
    final chipColor = isDark ? _chipDark : _chipLight;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? _surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: sheetContext,
                            builder: (dialogContext) => GestureDetector(
                              onTap: () => Navigator.pop(dialogContext),
                              child: Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: EdgeInsets.zero,
                                child: InteractiveViewer(
                                  child: breeder.imageUrl.isNotEmpty
                                      ? Image.network(breeder.imageUrl, fit: BoxFit.contain)
                                      : Container(
                                      color: Colors.white,
                                      child: const Icon(Icons.person, size: 100)),
                                ),
                              ),
                            ),
                          );
                        },
                        child: CircleAvatar(
                          radius: 32,
                          backgroundImage:
                          breeder.imageUrl.isNotEmpty ? NetworkImage(breeder.imageUrl) : null,
                          backgroundColor: chipColor,
                          child: breeder.imageUrl.isEmpty
                              ? Icon(Icons.person_rounded, size: 32, color: Colors.grey[500])
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              breeder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _sheetChip(
                                  breeder.role,
                                  _roleColor(breeder.role).withValues(alpha: 0.12),
                                  _roleColor(breeder.role),
                                ),
                                if (breeder.category.isNotEmpty)
                                  _sheetChip(breeder.category, chipColor,
                                      isDark ? Colors.grey[400]! : Colors.grey[700]!),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (breeder.animals.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sheetHeading('Animals', isDark),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.pets_rounded, size: 16, color: _green),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            breeder.animals
                                .map((a) => a.name.isNotEmpty && a.name != 'Animal'
                                ? a.name
                                : (a.breed.isNotEmpty ? a.breed : 'Animal'))
                                .toSet()
                                .join(', '),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  _sheetHeading('Details', isDark),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.phone_outlined, 'Contact', breeder.contactNumber),
                  if (breeder.age.isNotEmpty)
                    _buildDetailRow(Icons.cake_outlined, 'Age', breeder.age),
                  if (breeder.address.isNotEmpty)
                    _buildDetailRow(Icons.location_on_outlined, 'Address', breeder.address),
                  const SizedBox(height: 20),
                  if (isOwnListing)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Close'),
                      ),
                    )
                  else
                    Builder(builder: (_) {
                      final bool isTarget =
                          widget.geofenceService?.activeTargetId == breeder.id;
                      final Color arriveColor = isTarget ? Colors.red[700]! : _green;
                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _onArrivalPressed(sheetContext, breeder, isTarget),
                              icon: Icon(
                                  isTarget
                                      ? Icons.location_off_outlined
                                      : Icons.directions_walk_rounded,
                                  size: 18),
                              label: Text(isTarget ? 'Cancel arrival' : 'Arrive here'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: arriveColor,
                                side: BorderSide(color: arriveColor.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (Provider.of<AuthProvider>(sheetContext, listen: false)
                                    .isGuest) {
                                  RestrictedAccessDialog.show(
                                      sheetContext, 'chat with breeders and traders');
                                  return;
                                }
                                final navigator = Navigator.of(sheetContext);
                                navigator.pop();
                                navigator.push(
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                      breederId: breeder.userId,
                                      breederName: breeder.name,
                                      breederAvatarUrl: breeder.imageUrl,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                              label: const Text('Contact'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheetChip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11.5)),
    );
  }

  Widget _sheetHeading(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      color: isDark ? Colors.white : Colors.black87,
    ),
  );

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'N/A',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Reviews (currently not wired into the UI; kept as-is) ────────────────

  String _maskUserName(String fullName) {
    if (fullName.isEmpty) return 'Anonymous';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.map((part) {
      if (part.isEmpty) return '';
      if (part.length <= 1) return '${part[0]}*';
      final firstChar = part[0];
      int starCount = part.length > 4 ? 3 : 2;
      return '$firstChar${'*' * starCount}';
    }).join(' ');
  }

  Widget _buildReviewItem(BuildContext context, Review review, String listingOwnerId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = _supabase.auth.currentUser?.id;
    final isListingOwner = currentUserId == listingOwnerId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? _chipDark : _chipLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _maskUserName(review.userName),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                    5,
                        (index) => Icon(
                      index < review.rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 12,
                    )),
              ),
              const SizedBox(width: 8),
              Text(
                TimeUtils.getTimeAgo(review.createdAt),
                style: TextStyle(color: Colors.grey[500], fontSize: 10),
              ),
              if (currentUserId == review.userId) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete review',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Delete review'),
                        content: const Text('Are you sure you want to delete your review?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      if (!context.mounted) return;
                      try {
                        await Provider.of<BreederProvider>(context, listen: false)
                            .deleteReview(reviewId: review.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Review deleted')));
                        setState(() {});
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(review.comment,
              style: TextStyle(
                  fontSize: 12.5, color: isDark ? Colors.grey[400] : Colors.grey[700])),
          if (review.reviewPhotos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: review.reviewPhotos.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _showFullScreenImage(context, review.reviewPhotos[index]),
                    child: Container(
                      width: 60,
                      margin: const EdgeInsets.only(right: 6),
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Owner reply',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w600, color: _green)),
                  const SizedBox(height: 2),
                  Text(
                    review.replyComment!,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[300] : Colors.grey[800]),
                  ),
                ],
              ),
            ),
          ] else if (isListingOwner) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showReplyDialog(context, review.id),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                child: const Text('Reply', style: TextStyle(fontSize: 12, color: _green)),
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? _surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reply to review',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        content: TextField(
          controller: replyController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Write your reply',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (replyController.text.trim().isEmpty) return;
              await Provider.of<BreederProvider>(context, listen: false).replyToReview(
                reviewId: reviewId,
                replyComment: replyController.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white, elevation: 0),
            child: const Text('Send reply'),
          ),
        ],
      ),
    );
  }

  void _showAddReviewDialog(BuildContext context, Breeder breeder) {
    double rating = 5;
    final commentController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<File> selectedImages = [];
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? _surfaceDark : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Write a review', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        5,
                            (index) => IconButton(
                          icon: Icon(
                            index < rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: Colors.amber,
                            size: 30,
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () => setDialogState(() => rating = index + 1.0),
                        )),
                  ),
                ),
                TextField(
                  controller: commentController,
                  maxLines: 2,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    hintText: 'Share your experience',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      GestureDetector(
                        onTap: isSubmitting
                            ? null
                            : () async {
                          final picker = ImagePicker();
                          final XFile? image =
                          await picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            setDialogState(() {
                              selectedImages.add(File(image.path));
                            });
                          }
                        },
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            color: isDark ? _chipDark : _chipLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined, color: _green, size: 20),
                        ),
                      ),
                      ...selectedImages.asMap().entries.map((entry) {
                        int index = entry.key;
                        File file = entry.value;
                        return Stack(
                          children: [
                            Container(
                              width: 60,
                              margin: const EdgeInsets.only(left: 6),
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
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () =>
                                      setDialogState(() => selectedImages.removeAt(index)),
                                  child: Container(
                                    padding: const EdgeInsets.all(1),
                                    decoration: const BoxDecoration(
                                        color: Colors.red, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 10),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                if (commentController.text.isEmpty) return;

                setDialogState(() {
                  isSubmitting = true;
                });

                try {
                  await Provider.of<BreederProvider>(context, listen: false).addReview(
                    listingId: breeder.id,
                    rating: rating,
                    comment: commentController.text,
                    photoPaths: selectedImages.map((e) => e.path).toList(),
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
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white, elevation: 0),
              child: isSubmitting
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Post review'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewSuccessDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? _surfaceDark : Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: _green, size: 36),
              ),
              const SizedBox(height: 20),
              const Text('Review posted',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(
                'Thanks for sharing your experience.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  Widget _buildSearchBar(List<Breeder> allBreeders, bool isDark) {
    return SearchAnchor(
      searchController: _searchController,
      builder: (BuildContext context, SearchController controller) {
        return SearchBar(
          controller: controller,
          hintText: 'Search breeders or breeds',
          hintStyle: WidgetStateProperty.all(
            TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 14.5),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 16.0),
          ),
          constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
          onTap: () {
            controller.openView();
          },
          onChanged: (_) {
            controller.openView();
          },
          leading: const Icon(Icons.search_rounded, color: _green),
          trailing: [
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  controller.clear();
                },
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
          ],
          backgroundColor: WidgetStateProperty.all(isDark ? _surfaceDark : _surfaceLight),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shadowColor: WidgetStateProperty.all(Colors.black.withValues(alpha: 0.35)),
          elevation: WidgetStateProperty.all(4),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        );
      },
      suggestionsBuilder: (BuildContext context, SearchController controller) {
        final String query = controller.text.toLowerCase();
        final List<Breeder> results = allBreeders.where((breeder) {
          // Only search for breeders who have at least one active animal listing
          return (breeder.name.toLowerCase().contains(query) ||
              breeder.breed.toLowerCase().contains(query) ||
              breeder.category.toLowerCase().contains(query)) &&
              breeder.animals.isNotEmpty;
        }).toList();

        if (results.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text('No breeders or breeds found.',
                    style: TextStyle(color: Colors.grey[600])),
              ),
            )
          ];
        }

        return results.map((breeder) {
          return ListTile(
            leading: CircleAvatar(
              backgroundImage:
              breeder.imageUrl.isNotEmpty ? NetworkImage(breeder.imageUrl) : null,
              child: breeder.imageUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(breeder.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${breeder.role} • ${breeder.breed}'),
            trailing: Text(
              breeder.category,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            onTap: () {
              controller.closeView(breeder.name);
              _navigateToBreeder(breeder);
            },
          );
        }).toList();
      },
    );
  }

  void _navigateToBreeder(Breeder breeder) {
    if (mapController == null) return;

    setState(() {
      _shouldFollowUser = false;
    });

    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: breeder.location, zoom: 16),
      ),
    );

    // Show details modal
    _showBreederDetails(context, breeder, Theme.of(context).brightness == Brightness.dark);
  }
}