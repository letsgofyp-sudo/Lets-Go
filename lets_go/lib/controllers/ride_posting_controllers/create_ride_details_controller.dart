import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/map_util.dart';
import '../../services/api_service.dart';
import '../../utils/fare_calculator.dart';
import '../../utils/road_polyline_service.dart';
import '../../utils/auth_session.dart';

class RideDetailsController {
  // Route data
  List<LatLng> points = [];
  List<String> locationNames = [];
  List<LatLng> routePoints = [];
  List<LatLng> plannedRoutePoints = [];
  List<LatLng> actualRoutePoints = [];
  bool useActualPath = false;
  bool isPlannedRouteLoading = false;
  bool isActualRouteExtending = false;
  List<LatLng> _initialStopsSnapshot = [];
  LatLng? currentPosition;
  String? createdRouteId;
  double? routeDistance;
  int? routeDuration;

  // When false, controller will not call RoadPolylineService/OpenRouteService.
  // This is mainly to make unit tests deterministic and offline.
  final bool enableRoadSnapping;

  // Ride details
  DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay selectedTime = TimeOfDay.now();
  int totalSeats = 4;
  String? genderPreference;
  String? selectedVehicle;
  String? prefilledVehicleId;
  String description = '';
  final List<String> genderOptions = ['Male', 'Female', 'Any'];
  List<Map<String, dynamic>> userVehicles = [];

  // Dynamic fare calculation
  int dynamicPricePerSeat = 0;
  Map<String, dynamic> fareCalculation = {};
  Map<String, dynamic> autoFareCalculation = {};
  Map<String, dynamic> manualFareCalculation = {};
  bool hasManualAdjustments = false;
  bool isMapLoading = true;

  // Submit state
  bool isSubmitting = false;

  // Price negotiation
  bool isPriceNegotiable = true; // Default to true as requested

  // When true, we will create a fresh backend route at the time of creating the ride,
  // using the currently selected polyline (planned vs actual).
  bool recreateMode = false;

  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function(String)? onInfo;

  RideDetailsController({
    this.onStateChanged,
    this.onError,
    this.onSuccess,
    this.onInfo,
    this.enableRoadSnapping = true,
  });

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  int _resolveUserId(Map<String, dynamic> userData) {
    return _toInt(userData['id'])
            ?? _toInt(userData['user_id'])
            ?? _toInt(userData['user']?['id'])
            ?? _toInt(userData['profile']?['id'])
            ?? 0;
  }

  Future<int> _resolveUserIdWithSessionFallback(Map<String, dynamic> userData) async {
    final direct = _resolveUserId(userData);
    if (direct > 0) return direct;

    try {
      final session = await AuthSession.load();
      if (session != null) {
        final sessId = _toInt(session['id']) ?? _toInt(session['user_id']) ?? 0;
        if (sessId > 0) return sessId;
      }
    } catch (_) {
      // ignore
    }
    return 0;
  }

  // Initialize route data from passed data
  void initializeRouteData(Map<String, dynamic> routeData) {
    if (routeData['points'] != null) {
      points = List<LatLng>.from(routeData['points']);
    }
    if (routeData['locationNames'] != null) {
      locationNames = List<String>.from(routeData['locationNames']);
    }
    if (routeData['routePoints'] != null) {
      plannedRoutePoints = List<LatLng>.from(routeData['routePoints']);
    }

    final actual = routeData['actualRoutePoints'];
    if (actual is List) {
      try {
        actualRoutePoints = List<LatLng>.from(actual);
      } catch (_) {
        actualRoutePoints = [];
      }
    } else {
      actualRoutePoints = [];
    }

    final preferActual = routeData['preferActualPath'];
    useActualPath = (preferActual == true) && actualRoutePoints.length >= 2;

    // Snapshot the original stops once, so we can detect appended stops later.
    if (_initialStopsSnapshot.isEmpty && points.isNotEmpty) {
      _initialStopsSnapshot = List<LatLng>.from(points);
    }

    // Default to the chosen polyline; stops remain in `points`.
    routePoints = useActualPath && actualRoutePoints.length >= 2
        ? List<LatLng>.from(actualRoutePoints)
        : List<LatLng>.from(plannedRoutePoints.isNotEmpty ? plannedRoutePoints : points);

    createdRouteId = routeData['routeId'];
    routeDistance = routeData['distance'];
    routeDuration = routeData['duration'];

    if (enableRoadSnapping) {
      // Ensure planned polyline follows roads when we have stops but planned polyline
      // is missing or just a straight-line fallback.
      _ensurePlannedRouteOnRoads();

      // If user is viewing actual path and stops were edited/extended, append a
      // road-following segment from actual end to the new stop(s).
      _ensureActualPathExtendedToStops();
    }
  }

