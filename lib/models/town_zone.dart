import 'package:google_maps_flutter/google_maps_flutter.dart';

class TownZone {
  final String name;
  final LatLng center;
  final double radius; // Still useful for some quick checks
  final List<LatLng> boundary; // Required for polygon geofencing

  TownZone({
    required this.name,
    required this.center,
    this.radius = 0,
    required this.boundary,
  });
}
