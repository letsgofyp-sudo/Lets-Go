import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../services/api_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/road_polyline_service.dart';
import '../../utils/map_util.dart';

class RideBookingDetailsController {
  // Ride data
  Map<String, dynamic> rideData = {};
  bool isLoading = true;
  String? errorMessage;

  // Booking form data
  int selectedFromStop = 1;
  int selectedToStop = 2;
  int numberOfSeats = 1;
  String specialRequests = '';
  bool isBookingInProgress = false;

  // Route data
  List<LatLng> routePoints = [];
  List<String> locationNames = [];
  List<LatLng> stopPoints = [];
  double? routeDistance;
  int? routeDuration;
  int selectedRouteDuration = 0;

  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function(String)? onInfo;

  RideBookingDetailsController({
    this.onStateChanged,
    this.onError,
    this.onSuccess,
    this.onInfo,
  });

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
      final lat = (p['lat'] ?? p['latitude']);
      final lng = (p['lng'] ?? p['longitude']);
      final dLat = lat is num
          ? lat.toDouble()
          : double.tryParse(lat?.toString() ?? '');
      final dLng = lng is num
          ? lng.toDouble()
          : double.tryParse(lng?.toString() ?? '');
      if (dLat != null && dLng != null) {
        out.add(LatLng(dLat, dLng));
      }
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

      final Map<String, dynamic> data = Map<String, dynamic>.from(
        await ApiService.getRideBookingDetails(tripId),
      );
      debugPrint(
        'DEBUG: RideBookingDetailsController - API response keys: ${data.keys.toList()}',
      );
      debugPrint(
        'DEBUG: RideBookingDetailsController - trip data: ${data['trip']}',
      );
      if (data['trip'] != null) {
        debugPrint(
          'DEBUG: RideBookingDetailsController - base_fare from API: ${data['trip']['base_fare']}',
        );
        debugPrint(
          'DEBUG: RideBookingDetailsController - is_negotiable from API: ${data['trip']['is_negotiable']}',
        );
      }