  bool get hasActualPathAvailable => actualRoutePoints.length >= 2;

  void setUseActualPath(bool value) {
    useActualPath = value && hasActualPathAvailable;
    routePoints = useActualPath
        ? List<LatLng>.from(actualRoutePoints)
        : List<LatLng>.from(plannedRoutePoints.isNotEmpty ? plannedRoutePoints : points);
    // Recompute distance/duration so pricing and UI reflect chosen polyline.
    _recalculateDistanceDurationFromRoutePoints();
    calculateDynamicFare();
    onStateChanged?.call();

    if (enableRoadSnapping) {
      if (!useActualPath) {
        _ensurePlannedRouteOnRoads();
      } else {
        _ensureActualPathExtendedToStops();
      }
    }
  }

  bool _sameLatLng(LatLng a, LatLng b, {double epsilon = 1e-7}) {
    return (a.latitude - b.latitude).abs() <= epsilon &&
        (a.longitude - b.longitude).abs() <= epsilon;
  }

  bool _startsWithStops(List<LatLng> full, List<LatLng> prefix) {
    if (prefix.isEmpty) return true;
    if (full.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (!_sameLatLng(full[i], prefix[i])) return false;
    }
    return true;
  }

  bool _doesPolylineCoverStop(
    List<LatLng> poly,
    LatLng stop, {
    double thresholdMeters = 150,
  }) {
    if (poly.isEmpty) return false;
    for (final p in poly) {
      final d = calculateDistance(p, stop);
      if (d <= thresholdMeters) return true;
    }
    return false;
  }

