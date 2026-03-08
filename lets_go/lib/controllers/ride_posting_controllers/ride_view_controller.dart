import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';
import '../../utils/road_polyline_service.dart';

class RideViewController {
  // Route data
  List<LatLng> points = [];
  List<String> locationNames = [];
  List<LatLng> routePoints = [];
  LatLng? currentPosition;
  String? createdRouteId;
  double? routeDistance;
  int? routeDuration;

  // Ride details
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();
  int totalSeats = 4;
  String? genderPreference;
  String? selectedVehicle;
  String description = '';

  // Callbacks
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function(String)? onInfo;

  RideViewController({
    this.onStateChanged,
    this.onError,
    this.onSuccess,
    this.onInfo,
  });

  void initializeWithRideData(Map<String, dynamic> rideData) {
    try {
      debugPrint('[VIEW_CTRL] init: keys=${rideData.keys.toList()}');
      // Pull stops from various possible shapes
      final route = rideData['route'] as Map<String, dynamic>?;
      final List<dynamic>? stops = (rideData['route_coordinates'] as List<dynamic>?)
          ?? (rideData['route_stops'] as List<dynamic>?)
          ?? (rideData['stops'] as List<dynamic>?)
          ?? (route?['route_stops'] as List<dynamic>?)
          ?? (route?['stops'] as List<dynamic>?);

      points.clear();
      locationNames.clear();
      routePoints.clear();
      if (stops != null) {
        debugPrint('[VIEW_CTRL] parsing stops list, len=${stops.length}');
        for (final raw in stops) {
          final stop = raw as Map<String, dynamic>;
          final lat = (stop['latitude'] as num?)?.toDouble() ?? (stop['lat'] as num?)?.toDouble();
          final lng = (stop['longitude'] as num?)?.toDouble() ?? (stop['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) points.add(LatLng(lat, lng));
          final name = stop['name'] ?? stop['stop_name'] ?? stop['address'] ?? 'Stop';
          locationNames.add(name.toString());
        }
      }

      // Prefer: ALWAYS rebuild from stop_breakdown when present so map reflects latest edited route
      try {
        List<dynamic>? sb;
        final fc = rideData['fare_calculation'];
        if (fc is Map && fc['stop_breakdown'] is List && (fc['stop_breakdown'] as List).isNotEmpty) {
          sb = List<dynamic>.from(fc['stop_breakdown']);
        } else if (rideData['stop_breakdown'] is List && (rideData['stop_breakdown'] as List).isNotEmpty) {
          sb = List<dynamic>.from(rideData['stop_breakdown']);
        }
        final segments = sb ?? [];
        if (segments.isNotEmpty) {
          debugPrint('[VIEW_CTRL] using stop_breakdown for map (forced). parsedStops=${points.length} segments=${segments.length}');
          final List<LatLng> rebuilt = [];
          final List<String> names = [];
          for (int i = 0; i < segments.length; i++) {
            final m = segments[i] as Map<String, dynamic>;
            final from = m['from_coordinates'] as Map<String, dynamic>?;
            final to = m['to_coordinates'] as Map<String, dynamic>?;
            final fromLat = (from?['lat'] as num?)?.toDouble();
            final fromLng = (from?['lng'] as num?)?.toDouble();
            final toLat = (to?['lat'] as num?)?.toDouble();
            final toLng = (to?['lng'] as num?)?.toDouble();
            debugPrint('[VIEW_CTRL][SEG ${i+1}] from=($fromLat,$fromLng) to=($toLat,$toLng) names=(${m['from_stop_name']} -> ${m['to_stop_name']})');
            if (i == 0) {
              if (fromLat != null && fromLng != null) {
                rebuilt.add(LatLng(fromLat, fromLng));
                names.add((m['from_stop_name'] ?? 'Stop 1').toString());
              } else if (toLat != null && toLng != null) {
                // Fallback: seed with first segment's 'to' if 'from' missing
                rebuilt.add(LatLng(toLat, toLng));
                names.add((m['from_stop_name'] ?? 'Stop 1').toString());
                debugPrint('[VIEW_CTRL] seeded first point from TO due to missing FROM');
              }
            }
            if (toLat != null && toLng != null) {
              rebuilt.add(LatLng(toLat, toLng));
              names.add((m['to_stop_name'] ?? 'Stop ${i + 2}').toString());
            }
          }
          // If we only collected segments points (N), try to prepend first FROM to reach N+1
          if (rebuilt.length == segments.length) {
            try {
              final m0 = segments.first as Map<String, dynamic>;
              final f0 = m0['from_coordinates'] as Map<String, dynamic>?;
              final fLat = (f0?['lat'] as num?)?.toDouble();
              final fLng = (f0?['lng'] as num?)?.toDouble();
              if (fLat != null && fLng != null) {
                rebuilt.insert(0, LatLng(fLat, fLng));
                names.insert(0, (m0['from_stop_name'] ?? 'Stop 1').toString());
                debugPrint('[VIEW_CTRL] prepended first FROM to reach segments+1 points');
              }
            } catch (_) {}
          }
          if (rebuilt.length >= 2) {
            points = rebuilt;
            locationNames = names;
            debugPrint('[VIEW_CTRL] points set from breakdown: ${points.length} names=${locationNames.length}');
          } else {
            debugPrint('[VIEW_CTRL] rebuild from breakdown failed, keeping parsed stops');
            // If breakdown exists but coords missing, fetch full trip details to get coords
            try {
              final tripId = (rideData['trip_id'] ?? rideData['id'] ?? '').toString();
              if (tripId.isNotEmpty) {
                debugPrint('[VIEW_CTRL] fetching detailed trip to get coordinates for breakdown...');
                ApiService.getRideBookingDetails(tripId).then((res) {
                  final trip = (res['trip'] is Map)
                      ? Map<String, dynamic>.from(res['trip'])
                      : Map<String, dynamic>.from(res);
                  final sb = trip['stop_breakdown'] is List
                      ? List<dynamic>.from(trip['stop_breakdown'])
                      : (res['stop_breakdown'] is List
                          ? List<dynamic>.from(res['stop_breakdown'])
                          : <dynamic>[]);
                  if (sb.isNotEmpty) {
                    debugPrint('[VIEW_CTRL] detailed trip received with stop_breakdown, rebuilding map');
                    initializeWithRideData({
                      ...rideData,
                      'stop_breakdown': sb,
                      'route': trip['route'] ?? rideData['route'],
                      'fare_calculation': trip['fare_calculation'] ?? rideData['fare_calculation'],
                    });
                  }
                });
              }
            } catch (_) {}
          }
        }
      } catch (_) {
        // ignore
      }

      createdRouteId = route?['id']?.toString();
      routeDistance = (route?['total_distance_km'] as num?)?.toDouble();
      routeDuration = (route?['estimated_duration_minutes'] as num?)?.toInt();

      if (rideData['trip_date'] != null) {
        selectedDate = DateTime.parse(rideData['trip_date']);
      }
      if (rideData['departure_time'] != null) {
        final parts = rideData['departure_time'].toString().split(':');
        selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }

      debugPrint('[VIEW_CTRL] final points=${points.length} names=${locationNames.length}');
      // Build polyline
      fetchRoutePoints();
      onStateChanged?.call();
    } catch (e) {
      onError?.call('Failed to load ride: $e');
    }
  }

  Future<void> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      currentPosition = LatLng(pos.latitude, pos.longitude);
      onStateChanged?.call();
    } catch (_) {}
  }

  Future<void> fetchRoutePoints() async {
    if (points.length < 2) {
      routePoints = List<LatLng>.from(points);
      onStateChanged?.call();
      return;
    }
    try {
      routePoints = await RoadPolylineService.fetchRoadPolyline(points);
      if (routePoints.length < 2) {
        routePoints = List<LatLng>.from(points);
      }
    } catch (_) {
      routePoints = List<LatLng>.from(points);
    }
    onStateChanged?.call();
  }

  Future<void> cancelRide(String tripId, {String? reason}) async {
    try {
      final res = await ApiService.cancelTrip(tripId, reason: reason ?? 'Cancelled by driver');
      if (res['success'] == true) {
        onSuccess?.call('Ride cancelled successfully');
      } else {
        onError?.call('Failed to cancel ride');
      }
    } catch (e) {
      onError?.call('Error cancelling ride: $e');
    }
  }
}