      final bool ok = data['success'] == null || data['success'] == true;
      if (ok) {
        rideData = data;
        debugPrint(
          'DEBUG: RideBookingDetailsController - rideData stored successfully',
        );

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
                stopPoints.add(p);
                stopCoords.add(p);
              }
            }

            // Set default from/to stops
            if (locationNames.length >= 2) {
              selectedFromStop = 1;
              selectedToStop = locationNames.length;
            }

            // Try to fetch a road-following polyline; fallback to interpolation on failure
            final backendRoutePoints = _parsePolyline(
              data['route_points'] ??
                  data['trip']?['route_points'] ??
                  data['trip']?['route']?['route_points'] ??
                  data['route']?['route_points'],
            );
            final backendActualPath = _parsePolyline(
              data['actual_path'] ??
                  data['trip']?['actual_path'] ??
                  data['trip']?['route']?['actual_path'] ??
                  data['route']?['actual_path'],
            );
            if (backendRoutePoints.length >= 2) {
              routePoints = backendRoutePoints;
            } else if (backendActualPath.length >= 2) {
              routePoints = backendActualPath;
            } else if (stopCoords.length > 1) {
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

  // Update selected from stop
  void updateFromStop(int stopOrder) {
    selectedFromStop = stopOrder;
    // Ensure to_stop is after from_stop
    if (selectedToStop <= selectedFromStop) {
      selectedToStop = selectedFromStop + 1;
    }
    _recalculateFareAsync();
    onStateChanged?.call();
  }

  // Update to stop
  void updateToStop(int stopOrder) {
    selectedToStop = stopOrder;
    _recalculateFareAsync();
    onStateChanged?.call();
  }

  // Recalculate fare asynchronously using backend API
  Future<void> _recalculateFareAsync() async {
    if (rideData.isEmpty || rideData['trip']?['id'] == null) return;

    try {
      final tripId = rideData['trip']['id'];
      final response = await BookingService.calculateDynamicFare(
        tripId: tripId,
        fromStopOrder: selectedFromStop,
        toStopOrder: selectedToStop,
        numberOfSeats: numberOfSeats,
      );

      if (response['success'] == true) {
        // Store dynamic fare result in trip data
        rideData['trip']['dynamic_fare'] = response['fare_calculation'];

        // Update duration if available
        final durationMinutes =
            response['fare_calculation']['total_duration_minutes'] as int?;
        if (durationMinutes != null) {
          selectedRouteDuration = durationMinutes;
          debugPrint(
            'Dynamic fare and duration recalculated: ${response['fare_calculation']['total_fare']} for stops $selectedFromStop-$selectedToStop, seats: $numberOfSeats, duration: ${durationMinutes}min',
          );
        } else {
          debugPrint(
            'Dynamic fare recalculated: ${response['fare_calculation']['total_fare']} for stops $selectedFromStop-$selectedToStop, seats: $numberOfSeats (no duration data)',
          );
        }

        // Trigger UI update
        onStateChanged?.call();
      } else {
        debugPrint('Dynamic fare calculation failed: ${response['message']}');
      }
    } catch (e) {
      debugPrint('Error recalculating fare: $e');
    }
  }

  // Update number of seats and recalculate fare
  void updateSeats(int seats) {
    numberOfSeats = seats;
    _recalculateFareAsync();
    onStateChanged?.call();
  }

  // Update special requests
  void updateSpecialRequests(String requests) {
    specialRequests = requests;
    onStateChanged?.call();
  }

  // Get available stops for selection
  List<Map<String, dynamic>> getAvailableStops() {
    if (locationNames.isEmpty) return [];

    return locationNames.asMap().entries.map((entry) {
      final index = entry.key;
      final name = entry.value;
      return {
        'order': index + 1,
        'name': name,
        'display_name': '${index + 1}. $name',
      };
    }).toList();
  }

  // Get from stop options (all stops except last)
  List<Map<String, dynamic>> getFromStopOptions() {
    final stops = getAvailableStops();
    if (stops.length <= 1) return [];
    return stops.take(stops.length - 1).toList();
  }

  // Get to stop options (all stops after from_stop)
  List<Map<String, dynamic>> getToStopOptions() {
    final stops = getAvailableStops();
    if (stops.length <= 1) return [];
    return stops.where((stop) => stop['order'] > selectedFromStop).toList();
  }

  // Calculate total fare for selected route
  double calculateTotalFare() {
    if (rideData.isEmpty) return 0.0;

    // Check if we have dynamic fare calculation result
    final dynamicFare = rideData['trip']?['dynamic_fare'];
    if (dynamicFare != null) {
      final totalFare = (dynamicFare['total_fare'] as num?)?.toDouble() ?? 0.0;
      debugPrint(
        'Using dynamic fare: $totalFare for stops $selectedFromStop-$selectedToStop, seats: $numberOfSeats',
      );
      return totalFare;
    }

    // Check if we have stop breakdown for manual calculation
    final fareCalculation = rideData['trip']?['fare_calculation'];
    List<dynamic>? stopBreakdownData = fareCalculation?['stop_breakdown'];

    if (stopBreakdownData != null && stopBreakdownData.isNotEmpty) {
      // Calculate fare manually for selected stops
      double totalFare = 0.0;

      for (var stop in stopBreakdownData) {
        int fromStop = stop['from_stop'] ?? 0;
        int toStop = stop['to_stop'] ?? 0;

        // Include stops within the selected range
        if (fromStop >= selectedFromStop && toStop <= selectedToStop) {
          totalFare += (stop['price'] ?? 0.0).toDouble();
        }
      }

      // Apply bulk discount if available
      double bulkDiscountPercentage =
          fareCalculation?['bulk_discount_percentage'] ?? 0.0;
      double discountAmount = totalFare * (bulkDiscountPercentage / 100);
      double discountedFare = totalFare - discountAmount;

      // Calculate total for multiple seats
      double finalFare = discountedFare * numberOfSeats;

      debugPrint(
        'Manual fare calculated: $finalFare for stops $selectedFromStop-$selectedToStop, seats: $numberOfSeats',
      );
      return finalFare;
    }

    // Fallback to base fare calculation
    final baseFare =
        (rideData['trip']?['base_fare'] as num?)?.toDouble() ?? 0.0;
    debugPrint(
      'Using fallback fare calculation: $baseFare * $numberOfSeats = ${baseFare * numberOfSeats}',
    );
    return baseFare * numberOfSeats;
  }

  // Get selected route summary
  String getSelectedRouteSummary() {
    if (locationNames.isEmpty) return 'No route information';

    final fromStopName = selectedFromStop <= locationNames.length
        ? locationNames[selectedFromStop - 1]
        : 'Unknown';
    final toStopName = selectedToStop <= locationNames.length
        ? locationNames[selectedToStop - 1]
        : 'Unknown';

    return '$fromStopName → $toStopName';
  }

  // Get selected route distance
  double getSelectedRouteDistance() {
    if (rideData.isEmpty || routeDistance == null) return 0.0;

    // Calculate proportional distance based on selected stops
    final totalStops = locationNames.length;
    if (totalStops <= 1) return routeDistance!;

    final fromIndex = selectedFromStop - 1;
    final toIndex = selectedToStop - 1;
    final stopRange = toIndex - fromIndex;

    // Proportional distance calculation
    return (routeDistance! / (totalStops - 1)) * stopRange;
  }

  // Generate interpolated route points for more realistic visualization
  List<LatLng> _generateInterpolatedRoute(List<LatLng> stops) {
    if (stops.length >= 2) {
      _calculateDistance(stops.first, stops.last);
    }
    return MapUtil.generateInterpolatedRoute(stops);
  }

  // Haversine distance
  double _calculateDistance(LatLng a, LatLng b) {
    return MapUtil.calculateDistanceMeters(a, b);
  }

  // Get driver information
  Map<String, dynamic> getDriverInfo() {
    return rideData['driver'] ?? {};
  }

  // Get vehicle information
  Map<String, dynamic> getVehicleInfo() {
    return rideData['vehicle'] ?? {};
  }

  // Resolvers for image URLs and fields used by UI
  String? driverPhotoUrl() {
    final d = getDriverInfo();
    final s = d['profile_photo']?.toString();
    final ensured = ImageUtils.ensureValidImageUrl(s);
    if (ensured != null && ensured.isNotEmpty) return ensured;
    return null;
  }

  String? vehicleFrontPhotoUrl() {
    final v = getVehicleInfo();
    final s = v['photo_front']?.toString();
    final ensured = ImageUtils.ensureValidImageUrl(s);
    if (ensured != null && ensured.isNotEmpty) return ensured;
    return null;
  }

  String plateNumber() {
    final v = getVehicleInfo();
    final cand = [
      v['plate_number'],
      v['plate_no'],
      v['license_plate'],
      v['plate'],
      v['number_plate'],
    ];
    for (final c in cand) {
      final s = c?.toString();
      if (s != null && s.isNotEmpty) return s;
    }
    return 'N/A';
  }

  String vehicleColor() {
    final v = getVehicleInfo();
    final cand = [v['color'], v['vehicle_color'], v['colour']];
    for (final c in cand) {
      final s = c?.toString();
      if (s != null && s.isNotEmpty) return s;
    }
    return 'N/A';
  }

  String vehicleType() {
    final v = getVehicleInfo();
    final cand = [v['vehicle_type'], v['type']];
    for (final c in cand) {
      final s = c?.toString();
      if (s != null && s.isNotEmpty) return s;
    }
    return 'N/A';
  }

  String vehicleCompanyModel() {
    final v = getVehicleInfo();
    final company = (v['company_name'] ?? v['company'] ?? '').toString();
    final model = (v['model_number'] ?? v['model'] ?? '').toString();
    final parts = [company, model].where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? 'Vehicle' : parts.join(' ');
  }

  // Get trip information
  Map<String, dynamic> getTripInfo() {
    return rideData['trip'] ?? {};
  }

  // Get passengers information
  List<Map<String, dynamic>> getPassengersInfo() {
    return List<Map<String, dynamic>>.from(rideData['passengers'] ?? []);
  }

  // Get fare information
  Map<String, dynamic> getFareInfo() {
    return rideData['fare_data'] ?? {};
  }

  // Get stop breakdown
  List<Map<String, dynamic>> getStopBreakdown() {
    return List<Map<String, dynamic>>.from(rideData['stop_breakdown'] ?? []);
  }

  // Get booking information
  Map<String, dynamic> getBookingInfo() {
    return rideData['booking_info'] ?? {};
  }

  // Check if ride is bookable
  bool isRideBookable() {
    final bookingInfo = getBookingInfo();
    return bookingInfo['can_book'] == true;
  }

  // Get maximum seats allowed
  int getMaxSeats() {
    final bookingInfo = getBookingInfo();
    return bookingInfo['max_seats'] ?? 1;
  }

  // Get minimum seats required
  int getMinSeats() {
    final bookingInfo = getBookingInfo();
    return bookingInfo['min_seats'] ?? 1;
  }

  // Get price per seat
  double getPricePerSeat() {
    // Check if we have dynamic fare calculation result first
    final dynamicFare = rideData['trip']?['dynamic_fare'];
    if (dynamicFare != null) {
      final baseFarePerSeat =
          (dynamicFare['base_fare_per_seat'] as num?)?.toDouble() ?? 0.0;
      debugPrint(
        'DEBUG: RideBookingDetailsController.getPricePerSeat() - using dynamic fare: $baseFarePerSeat',
      );
      return baseFarePerSeat;
    }

    final bookingInfo = getBookingInfo();
    final pricePerSeat =
        (bookingInfo['price_per_seat'] as num?)?.toDouble() ?? 0.0;
    debugPrint(
      'DEBUG: RideBookingDetailsController.getPricePerSeat() - booking_info: $bookingInfo',
    );
    debugPrint(
      'DEBUG: RideBookingDetailsController.getPricePerSeat() - returning: $pricePerSeat',
    );
    return pricePerSeat;
  }

  // Format departure time
  String getFormattedDepartureTime() {
    final tripInfo = getTripInfo();
    final departureTime = tripInfo['departure_time'];
    final tripDate = tripInfo['trip_date'];

    if (departureTime == null || tripDate == null) return 'N/A';

    try {
      final date = DateTime.parse(tripDate);
      final timeParts = departureTime.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final departureDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );
      final now = DateTime.now();

      if (departureDateTime.isAfter(now)) {
        final difference = departureDateTime.difference(now);
        if (difference.inDays > 0) {
          return '${DateFormat('MMM dd, HH:mm').format(departureDateTime)} (in ${difference.inDays} day${difference.inDays > 1 ? 's' : ''})';
        } else if (difference.inHours > 0) {
          return '${DateFormat('HH:mm').format(departureDateTime)} (in ${difference.inHours} hour${difference.inHours > 1 ? 's' : ''})';
        } else {
          return '${DateFormat('HH:mm').format(departureDateTime)} (in ${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''})';
        }
      } else {
        return DateFormat('MMM dd, HH:mm').format(departureDateTime);
      }
    } catch (e) {
      return departureTime;
    }
  }

  // Format trip date
  String getFormattedTripDate() {
    final tripInfo = getTripInfo();
    final tripDate = tripInfo['trip_date'];

    if (tripDate == null) return 'N/A';

    try {
      final date = DateTime.parse(tripDate);
      final now = DateTime.now();

      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return 'Today';
      } else if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day + 1) {
        return 'Tomorrow';
      } else {
        return DateFormat('MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return tripDate;
    }
  }

  // Get gender preference display text
  String getGenderPreferenceText() {
    final tripInfo = getTripInfo();
    final genderPref = tripInfo['gender_preference'];

    if (genderPref == null || genderPref == 'Any') {
      return 'Any gender welcome';
    } else {
      return '$genderPref only';
    }
  }

  // Get trip status display text
  String getTripStatusText() {
    final tripInfo = getTripInfo();
    final status = tripInfo['trip_status'];

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

  // Get trip status color
  Color getTripStatusColor() {
    final tripInfo = getTripInfo();
    final status = tripInfo['trip_status'];

    switch (status) {
      case 'SCHEDULED':
        return Colors.green;
      case 'IN_PROGRESS':
        return Colors.blue;
      case 'COMPLETED':
        return Colors.grey;
      case 'CANCELLED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Set loading state
  void setLoading(bool loading) {
    isLoading = loading;
    onStateChanged?.call();
  }

  // Set error message
  void setError(String error) {
    errorMessage = error;
    onStateChanged?.call();
  }

  // Clear error message
  void clearError() {
    errorMessage = null;
    onStateChanged?.call();
  }

  // Get formatted duration string for display
  String getEstimatedDuration() {
    if (selectedRouteDuration <= 0) return 'N/A';

    final hours = selectedRouteDuration ~/ 60;
    final minutes = selectedRouteDuration % 60;

    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  // Update state
  void setState(VoidCallback fn) {
    fn();
    onStateChanged?.call();
  }

  // Dispose method for cleanup
  void dispose() {
    // Clean up any resources if needed in the future
  }
}
