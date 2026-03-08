import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';
import '../../utils/fare_calculator.dart';
import '../../utils/road_polyline_service.dart';

class RideEditController {
  // Route data
  List<LatLng> points = [];
  List<String> locationNames = [];
  List<LatLng> routePoints = [];
  List<LatLng> actualRoutePoints = [];
  LatLng? currentPosition;
  String? createdRouteId;
  double? routeDistance;
  int? routeDuration;

  // Ride details
  DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay selectedTime = TimeOfDay.now();
  int totalSeats = 4;
  String? genderPreference;
  String? selectedVehicle;
  String description = '';
  final List<String> genderOptions = ['Male', 'Female', 'Any'];
  List<Map<String, dynamic>> userVehicles = [];

  // Fare calc
  double dynamicPricePerSeat = 0.0;
  Map<String, dynamic> fareCalculation = {};
  Map<String, dynamic> autoFareCalculation = {};
  Map<String, dynamic> manualFareCalculation = {};
  bool hasManualAdjustments = false;

  // Negotiation
  bool isPriceNegotiable = true;

  // Callbacks
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function(String)? onInfo;

  RideEditController({
    this.onStateChanged,
    this.onError,
    this.onSuccess,
    this.onInfo,
  });

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  void initializeWithRideData(Map<String, dynamic> rideData) {
    try {
      final route = rideData['route'] as Map<String, dynamic>?;
      createdRouteId = route?['id']?.toString();
      routeDistance = (route?['total_distance_km'] as num?)?.toDouble();
      routeDuration = (route?['estimated_duration_minutes'] as num?)?.toInt();

      // Preserve existing actual path (if provided by backend) for overlay purposes.
      // This does NOT affect the planned route that is edited.
      actualRoutePoints = [];
      final rawActual = rideData['actual_path'];
      if (rawActual is List) {
        final pts = <LatLng>[];
        for (final p in rawActual) {
          if (p is! Map) continue;
          final lat = _toDouble(p['lat'] ?? p['latitude']);
          final lng = _toDouble(p['lng'] ?? p['longitude']);
          if (lat != null && lng != null) {
            pts.add(LatLng(lat, lng));
          }
        }
        if (pts.length >= 2) actualRoutePoints = pts;
      }

      final List<dynamic>? stops = (rideData['route_coordinates'] as List<dynamic>?)
          ?? (rideData['route_stops'] as List<dynamic>?)
          ?? (rideData['stops'] as List<dynamic>?)
          ?? (route?['route_stops'] as List<dynamic>?)
          ?? (route?['stops'] as List<dynamic>?);
      if (stops != null && stops.isNotEmpty) {
        points.clear();
        locationNames.clear();
        routePoints.clear();
        for (final raw in stops) {
          final stop = raw as Map<String, dynamic>;
          final lat = (stop['latitude'] as num?)?.toDouble() ?? (stop['lat'] as num?)?.toDouble();
          final lng = (stop['longitude'] as num?)?.toDouble() ?? (stop['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) points.add(LatLng(lat, lng));
          final name = stop['name'] ?? stop['stop_name'] ?? stop['address'] ?? 'Stop';
          locationNames.add(name.toString());
        }
      }

      // Fallback: rebuild from stop_breakdown if we didn't get enough explicit stops
      if (points.length < 2) {
        try {
          List<dynamic>? sb;
          final fc = rideData['fare_calculation'];
          if (fc is Map && fc['stop_breakdown'] is List && (fc['stop_breakdown'] as List).isNotEmpty) {
            sb = List<dynamic>.from(fc['stop_breakdown']);
          } else if (rideData['stop_breakdown'] is List && (rideData['stop_breakdown'] as List).isNotEmpty) {
            sb = List<dynamic>.from(rideData['stop_breakdown']);
          }
          if (sb != null && sb.isNotEmpty) {
            final List<LatLng> rebuilt = [];
            final List<String> names = [];
            for (int i = 0; i < sb.length; i++) {
              final m = sb[i] as Map<String, dynamic>;
              if (i == 0) {
                final from = m['from_coordinates'] as Map<String, dynamic>?;
                final fromLat = (from?['lat'] as num?)?.toDouble();
                final fromLng = (from?['lng'] as num?)?.toDouble();
                if (fromLat != null && fromLng != null) {
                  rebuilt.add(LatLng(fromLat, fromLng));
                  names.add((m['from_stop_name'] ?? 'Stop 1').toString());
                }
              }
              final to = m['to_coordinates'] as Map<String, dynamic>?;
              final toLat = (to?['lat'] as num?)?.toDouble();
              final toLng = (to?['lng'] as num?)?.toDouble();
              if (toLat != null && toLng != null) {
                rebuilt.add(LatLng(toLat, toLng));
                names.add((m['to_stop_name'] ?? 'Stop ${i + 2}').toString());
              }
            }
            if (rebuilt.length >= 2) {
              points = rebuilt;
              locationNames = names;
            }
          }
        } catch (_) {}
      }

      if (rideData['trip_date'] != null) selectedDate = DateTime.parse(rideData['trip_date']);
      if (rideData['departure_time'] != null) {
        final parts = rideData['departure_time'].toString().split(':');
        selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }

      // Negotiation
      if (rideData['is_negotiable'] != null) {
        isPriceNegotiable = rideData['is_negotiable'] == true;
      }

      // Gender preference
      final gp = rideData['gender_preference']?.toString();
      if (gp != null && genderOptions.contains(gp)) {
        genderPreference = gp;
      } else {
        genderPreference ??= 'Any';
      }

      // Notes/description are optional; do not derive from stop names.
      final n = (rideData['notes'] ?? '').toString();
      description = n.trim();

      // Fare calculation payloads
      if (rideData['fare_calculation'] != null) {
        fareCalculation = Map<String, dynamic>.from(rideData['fare_calculation']);
      }
      // Pull stop_breakdown from top-level if missing
      if ((fareCalculation['stop_breakdown'] == null ||
              (fareCalculation['stop_breakdown'] is List && (fareCalculation['stop_breakdown'] as List).isEmpty)) &&
          rideData['stop_breakdown'] != null) {
        try {
          fareCalculation = Map<String, dynamic>.from(fareCalculation);
          fareCalculation['stop_breakdown'] = List<Map<String, dynamic>>.from(rideData['stop_breakdown']);
        } catch (_) {}
      }
      dynamicPricePerSeat = (fareCalculation['base_fare'] as num?)?.toDouble()
          ?? (rideData['custom_price'] as num?)?.toDouble() ?? 0.0;

      // Seed manual fare from existing calculation so manual edits work
      if (fareCalculation.isNotEmpty && manualFareCalculation.isEmpty) {
        manualFareCalculation = Map<String, dynamic>.from(fareCalculation);
        hasManualAdjustments = false;
      }

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

  Future<void> loadUserVehicles(int userId) async {
    try {
      final vehicles = await ApiService.getUserVehicles(userId);
      userVehicles = vehicles;
      if (vehicles.isNotEmpty && selectedVehicle == null) {
        selectedVehicle = vehicles.first['id'].toString();
        if (vehicles.first['seats'] != null) totalSeats = (vehicles.first['seats'] as int) - 1;
      }
      onStateChanged?.call();
    } catch (e) {
      onError?.call('Failed to load vehicles: $e');
    }
  }

  void calculateDynamicFare() {
    if (points.length < 2 || selectedVehicle == null || userVehicles.isEmpty) return;
    try {
      final selectedVehicleData = userVehicles.firstWhere(
        (v) => v['id'].toString() == selectedVehicle!,
        orElse: () => userVehicles.first,
      );
      final routeStops = points.asMap().entries.map((entry) => {
            'latitude': entry.value.latitude,
            'longitude': entry.value.longitude,
            'stop_name': (entry.key < locationNames.length) ? locationNames[entry.key] : 'Stop ${entry.key + 1}',
          }).toList();
      final departureTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
      String backendVehicleType = (selectedVehicleData['vehicle_type'] ?? 'FW').toString();
      String calculatorVehicleType = _mapVehicleTypeForCalculator(backendVehicleType);
      final result = FareCalculator.calculateFare(
        routeStops: routeStops,
        fuelType: selectedVehicleData['fuel_type'] ?? 'Petrol',
        vehicleType: calculatorVehicleType,
        departureTime: departureTime,
        totalSeats: totalSeats,
      );
      autoFareCalculation = Map<String, dynamic>.from(result);
      if (!hasManualAdjustments) {
        manualFareCalculation = Map<String, dynamic>.from(result);
      }
      fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
      dynamicPricePerSeat = (manualFareCalculation['base_fare'] as num?)?.toDouble() ?? 0.0;
      onStateChanged?.call();
    } catch (e) {
      // fallback
      dynamicPricePerSeat = dynamicPricePerSeat == 0.0 ? 500.0 : dynamicPricePerSeat;
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

  void updateTotalPrice(double newTotalPrice) {
    if (manualFareCalculation.isEmpty) {
      if (fareCalculation.isEmpty) return;
      manualFareCalculation = Map<String, dynamic>.from(fareCalculation);
    }
    final stopBreakdown = manualFareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
    if (stopBreakdown.isEmpty) return;
    // simple distribute proportional to existing
    final totalOld = stopBreakdown.fold<double>(0.0, (s, e) => s + ((e['price'] as num?)?.toDouble() ?? 0.0));
    final factor = totalOld == 0.0 ? 0.0 : newTotalPrice / totalOld;
    final updated = stopBreakdown
        .map((e) => {
              ...Map<String, dynamic>.from(e),
              'price': (((e['price'] as num?)?.toDouble() ?? 0.0) * factor),
            })
        .toList();
    manualFareCalculation['stop_breakdown'] = updated;
    manualFareCalculation['total_price'] = newTotalPrice;
    manualFareCalculation['base_fare'] = newTotalPrice;
    dynamicPricePerSeat = newTotalPrice;
    fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
    hasManualAdjustments = true;
    onStateChanged?.call();
  }

  void updateStopPrice(int stopIndex, double newPrice) {
    if (manualFareCalculation.isEmpty) {
      if (fareCalculation.isEmpty) return;
      manualFareCalculation = Map<String, dynamic>.from(fareCalculation);
    }
    final stopBreakdown = manualFareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
    if (stopIndex < 0 || stopIndex >= stopBreakdown.length) return;
    final updated = List<Map<String, dynamic>>.from(stopBreakdown.map((e) => Map<String, dynamic>.from(e)));
    updated[stopIndex]['price'] = newPrice;
    manualFareCalculation['stop_breakdown'] = updated;
    final total = updated.fold<double>(0.0, (s, e) => s + ((e['price'] as num?)?.toDouble() ?? 0.0));
    manualFareCalculation['total_price'] = total;
    manualFareCalculation['base_fare'] = total;
    dynamicPricePerSeat = total;
    fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
    hasManualAdjustments = true;
    onStateChanged?.call();
    onInfo?.call('Updated stop price to ₨${newPrice.toStringAsFixed(2)}');
  }

  void togglePriceNegotiation(bool value) {
    isPriceNegotiable = value;
    onStateChanged?.call();
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

  void applyUpdatedRouteData(Map<String, dynamic> updated) {
    try {
      if (updated['points'] != null) points = List<LatLng>.from(updated['points']);
      if (updated['locationNames'] != null) locationNames = List<String>.from(updated['locationNames']);
      if (updated['routePoints'] != null) routePoints = List<LatLng>.from(updated['routePoints']);
      if (updated['actualRoutePoints'] != null) {
        try {
          actualRoutePoints = List<LatLng>.from(updated['actualRoutePoints']);
        } catch (_) {
          // Keep prior actualRoutePoints on parse issues
        }
      }
      createdRouteId = updated['routeId']?.toString();
      routeDistance = (updated['distance'] as num?)?.toDouble();
      final duration = updated['duration'];
      routeDuration = (duration is int) ? duration : (duration as num?)?.toInt();
      onStateChanged?.call();
      calculateDynamicFare();
    } catch (e) {
      onError?.call('Failed to apply updated route: $e');
    }
  }

  Future<void> updateRide(Map<String, dynamic> userData, String tripId) async {
    try {
      final Map<String, dynamic> payload = {
        'route_id': createdRouteId,
        'vehicle_id': int.parse(selectedVehicle ?? '0'),
        'trip_date': _fmtDate(selectedDate),
        'departure_time': _fmtTime(selectedTime),
        'total_seats': totalSeats,
        'gender_preference': genderPreference ?? 'Any',
        'base_fare': dynamicPricePerSeat,
        'fare_calculation': manualFareCalculation.isNotEmpty ? manualFareCalculation : fareCalculation,
        'auto_fare_calculation': autoFareCalculation,
        'has_manual_adjustments': hasManualAdjustments,
        // Notes/description are optional; never auto-generate from stop names.
        'notes': description.trim(),
        'is_negotiable': isPriceNegotiable,
      };
      if (points.isNotEmpty) {
        payload['route_stops'] = points.asMap().entries.map((e) => {
              'latitude': e.value.latitude,
              'longitude': e.value.longitude,
              'stop_name': (e.key < locationNames.length) ? locationNames[e.key] : 'Stop ${e.key + 1}',
            }).toList();
        payload['route_coordinates'] = points.asMap().entries.map((e) => {
              'lat': e.value.latitude,
              'lng': e.value.longitude,
              'name': (e.key < locationNames.length) ? locationNames[e.key] : 'Stop ${e.key + 1}',
              'order': e.key + 1,
            }).toList();
        payload['route_names'] = List<String>.from(locationNames);
      }
      final stopBreakdownRaw = (manualFareCalculation.isNotEmpty
              ? manualFareCalculation['stop_breakdown']
              : fareCalculation['stop_breakdown']);
      List<Map<String, dynamic>> sb = [];
      if (stopBreakdownRaw is List) {
        sb = List<Map<String, dynamic>>.from(
          stopBreakdownRaw.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }

      // If breakdown missing or any element lacks distance_km, rebuild from points
      bool needsRebuild = sb.isEmpty || sb.any((m) => (m['distance_km'] ?? m['distance']) == null);
      if (needsRebuild && points.length >= 2) {
        final Distance calc = const Distance();
        final List<Map<String, dynamic>> rebuilt = [];
        // Estimate prices proportionally by segment distance if we lack them
        // First compute distances
        final List<double> segKm = [];
        for (int i = 0; i < points.length - 1; i++) {
          final d = calc.as(LengthUnit.Kilometer, points[i], points[i + 1]);
          segKm.add(d.isFinite ? d : 0.0);
        }
        final double totalKm = segKm.fold(0.0, (a, b) => a + b);
        // Determine price per segment: prefer existing prices length, else distribute dynamicPricePerSeat
        List<double> segPrices = [];
        if (sb.length == segKm.length) {
          segPrices = sb.map((m) => ((m['price'] as num?)?.toDouble() ?? 0.0)).toList();
        } else {
          final double totalPrice = (manualFareCalculation['total_price'] as num?)?.toDouble()
              ?? (fareCalculation['total_price'] as num?)?.toDouble()
              ?? dynamicPricePerSeat;
          if (totalKm > 0) {
            for (final dk in segKm) {
              segPrices.add(totalPrice * (dk / totalKm));
            }
          } else {
            // Even split if totalKm is zero
            final split = (points.length - 1) > 0 ? totalPrice / (points.length - 1) : totalPrice;
            segPrices = List<double>.filled(points.length - 1, split);
          }
        }
        for (int i = 0; i < points.length - 1; i++) {
          final fromOrder = i + 1;
          final toOrder = i + 2;
          final fromName = (fromOrder - 1 < locationNames.length) ? locationNames[fromOrder - 1] : 'Stop $fromOrder';
          final toName = (toOrder - 1 < locationNames.length) ? locationNames[toOrder - 1] : 'Stop $toOrder';
          final fromCoords = {'lat': points[i].latitude, 'lng': points[i].longitude};
          final toCoords = {'lat': points[i + 1].latitude, 'lng': points[i + 1].longitude};
          rebuilt.add({
            'from_stop_order': fromOrder,
            'to_stop_order': toOrder,
            'from_stop': fromOrder,
            'to_stop': toOrder,
            'from_stop_name': fromName,
            'to_stop_name': toName,
            'distance_km': segKm[i],
            'distance': segKm[i],
            'duration_minutes': 0,
            'price': i < segPrices.length ? segPrices[i] : 0.0,
            'from_coordinates': fromCoords,
            'to_coordinates': toCoords,
          });
        }
        sb = rebuilt;
      }

      if (sb.isNotEmpty) {

        // Normalize orders, names, coordinates, and field names
        List<Map<String, dynamic>> normalized = [];
        double sumKm = 0.0;
        int sumMin = 0;
        double sumPrice = 0.0;
        for (int i = 0; i < sb.length; i++) {
          final m = sb[i];
          int fromOrder = (m['from_stop_order'] ?? m['from_stop'] ?? (i + 1)) as int;
          int toOrder = (m['to_stop_order'] ?? m['to_stop'] ?? (i + 2)) as int;

          // Clamp to valid range using points length if available
          final maxOrder = points.isNotEmpty ? points.length : (sb.length + 1);
          if (fromOrder < 1) fromOrder = 1;
          if (toOrder < 2) toOrder = 2;
          if (fromOrder > maxOrder) fromOrder = maxOrder - 1;
          if (toOrder > maxOrder) toOrder = maxOrder;

          // Names
          final fromName = m['from_stop_name'] ?? (fromOrder - 1 < locationNames.length ? locationNames[fromOrder - 1] : 'Stop $fromOrder');
          final toName = m['to_stop_name'] ?? (toOrder - 1 < locationNames.length ? locationNames[toOrder - 1] : 'Stop $toOrder');

          // Coordinates
          Map<String, dynamic>? fromCoords = (m['from_coordinates'] as Map?)?.map((k, v) => MapEntry(k.toString(), v));
          Map<String, dynamic>? toCoords = (m['to_coordinates'] as Map?)?.map((k, v) => MapEntry(k.toString(), v));
          if (fromCoords == null && points.isNotEmpty && fromOrder - 1 < points.length) {
            final p = points[fromOrder - 1];
            fromCoords = {'lat': p.latitude, 'lng': p.longitude};
          }
          if (toCoords == null && points.isNotEmpty && toOrder - 1 < points.length) {
            final p = points[toOrder - 1];
            toCoords = {'lat': p.latitude, 'lng': p.longitude};
          }

          // Distances/durations
          final distanceKm = (m['distance_km'] ?? m['distance']) as num?;
          final durationMin = (m['duration_minutes'] ?? m['duration']) as num?;
          final price = (m['price'] as num?)?.toDouble() ?? 0.0;

          // Track totals
          sumKm += (distanceKm?.toDouble() ?? 0.0);
          sumMin += (durationMin?.toInt() ?? 0);
          sumPrice += price;

          normalized.add({
            // Provide both legacy and explicit order fields for backend compatibility
            'from_stop_order': fromOrder,
            'to_stop_order': toOrder,
            'from_stop': fromOrder,
            'to_stop': toOrder,
            'from_stop_name': fromName,
            'to_stop_name': toName,
            'distance_km': (distanceKm?.toDouble() ?? 0.0),
            'distance': (distanceKm?.toDouble() ?? 0.0),
            'duration_minutes': (durationMin?.toInt() ?? 0),
            'price': price,
            'from_coordinates': fromCoords,
            'to_coordinates': toCoords,
          });
        }
        payload['stop_breakdown'] = normalized;
        // Mirror into fare_calculation as some backends read from this path
        try {
          final fc = Map<String, dynamic>.from(payload['fare_calculation'] as Map<String, dynamic>);
          fc['stop_breakdown'] = normalized;
          fc['total_distance_km'] = sumKm;
          fc['total_duration_minutes'] = sumMin;
          fc['total_price'] = sumPrice > 0 ? sumPrice : (payload['base_fare'] as num?)?.toDouble();
          payload['fare_calculation'] = fc;
        } catch (_) {}
      }
      // Debug: log essential fields before PUT
      try {
        debugPrint('[UPDATE_RIDE] route_id=${payload['route_id']} vehicle_id=${payload['vehicle_id']} total_seats=${payload['total_seats']}');
        final sbDbg = (payload['stop_breakdown'] as List?)?.map((e) {
          final m = e as Map<String, dynamic>;
          return {
            'from': m['from_stop_order'],
            'to': m['to_stop_order'],
            'km': m['distance_km'],
            'min': m['duration_minutes'],
            'price': m['price'],
          };
        }).toList();
        debugPrint('[UPDATE_RIDE] stop_breakdown: $sbDbg');
        debugPrint('[UPDATE_RIDE] fare_calculation keys: ${(payload['fare_calculation'] as Map?)?.keys.toList()}');
      } catch (_) {}
      final response = await ApiService.updateTrip(tripId, payload);
      if (response['success'] == true) {
        onSuccess?.call('Ride updated successfully!');
      } else {
        onError?.call('Failed to update ride');
      }
    } catch (e) {
      onError?.call('Error updating ride: $e');
    }
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

  String _fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
