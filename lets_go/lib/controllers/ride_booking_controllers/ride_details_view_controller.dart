import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../utils/road_polyline_service.dart';
import '../../services/api_service.dart';
import '../../utils/map_util.dart';

class RideDetailsViewController {
  // Ride data
  Map<String, dynamic> rideData = {};
  bool isLoading = true;
  String? errorMessage;

  // Route data
  List<LatLng> routePoints = [];
  List<String> locationNames = [];
  List<LatLng> stopPoints = [];
  double? routeDistance;
  int? routeDuration;

  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onInfo;

  RideDetailsViewController({this.onStateChanged, this.onError, this.onInfo});

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  List<LatLng> _parsePolyline(dynamic raw) {
    dynamic normalized = raw;
    if (normalized is String) {
      try {
        normalized = json.decode(normalized);
      } catch (_) {
        normalized = null;
      }
    }
    if (normalized is! List) return <LatLng>[];
    final out = <LatLng>[];
    for (final p in normalized) {
      if (p is! Map) continue;
      final lat = _toDouble(p['lat'] ?? p['latitude']);
      final lng = _toDouble(p['lng'] ?? p['longitude']);
      if (lat != null && lng != null) out.add(LatLng(lat, lng));
    }
    return out;
  }

  // Load ride details from API
  Future<void> loadRideDetails(String tripId) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(await ApiService.getRideBookingDetails(tripId));

      // ApiService responses are not consistent: some endpoints return
      // `{success:true, ...}`, while others return the payload directly.
      // Treat a missing `success` field as a successful payload.
      final bool ok = data['success'] == null || data['success'] == true;

      if (ok) {
        rideData = data;

        // Extract route information
        if (data['route'] != null) {
          final route = Map<String, dynamic>.from(data['route'] as Map);
          routeDistance = route['total_distance_km']?.toDouble();
          routeDuration = route['estimated_duration_minutes']?.toInt();

          // Extract stops and coordinates
          if (route['stops'] != null) {
            final stops = List<dynamic>.from(route['stops'] as List);
            locationNames.clear();
            routePoints.clear();
            stopPoints.clear();
            final List<LatLng> stopCoords = [];

            // Prefer backend geometry if present (authoritative line).
            final backendRoutePoints = _parsePolyline(
              data['route_points'] ??
                  data['trip']?['route_points'] ??
                  data['trip']?['route']?['route_points'] ??
                  route['route_points'],
            );
            final backendActualPath = _parsePolyline(
              data['actual_path'] ??
                  data['trip']?['actual_path'] ??
                  data['trip']?['route']?['actual_path'] ??
                  route['actual_path'],
            );
            // Prefer `route_points` because it may contain the hybrid/selected geometry.
            // Fall back to `actual_path` only when route_points is missing.
            final preferred = backendRoutePoints.length >= 2
                ? backendRoutePoints
                : (backendActualPath.length >= 2
                      ? backendActualPath
                      : <LatLng>[]);
            if (preferred.length >= 2) {
              routePoints = List<LatLng>.from(preferred);
            }

            for (final stop in stops) {
              locationNames.add(stop['name'] ?? 'Unknown Stop');
              if (stop['latitude'] != null && stop['longitude'] != null) {
                final p = LatLng(
                  (stop['latitude'] as num).toDouble(),
                  (stop['longitude'] as num).toDouble(),
                );
                stopPoints.add(p);
                stopCoords.add(p);
              }
            }

            // Try to fetch a road-following polyline; fallback to interpolation on failure
            if (routePoints.length < 2 && stopCoords.length > 1) {
              final road = await RoadPolylineService.fetchRoadPolyline(
                stopCoords,
              );
              routePoints = (road.length > 1)
                  ? road
                  : _generateInterpolatedRoute(stopCoords);
            }
          }
        }

        setState(() {
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = data['error'] ?? 'Failed to load ride details';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading ride details: $e';
        isLoading = false;
      });
    }
  }

  // Helper method to set state
  void setState(VoidCallback fn) {
    fn();
    onStateChanged?.call();
  }

  // Get trip status color
  Color getTripStatusColor() {
    final status = rideData['trip']?['trip_status'] ?? 'SCHEDULED';
    switch (status) {
      case 'SCHEDULED':
        return Colors.blue;
      case 'IN_PROGRESS':
        return Colors.orange;
      case 'COMPLETED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Get trip status text
  String getTripStatusText() {
    final status = rideData['trip']?['trip_status'] ?? 'SCHEDULED';
    switch (status) {
      case 'SCHEDULED':
        return 'Scheduled';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  // Get formatted trip date
  String getFormattedTripDate() {
    final date = rideData['trip']?['trip_date'];
    if (date != null) {
      try {
        final dateTime = DateTime.parse(date);
        return DateFormat('MMM dd, yyyy').format(dateTime);
      } catch (e) {
        return 'Invalid Date';
      }
    }
    return 'N/A';
  }

  // Get formatted departure time
  String getFormattedDepartureTime() {
    final time = rideData['trip']?['departure_time'];
    if (time != null) {
      try {
        final timeParts = time.split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
      } catch (e) {
        return 'Invalid Time';
      }
    }
    return 'N/A';
  }

  // Get trip information
  Map<String, dynamic> getTripInfo() {
    return rideData['trip'] ?? {};
  }

  // Get driver information
  Map<String, dynamic> getDriverInfo() {
    return rideData['driver'] ?? {};
  }

  // Get vehicle information
  Map<String, dynamic> getVehicleInfo() {
    return rideData['vehicle'] ?? {};
  }

  // Get gender preference text
  String getGenderPreferenceText() {
    final preference = rideData['trip']?['gender_preference'] ?? 'Any';
    switch (preference) {
      case 'Male':
        return 'Male Only';
      case 'Female':
        return 'Female Only';
      case 'Any':
        return 'Any Gender';
      default:
        return 'N/A';
    }
  }

  // Get passengers information
  List<Map<String, dynamic>> getPassengersInfo() {
    final passengers = rideData['passengers'] ?? [];
    return List<Map<String, dynamic>>.from(passengers);
  }

  // Check if ride is bookable
  bool isRideBookable() {
    final trip = rideData['trip'];
    if (trip == null) return false;

    final status = trip['trip_status'];
    final availableSeats = trip['available_seats'] ?? 0;

    return status == 'SCHEDULED' && availableSeats > 0;
  }

  // Generate interpolated route points for more realistic visualization
  List<LatLng> _generateInterpolatedRoute(List<LatLng> stops) {
    if (stops.length >= 2) {
      _calculateDistance(stops.first, stops.last);
    }
    return MapUtil.generateInterpolatedRoute(stops);
  }

  // Get route points for display (already road-following if ORS succeeded)
  List<LatLng> getInterpolatedRoutePoints() {
    return routePoints;
  }

  // Calculate distance between two points using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    return MapUtil.calculateDistanceMeters(point1, point2);
  }

  // Dispose resources
  void dispose() {
    // Clean up any resources if needed
  }
}