  bool _validateActualPathCoversStops({double thresholdMeters = 150}) {
    if (!useActualPath) return true;
    if (actualRoutePoints.length < 2) return false;
    if (points.length < 2) return false;

    // The user wants: if the actual path doesn't cover any stop, block creation.
    // We interpret "cover" as each stop being within threshold of some actual point.
    for (final s in points) {
      if (!_doesPolylineCoverStop(actualRoutePoints, s, thresholdMeters: thresholdMeters)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _ensureActualPathExtendedToStops() async {
    if (!useActualPath) return;
    if (actualRoutePoints.length < 2) return;
    if (points.length < 2) return;
    if (isActualRouteExtending) return;

    // IMPORTANT (recreate-mode behavior):
    // We only extend the actual path when the user APPENDS new stops.
    // If stops are deleted or reordered, we must NOT alter the actual path.
    if (!(_initialStopsSnapshot.length >= 2 &&
        _startsWithStops(points, _initialStopsSnapshot) &&
        points.length > _initialStopsSnapshot.length)) {
      return;
    }

    var targets = points.sublist(_initialStopsSnapshot.length);
    if (targets.isEmpty) return;

    final actualEnd = actualRoutePoints.last;
    // If the first target is effectively the same as actual end, skip it.
    if (_sameLatLng(actualEnd, targets.first)) {
      targets = targets.sublist(1);
    }
    if (targets.isEmpty) return;

    isActualRouteExtending = true;
    onStateChanged?.call();

    try {
      final ext = await RoadPolylineService.fetchRoadPolyline([actualEnd, ...targets]);
      if (ext.length >= 2) {
        // Avoid duplicating the first point (actualEnd).
        final toAppend = ext.sublist(1);
        if (toAppend.isNotEmpty) {
          actualRoutePoints = [...actualRoutePoints, ...toAppend];
          routePoints = List<LatLng>.from(actualRoutePoints);
          _recalculateDistanceDurationFromRoutePoints();
          calculateDynamicFare();
          // Update snapshot so future appended stops are detected correctly.
          _initialStopsSnapshot = List<LatLng>.from(points);
        }
      }
    } finally {
      isActualRouteExtending = false;
      onStateChanged?.call();
    }
  }

  bool _looksLikeStraightLinePlannedRoute() {
    if (plannedRoutePoints.isEmpty) return true;
    // If it matches stops list length exactly, it's likely just a straight-line polyline.
    if (plannedRoutePoints.length == points.length && plannedRoutePoints.length <= 10) {
      bool allMatch = true;
      for (int i = 0; i < plannedRoutePoints.length; i++) {
        if (plannedRoutePoints[i].latitude != points[i].latitude ||
            plannedRoutePoints[i].longitude != points[i].longitude) {
          allMatch = false;
          break;
        }
      }
      if (allMatch) return true;
    }
    return false;
  }

  Future<void> _ensurePlannedRouteOnRoads() async {
    if (points.length < 2) return;
    if (useActualPath) return;
    if (isPlannedRouteLoading) return;
    if (!_looksLikeStraightLinePlannedRoute()) return;
    await fetchPlannedRouteOnRoads();
  }

  // Fetch road-following polyline for planned route using OpenRouteService.
  // Uses `points` (stops) as waypoints.
  Future<void> fetchPlannedRouteOnRoads() async {
    if (points.length < 2) return;
    isPlannedRouteLoading = true;
    onStateChanged?.call();

    try {
      plannedRoutePoints = await RoadPolylineService.fetchRoadPolyline(points);
    } catch (_) {
      plannedRoutePoints = List<LatLng>.from(points);
    } finally {
      isPlannedRouteLoading = false;
      if (!useActualPath) {
        routePoints = List<LatLng>.from(plannedRoutePoints);
        _recalculateDistanceDurationFromRoutePoints();
        calculateDynamicFare();
      }
      onStateChanged?.call();
    }
  }

  void _recalculateDistanceDurationFromRoutePoints() {
    if (routePoints.length < 2) {
      routeDistance = 0.0;
      routeDuration = 0;
      return;
    }
    double totalDistance = 0.0;
    for (int i = 1; i < routePoints.length; i++) {
      totalDistance += calculateDistance(routePoints[i - 1], routePoints[i]);
    }
    totalDistance = totalDistance / 1000;
    routeDistance = totalDistance;
    routeDuration = (totalDistance / 50 * 60).round();
  }

  // Get current location
  Future<void> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        onError?.call('Location services are disabled');
        currentPosition = const LatLng(
          31.5204,
          74.3587,
        ); // Default position (Lahore)
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          onError?.call('Location permissions are denied');
          currentPosition = const LatLng(31.5204, 74.3587); // Default position
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        onError?.call('Location permissions are permanently denied');
        currentPosition = const LatLng(31.5204, 74.3587); // Default position
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition();
      currentPosition = LatLng(position.latitude, position.longitude);
      onStateChanged?.call();
    } catch (e) {
      onError?.call('Error getting location: $e');
      currentPosition = const LatLng(31.5204, 74.3587); // Default position
      onStateChanged?.call();
    }
  }

  // Load user vehicles
  Future<void> loadUserVehicles(int userId) async {
    try {
      final vehicles = await ApiService.getUserVehicles(userId);
      userVehicles = vehicles
          .where((v) => (v['status']?.toString().toUpperCase() ?? 'VERIFIED') == 'VERIFIED')
          .toList();
      if (userVehicles.isNotEmpty) {
        String? chosen;
        final pre = (prefilledVehicleId ?? '').toString().trim();
        if (pre.isNotEmpty) {
          final match = userVehicles.where((v) => v['id']?.toString() == pre).toList();
          if (match.isNotEmpty) {
            chosen = pre;
          }
        }
        selectedVehicle = chosen ?? userVehicles.first['id']?.toString();

        // Update seats based on selected vehicle
        final vehicle = userVehicles.firstWhere(
          (v) => v['id']?.toString() == selectedVehicle,
          orElse: () => userVehicles.first,
        );
        final seats = _toInt(vehicle['seats']);
        if (seats != null && seats > 0) {
          totalSeats = (seats - 1).clamp(1, 100);
        }
      } else {
        selectedVehicle = null;
      }

      prefilledVehicleId = null;
      onStateChanged?.call();

      // Recalculate dynamic fare when vehicles are loaded
      calculateDynamicFare();
    } catch (e) {
      onError?.call('Failed to load vehicles: $e');
    }
  }

  // Calculate dynamic fare based on current parameters (auto calculation)
  void calculateDynamicFare() {
    if (points.length < 2 || selectedVehicle == null || userVehicles.isEmpty) {
      return;
    }

    try {
      // Get selected vehicle data
      final selectedVehicleData = userVehicles.firstWhere(
        (v) => v['id'].toString() == selectedVehicle!,
        orElse: () => userVehicles.first,
      );

      // Prepare route stops
      final routeStops = points.asMap().entries.map((entry) {
        return {
          'latitude': entry.value.latitude,
          'longitude': entry.value.longitude,
          'stop_name':
              locationNames.isNotEmpty && entry.key < locationNames.length
              ? locationNames[entry.key]
              : 'Stop ${entry.key + 1}',
        };
      }).toList();

      // Calculate departure time
      final departureTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      // Calculate comprehensive automatic fare on-device
      // Map backend vehicle type codes to calculator categories
      String backendVehicleType = (selectedVehicleData['vehicle_type'] ?? 'FW')
          .toString();
      String calculatorVehicleType = _mapVehicleTypeForCalculator(
        backendVehicleType,
      );

      debugPrint('[CREATE_CTRL] calculateDynamicFare: routeStops count=${routeStops.length}');
      final result = FareCalculator.calculateFare(
        routeStops: routeStops,
        fuelType: selectedVehicleData['fuel_type'] ?? 'Petrol',
        vehicleType: calculatorVehicleType,
        departureTime: departureTime,
        totalSeats: totalSeats,
      );

      // Store automatic calculation
      autoFareCalculation = Map<String, dynamic>.from(result);
      // Initialize manual calc with auto by default (no adjustments yet)
      manualFareCalculation = Map<String, dynamic>.from(result);
      hasManualAdjustments = false;

      // Expose current fare via fareCalculation for UI binding
      fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
      dynamicPricePerSeat = (manualFareCalculation['base_fare'] as num?)?.round() ?? 0;
      debugPrint('[CREATE_CTRL] Auto base=${autoFareCalculation['base_fare']} total=${autoFareCalculation['total_price']}');
      final sb = (autoFareCalculation['stop_breakdown'] as List<dynamic>? ?? []).map((e) => (e['price'] ?? 0.0)).toList();
      debugPrint('[CREATE_CTRL] Auto stop prices=$sb');
      debugPrint('[CREATE_CTRL] Exposed fareCalc total=${fareCalculation['total_price']} dynamicPricePerSeat=$dynamicPricePerSeat');
      onStateChanged?.call();
    } catch (e) {
      // Keep default price if calculation fails
      dynamicPricePerSeat = 500;
      autoFareCalculation = {
        'base_fare': 500,
        'total_distance_km': 0.0,
        'total_duration_minutes': 0,
        'stop_breakdown': [],
        'calculation_breakdown': {},
      };
      manualFareCalculation = Map<String, dynamic>.from(autoFareCalculation);
      fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
      hasManualAdjustments = false;
      onStateChanged?.call();
    }
  }

  String _mapVehicleTypeForCalculator(String? backendType) {
    switch ((backendType ?? '').toUpperCase()) {
      case 'TW':
        return 'Motorcycle';
      case 'FW':
        return 'Sedan';
      default:
        return backendType ?? 'Sedan';
    }
  }

  // Update total price and distribute across stops (manual adjustment)
  void updateTotalPrice(int newTotalPrice) {
    if (manualFareCalculation.isEmpty) return;

    final stopBreakdown =
        manualFareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
    if (stopBreakdown.isEmpty) return;

    // Debug: Print current breakdown
    debugPrint(
      'Current breakdown: ${stopBreakdown.map((s) => s['price']).toList()}',
    );
    debugPrint('Current total: $dynamicPricePerSeat');
    debugPrint('New total requested: $newTotalPrice');

    // Distribute the new total price across stops
    final updatedBreakdown = FareCalculator.distributeTotalPrice(
      stopBreakdown.cast<Map<String, dynamic>>(),
      newTotalPrice,
    );

    // Debug: Print updated breakdown
    debugPrint(
      'Updated breakdown: ${updatedBreakdown.map((s) => s['price']).toList()}',
    );
    final int calculatedTotal = updatedBreakdown.fold<int>(
      0,
      (sum, stop) => sum + ((stop['price'] as num?)?.toInt() ?? 0),
    );
    debugPrint('Calculated total: $calculatedTotal');

    // Guarantee integer exact sum by pushing any remainder into the last segment.
    if (updatedBreakdown.isNotEmpty && calculatedTotal != newTotalPrice) {
      final int diff = newTotalPrice - calculatedTotal;
      final int lastStopPrice = (updatedBreakdown.last['price'] as num?)?.toInt() ?? 0;
      updatedBreakdown.last['price'] = lastStopPrice + diff;
      debugPrint('Adjusted last stop price to: ${updatedBreakdown.last['price']}');
    }

    // Update the fare calculation
    manualFareCalculation = Map<String, dynamic>.from(manualFareCalculation);
    manualFareCalculation['stop_breakdown'] = updatedBreakdown;

    // Update total price
    manualFareCalculation['total_price'] = newTotalPrice;
    manualFareCalculation['base_fare'] = newTotalPrice;

    // Update dynamic price
    dynamicPricePerSeat = newTotalPrice;

    // Update calculation breakdown
    final breakdown =
        manualFareCalculation['calculation_breakdown'] as Map<String, dynamic>? ?? {};
    breakdown['total_price'] = newTotalPrice;
    manualFareCalculation['calculation_breakdown'] = breakdown;

    // Reflect manual changes in exposed fareCalculation and flag
    fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
    hasManualAdjustments = true;
    debugPrint('[CREATE_CTRL] updateTotalPrice -> newTotal=$newTotalPrice');
    debugPrint('[CREATE_CTRL] stop prices after distribute=${updatedBreakdown.map((e) => e['price']).toList()}');
    debugPrint('[CREATE_CTRL] exposed total=${fareCalculation['total_price']}');

    onStateChanged?.call();
  }

  // Update individual stop price (manual adjustment)
  void updateStopPrice(int stopIndex, int newPrice) {
    if (manualFareCalculation.isEmpty) return;

    final stopBreakdown =
        manualFareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
    if (stopIndex < 0 || stopIndex >= stopBreakdown.length) return;

    // Debug: Print current state
    debugPrint('Updating stop $stopIndex price to: $newPrice');
    debugPrint(
      'Current breakdown: ${stopBreakdown.map((s) => s['price']).toList()}',
    );

    // Update the stop price using FareCalculator (only affects this stop, increases total)
    final updatedBreakdown = FareCalculator.updateStopPriceOnly(
      stopBreakdown.cast<Map<String, dynamic>>(),
      stopIndex,
      newPrice,
    );

    // Debug: Print updated state
    debugPrint(
      'Updated breakdown: ${updatedBreakdown.map((s) => s['price']).toList()}',
    );
    final int calculatedTotal = updatedBreakdown.fold<int>(
      0,
      (sum, stop) => sum + ((stop['price'] as num?)?.toInt() ?? 0),
    );
    debugPrint('Calculated total: $calculatedTotal');

    // Update the manual fare calculation breakdown
    manualFareCalculation = Map<String, dynamic>.from(manualFareCalculation);
    manualFareCalculation['stop_breakdown'] = updatedBreakdown;

    // Update total price
    manualFareCalculation['total_price'] = calculatedTotal;
    manualFareCalculation['base_fare'] = calculatedTotal;

    // Update dynamic price
    dynamicPricePerSeat = calculatedTotal;

    // Update calculation breakdown
    final breakdown =
        manualFareCalculation['calculation_breakdown'] as Map<String, dynamic>? ?? {};
    breakdown['total_price'] = calculatedTotal;
    manualFareCalculation['calculation_breakdown'] = breakdown;

    // Reflect manual changes in exposed fareCalculation and flag
    fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
    hasManualAdjustments = true;

    onStateChanged?.call();

    // Show success message
    onInfo?.call('Updated stop price to ₨$newPrice');
  }

  // Create route via API
  Future<Map<String, dynamic>> createRoute() async {
    if (points.length < 2) {
      return {
        'success': false,
        'error': 'Please select at least origin and destination',
      };
    }

    try {
      // Calculate distance and duration from route points
      double totalDistance = 0.0;
      int totalDuration = 0;

      if (routePoints.isNotEmpty) {
        // Calculate distance from route points
        for (int i = 1; i < routePoints.length; i++) {
          totalDistance += calculateDistance(
            routePoints[i - 1],
            routePoints[i],
          );
        }
        totalDistance = totalDistance / 1000; // Convert to kilometers

        // Estimate duration (assuming average speed of 50 km/h)
        totalDuration = (totalDistance / 50 * 60).round(); // Convert to minutes
      }

      final routeData = {
        'coordinates': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'route_points': routePoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'location_names': locationNames,
        'created_at': DateTime.now().toIso8601String(),
      };

      // Debug: Print route data being sent
      debugPrint('Sending route data: ${routeData.toString()}');

      final response = await ApiService.createRoute(routeData);

      debugPrint('API Response: ${response.toString()}');

      if (response['success'] == true) {
        createdRouteId = response['route']?['id']?.toString();
        routeDistance =
            response['route']?['distance']?.toDouble() ?? totalDistance;
        routeDuration =
            response['route']?['duration']?.toInt() ?? totalDuration;

        onSuccess?.call(
          'Route created successfully! Distance: ${routeDistance?.toStringAsFixed(1)} km',
        );
        return response;
      } else {
        // If API fails, use calculated values as fallback
        routeDistance = totalDistance;
        routeDuration = totalDuration;
        // Generate a temporary route ID for local use
        createdRouteId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

        onSuccess?.call(
          'Route created with calculated values. Distance: ${routeDistance?.toStringAsFixed(1)} km',
        );
        return {
          'success': true,
          'route': {
            'id': createdRouteId,
            'distance': routeDistance,
            'duration': routeDuration,
          },
        };
      }
    } catch (e) {
      debugPrint('Error creating route: $e');

      // Use calculated values as fallback even on error
      double totalDistance = 0.0;
      int totalDuration = 0;

      if (routePoints.isNotEmpty) {
        for (int i = 1; i < routePoints.length; i++) {
          totalDistance += calculateDistance(
            routePoints[i - 1],
            routePoints[i],
          );
        }
        totalDistance = totalDistance / 1000;
        totalDuration = (totalDistance / 50 * 60).round();
      }

      routeDistance = totalDistance;
      routeDuration = totalDuration;
      // Generate a temporary route ID for local use
      createdRouteId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

      onSuccess?.call(
        'Route created with fallback values. Distance: ${routeDistance?.toStringAsFixed(1)} km',
      );
      return {
        'success': true,
        'route': {
          'id': createdRouteId,
          'distance': routeDistance,
          'duration': routeDuration,
        },
      };
    }
  }

  // Calculate distance between two points in meters
  double calculateDistance(LatLng point1, LatLng point2) {
    return MapUtil.calculateDistanceMeters(point1, point2);
  }

  // Update ride details
  void updateSelectedDate(DateTime date) {
    selectedDate = date;
    onStateChanged?.call();
    calculateDynamicFare();
  }

  void updateSelectedTime(TimeOfDay time) {
    selectedTime = time;
    onStateChanged?.call();
    calculateDynamicFare();
  }

  void updateTotalSeats(int seats) {
    totalSeats = seats;
    onStateChanged?.call();
    calculateDynamicFare();
  }

  void updateGenderPreference(String? preference) {
    if (preference != null && genderOptions.contains(preference)) {
      genderPreference = preference;
      debugPrint('Setting gender preference to: $preference'); // Debug log
    } else {
      genderPreference = 'Any';
      debugPrint('Invalid preference: $preference, defaulting to Any'); // Debug log
    }
    onStateChanged?.call();
  }

  void updateSelectedVehicle(String? vehicleId) {
    if (vehicleId != null) {
      final found = userVehicles.where((v) => v['id']?.toString() == vehicleId).toList();
      if (found.isEmpty) return;
    }
    selectedVehicle = vehicleId;
    if (vehicleId != null) {
      final vehicle = userVehicles.firstWhere(
        (v) => v['id'].toString() == vehicleId,
        orElse: () => userVehicles.first,
      );
      final seats = _toInt(vehicle['seats']);
      if (seats != null && seats > 0) {
        totalSeats = (seats - 1).clamp(1, 100);
      }
    }
    onStateChanged?.call();
    calculateDynamicFare();
  }

  void updateDescription(String desc) {
    description = desc;
    onStateChanged?.call();
  }

  // Set map loading state
  void setMapLoading(bool loading) {
    isMapLoading = loading;
    onStateChanged?.call();
  }

  // Get ride data for API calls
  Map<String, dynamic> getRideData() {
    return {
      'routeId': createdRouteId,
      'vehicleId': selectedVehicle,
      'tripDate': DateFormat('yyyy-MM-dd').format(selectedDate),
      'departureTime':
          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
      'totalSeats': totalSeats,
      'genderPreference': genderPreference,
      'customPrice': dynamicPricePerSeat,
      'fareCalculation': fareCalculation,
      'description': description,
      'isPriceNegotiable': isPriceNegotiable,
    };
  }

  // Get route data for navigation
  Map<String, dynamic> getRouteData() {
    return {
      'points': points,
      'locationNames': locationNames,
      'routePoints': routePoints,
      'routeId': createdRouteId,
      'distance': routeDistance,
      'duration': routeDuration,
    };
  }

  // Dispose method for cleanup
  void dispose() {
    // Clean up any resources if needed
  }

  // Toggle price negotiation
  void togglePriceNegotiation(bool value) {
    isPriceNegotiable = value;
    onStateChanged?.call();
  }

  // Navigate to MyRidesScreen
  void _navigateToMyRides() {
    // This will be handled by the screen to navigate to MyRidesScreen
    // The screen should listen for a specific callback or use a navigation service
    onSuccess?.call('navigate_to_my_rides');
  }

  // Select vehicle method
  void selectVehicle(String vehicleId) {
    selectedVehicle = vehicleId;
    if (vehicleId.isNotEmpty) {
      final vehicle = userVehicles.firstWhere(
        (v) => v['id']?.toString() == vehicleId,
        orElse: () => userVehicles.first,
      );
      final seats = _toInt(vehicle['seats']);
      if (seats != null && seats > 0) {
        totalSeats = (seats - 1).clamp(1, 100);
      }
    }
    onStateChanged?.call();
    calculateDynamicFare();
  }

  // Create ride with user data
  Future<void> createRide(Map<String, dynamic> userData) async {
    if (isSubmitting) return;
    isSubmitting = true;
    onStateChanged?.call();

    // Validate all required data is present
    if (!recreateMode && createdRouteId == null) {
      onError?.call(
        'Route not found. Please go back and create a route first.',
      );
      isSubmitting = false;
      onStateChanged?.call();
      return;
    }

    if ((manualFareCalculation['stop_breakdown'] as List?)?.isEmpty != false) {
      calculateDynamicFare();
      if (!hasManualAdjustments && autoFareCalculation.isNotEmpty) {
        manualFareCalculation = Map<String, dynamic>.from(autoFareCalculation);
        fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
        dynamicPricePerSeat = (manualFareCalculation['base_fare'] as num?)?.round() ?? dynamicPricePerSeat;
      }
    }

    if ((manualFareCalculation['stop_breakdown'] as List?)?.isEmpty != false) {
      onError?.call('Fare calculation failed. Please adjust fare once and try again.');
      isSubmitting = false;
      onStateChanged?.call();
      return;
    }

    // For temporary route IDs (local testing), skip backend validation
    bool isTemporaryRoute = createdRouteId!.startsWith('temp_');

    if (selectedVehicle == null) {
      onError?.call('Please select a vehicle');
      isSubmitting = false;
      onStateChanged?.call();
      return;
    }

    if (totalSeats <= 0) {
      onError?.call('Please select at least 1 seat');
      isSubmitting = false;
      onStateChanged?.call();
      return;
    }

    try {
      // In recreate mode we create a new route so the persisted geometry matches
      // the currently selected path (planned vs actual).
      if (recreateMode) {
        if (points.length < 2) {
          onError?.call('Trip route data missing');
          return;
        }

        // If user chose actual path, ensure it meaningfully aligns with the stops.
        if (useActualPath) {
          final ok = _validateActualPathCoversStops(thresholdMeters: 150);
          if (!ok) {
            onError?.call(
              'Actual path does not cover one or more stops. Please delete/adjust those stops (or switch to planned route).',
            );
            isSubmitting = false;
            onStateChanged?.call();
            return;
          }
        }

        final List<LatLng> polylineToPersist = useActualPath && actualRoutePoints.length >= 2
            ? List<LatLng>.from(actualRoutePoints)
            : (plannedRoutePoints.isNotEmpty
                ? List<LatLng>.from(plannedRoutePoints)
                : List<LatLng>.from(routePoints));

        final routeData = {
          'coordinates': points
              .map(
                (p) => {
                  'lat': p.latitude,
                  'lng': p.longitude,
                },
              )
              .toList(),
          'route_points': polylineToPersist
              .map(
                (p) => {
                  'lat': p.latitude,
                  'lng': p.longitude,
                },
              )
              .toList(),
          'location_names': locationNames,
          'created_at': DateTime.now().toIso8601String(),
        };

        final rr = await ApiService.createRoute(routeData);
        if (rr['success'] == true) {
          final r = (rr['route'] is Map) ? Map<String, dynamic>.from(rr['route'] as Map) : <String, dynamic>{};
          final newRouteId = (r['id'] ?? '').toString();
          if (newRouteId.trim().isEmpty) {
            onError?.call('Failed to create route for recreate ride');
            isSubmitting = false;
            onStateChanged?.call();
            return;
          }
          createdRouteId = newRouteId;
          try {
            routeDistance = (r['distance'] is num) ? (r['distance'] as num).toDouble() : routeDistance;
          } catch (_) {}
          try {
            routeDuration = (r['duration'] is num) ? (r['duration'] as num).toInt() : routeDuration;
          } catch (_) {}
        } else {
          onError?.call((rr['error'] ?? 'Failed to create route for recreate ride').toString());
          isSubmitting = false;
          onStateChanged?.call();
          return;
        }
      }

      if (isTemporaryRoute) {
        // For temporary routes, show success without backend call
        onSuccess?.call(
          'Ride created successfully! (Local Mode)\nPrice per Seat: ₨${dynamicPricePerSeat.toStringAsFixed(2)}\nRoute: ${locationNames.join(' → ')}',
        );
        // Navigate to MyRidesScreen after successful creation
        _navigateToMyRides();
        return;
      }

      // Create trip with frontend-calculated data
      // Coerce types safely
      final vehicleIdInt = int.tryParse(selectedVehicle ?? '') ?? _toInt(selectedVehicle) ?? _toInt(userData['vehicle_id']) ?? 0;
      final driverIdInt = await _resolveUserIdWithSessionFallback(userData);
      if (vehicleIdInt == 0 || driverIdInt == 0) {
        onError?.call('Missing vehicle/driver id');
        isSubmitting = false;
        onStateChanged?.call();
        return;
      }

      final gate = await ApiService.getRideCreateGateStatus(
        userId: driverIdInt,
        vehicleId: vehicleIdInt,
      );
      if (gate['blocked'] == true) {
        onError?.call(gate['message'] ?? 'Verification pending.');
        isSubmitting = false;
        onStateChanged?.call();
        return;
      }

      final response = await ApiService.createTrip(
        routeId: createdRouteId!,
        vehicleId: vehicleIdInt,
        driverId: driverIdInt,
        tripDate: DateFormat('yyyy-MM-dd').format(selectedDate),
        departureTime:
            '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
        totalSeats: totalSeats,
        customPrice: dynamicPricePerSeat,
        fareCalculation: manualFareCalculation,
        autoFareCalculation: autoFareCalculation,
        hasManualAdjustments: hasManualAdjustments,
        genderPreference: genderPreference,
        notes: description.isNotEmpty
            ? description
            : (locationNames.isNotEmpty
                  ? locationNames.join(' → ')
                  : 'Custom route'),
        isPriceNegotiable: isPriceNegotiable,
      );

      if (response['success']) {
        // Show success message with the frontend-calculated fare
        final customPrice = response['custom_price'] ?? dynamicPricePerSeat;
        onSuccess?.call(
          'Ride created successfully! Trip ID: ${response['trip_id']}\nPrice per Seat: ₨${customPrice.toStringAsFixed(2)}',
        );
        // Navigate to MyRidesScreen after successful creation
        _navigateToMyRides();
      } else {
        onError?.call('Failed to create ride: ${response['error']}');
      }
    } catch (e) {
      onError?.call('Error creating ride: $e');
    } finally {
      isSubmitting = false;
      onStateChanged?.call();
    }
  }
}
