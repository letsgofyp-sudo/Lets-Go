import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
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

  RideDetailsViewController({
    this.onStateChanged,
    this.onError,
    this.onInfo,
  });

  // Load ride details from API
  Future<void> loadRideDetails(String tripId) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final data = await ApiService.getRideBookingDetails(tripId);
      
      if (data['success'] == true) {
        rideData = data;
        
        // Extract route information
        if (data['route'] != null) {
          final route = data['route'] as Map<String, dynamic>;
          routeDistance = route['total_distance_km']?.toDouble();
          routeDuration = route['estimated_duration_minutes']?.toInt();
          
          // Extract stops and coordinates
          if (route['stops'] != null) {
            final stops = route['stops'] as List<dynamic>;
            locationNames.clear();
            routePoints.clear();
            stopPoints.clear();
            final List<LatLng> stopCoords = [];
            
            for (final stop in stops) {
              locationNames.add(stop['name'] ?? 'Unknown Stop');
              if (stop['latitude'] != null && stop['longitude'] != null) {
                final p = LatLng(
                  (stop['latitude'] as num).toDouble(),
                  (stop['longitude'] as num).toDouble(),
                );
                routePoints.add(p);
                stopPoints.add(p);
                stopCoords.add(p);
              }
            }
            
            // Try to fetch a road-following polyline; fallback to interpolation on failure
            if (stopCoords.length > 1) {
              final road = await RoadPolylineService.fetchRoadPolyline(stopCoords);
              routePoints = (road.length > 1) ? road : _generateInterpolatedRoute(stopCoords);
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
