// import 'package:flutter/material.dart';
// import 'package:latlong2/latlong.dart';
// import 'package:intl/intl.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
// import '../../services/api_service.dart';
// import '../../utils/fare_calculator.dart';
// import '../../constants.dart';

// class RideViewEditController {
//   // Route data
//   List<LatLng> points = [];
//   List<String> locationNames = [];
//   List<LatLng> routePoints = [];
//   LatLng? currentPosition;
//   String? createdRouteId;
//   double? routeDistance;
//   int? routeDuration;

//   // Ride details
//   DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
//   TimeOfDay selectedTime = TimeOfDay.now();
//   int totalSeats = 4;
//   String? genderPreference;
//   String? selectedVehicle;
//   String description = '';
//   final List<String> genderOptions = ['Male', 'Female', 'Any'];
//   List<Map<String, dynamic>> userVehicles = [];

//   // Dynamic fare calculation
//   double dynamicPricePerSeat = 0.0;
//   Map<String, dynamic> fareCalculation = {};
//   Map<String, dynamic> autoFareCalculation = {};
//   Map<String, dynamic> manualFareCalculation = {};
//   bool hasManualAdjustments = false;
//   bool isMapLoading = true;

//   // Price negotiation
//   bool isPriceNegotiable = true;

//   // View/Edit mode
//   bool isEditMode = false;
//   String? originalTripId;
//   Map<String, dynamic>? originalRideData;

//   // Callbacks for UI updates
//   VoidCallback? onStateChanged;
//   Function(String)? onError;
//   Function(String)? onSuccess;
//   Function(String)? onInfo;

//   RideViewEditController({
//     this.onStateChanged,
//     this.onError,
//     this.onSuccess,
//     this.onInfo,
//   });

//   // Initialize with existing ride data for view/edit mode
//   void initializeWithRideData(Map<String, dynamic> rideData, bool editMode) {
//     isEditMode = editMode;
//     originalTripId = rideData['trip_id'];
//     originalRideData = Map<String, dynamic>.from(rideData);

//     // Load route data
//     if (rideData['route'] != null) {
//       final route = rideData['route'] as Map<String, dynamic>;
//       createdRouteId = route['id']?.toString();
//       routeDistance = (route['total_distance_km'] as num?)?.toDouble();
//       routeDuration = (route['estimated_duration_minutes'] as num?)?.toInt();

//       // Load route stops (prefer latest list payload fields first)
//       List<dynamic>? stops =
//           (rideData['route_coordinates'] as List<dynamic>?) ??
//           (rideData['route_stops'] as List<dynamic>?) ??
//           (rideData['stops'] as List<dynamic>?) ??
//           (route['route_stops'] as List<dynamic>?) ??
//           (route['stops'] as List<dynamic>?);
//       if (stops != null && stops.isNotEmpty) {
//         points.clear();
//         locationNames.clear();
//         routePoints.clear();

//         for (final raw in stops) {
//           final stop = raw as Map<String, dynamic>;
//           final lat = (stop['latitude'] as num?)?.toDouble() ?? (stop['lat'] as num?)?.toDouble();
//           final lng = (stop['longitude'] as num?)?.toDouble() ?? (stop['lng'] as num?)?.toDouble();
//           // Also support list payload shape: {lat, lng, name}
//           final lat2 = (stop['lat'] as num?)?.toDouble();
//           final lng2 = (stop['lng'] as num?)?.toDouble();
//           final useLat = lat ?? lat2;
//           final useLng = lng ?? lng2;
//           if (useLat != null && useLng != null) {
//             points.add(LatLng(useLat, useLng));
//           }

//   // Properly placed fallback helper at class scope
//   void _rebuildStopsFromBreakdownIfNeeded(Map<String, dynamic> rideData) {
//     try {
//       List<dynamic>? sb;
//       if (fareCalculation['stop_breakdown'] is List && (fareCalculation['stop_breakdown'] as List).isNotEmpty) {
//         sb = List<dynamic>.from(fareCalculation['stop_breakdown']);
//       } else if (rideData['fare_calculation'] is Map &&
//           (rideData['fare_calculation']['stop_breakdown'] is List) &&
//           (rideData['fare_calculation']['stop_breakdown'] as List).isNotEmpty) {
//         sb = List<dynamic>.from(rideData['fare_calculation']['stop_breakdown']);
//       } else if (rideData['stop_breakdown'] is List && (rideData['stop_breakdown'] as List).isNotEmpty) {
//         sb = List<dynamic>.from(rideData['stop_breakdown']);
//       }

//       final segments = sb ?? [];
//       final expectedStops = segments.isNotEmpty ? segments.length + 1 : 0;
//       debugPrint('[EDIT_CTRL] _rebuildStopsFromBreakdownIfNeeded: points=${points.length} expectedStops=$expectedStops');
//       if (expectedStops == 0) return;
//       if (points.length >= expectedStops) return;

//       final List<LatLng> rebuiltPoints = [];
//       final List<String> rebuiltNames = [];
//       for (int i = 0; i < segments.length; i++) {
//         final m = segments[i] as Map<String, dynamic>;
//         if (i == 0) {
//           final from = m['from_coordinates'] as Map<String, dynamic>?;
//           final fromLat = (from?['lat'] as num?)?.toDouble();
//           final fromLng = (from?['lng'] as num?)?.toDouble();
//           if (fromLat != null && fromLng != null) {
//             rebuiltPoints.add(LatLng(fromLat, fromLng));
//             rebuiltNames.add((m['from_stop_name'] ?? 'Stop 1').toString());
//           }
//         }
//         final to = m['to_coordinates'] as Map<String, dynamic>?;
//         final toLat = (to?['lat'] as num?)?.toDouble();
//         final toLng = (to?['lng'] as num?)?.toDouble();
//         if (toLat != null && toLng != null) {
//           rebuiltPoints.add(LatLng(toLat, toLng));
//           rebuiltNames.add((m['to_stop_name'] ?? 'Stop ${i + 2}').toString());
//         }
//       }

//       if (rebuiltPoints.isNotEmpty && rebuiltPoints.length == expectedStops) {
//         debugPrint('[EDIT_CTRL] Fallback rebuilt ${rebuiltPoints.length} stops from breakdown');
//         points = rebuiltPoints;
//         locationNames = rebuiltNames;
//         fetchRoutePoints();
//         onStateChanged?.call();
//       } else {
//         debugPrint('[EDIT_CTRL] Fallback skipped: rebuilt=${rebuiltPoints.length} expected=$expectedStops');
//       }
//     } catch (e) {
//       debugPrint('[EDIT_CTRL] _rebuildStopsFromBreakdownIfNeeded error: $e');
//     }
//   }

//   // If backend list response hasn't updated route geometry yet, rebuild stops
//   // from fare_calculation.stop_breakdown or top-level stop_breakdown.
//   void _maybeRebuildStopsFromBreakdown(Map<String, dynamic> rideData) {
//     try {
//       // Prefer nested fare_calculation
//       List<dynamic>? sb = [];
//       if (fareCalculation['stop_breakdown'] is List &&
//           (fareCalculation['stop_breakdown'] as List).isNotEmpty) {
//         sb = List<dynamic>.from(fareCalculation['stop_breakdown']);
//       } else if (rideData['fare_calculation'] is Map &&
//           (rideData['fare_calculation']['stop_breakdown'] is List) &&
//           (rideData['fare_calculation']['stop_breakdown'] as List).isNotEmpty) {
//         sb = List<dynamic>.from(rideData['fare_calculation']['stop_breakdown']);
//       } else if (rideData['stop_breakdown'] is List &&
//           (rideData['stop_breakdown'] as List).isNotEmpty) {
//         sb = List<dynamic>.from(rideData['stop_breakdown']);
//       }

//       final segments = sb ?? [];
//       final expectedStops = segments.isNotEmpty ? segments.length + 1 : 0;
//       debugPrint('[EDIT_CTRL] _maybeRebuildStopsFromBreakdown: currentPoints=${points.length} expectedStops=$expectedStops');

//       if (expectedStops == 0) return;

//       // If points already match, no need to rebuild
//       if (points.length >= expectedStops) return;

//       final List<LatLng> rebuiltPoints = [];
//       final List<String> rebuiltNames = [];

//       for (int i = 0; i < segments.length; i++) {
//         final m = segments[i] as Map<String, dynamic>;
//         // First segment: add from first
//         if (i == 0) {
//           final from = m['from_coordinates'] as Map<String, dynamic>?;
//           final fromLat = (from?['lat'] as num?)?.toDouble();
//           final fromLng = (from?['lng'] as num?)?.toDouble();
//           if (fromLat != null && fromLng != null) {
//             rebuiltPoints.add(LatLng(fromLat, fromLng));
//             rebuiltNames.add((m['from_stop_name'] ?? 'Stop 1').toString());
//           }
//         }
//         // Append each segment's to
//         final to = m['to_coordinates'] as Map<String, dynamic>?;
//         final toLat = (to?['lat'] as num?)?.toDouble();
//         final toLng = (to?['lng'] as num?)?.toDouble();
//         if (toLat != null && toLng != null) {
//           rebuiltPoints.add(LatLng(toLat, toLng));
//           rebuiltNames.add((m['to_stop_name'] ?? 'Stop ${i + 2}').toString());
//         }
//       }

//       if (rebuiltPoints.isNotEmpty && rebuiltPoints.length == expectedStops) {
//         debugPrint('[EDIT_CTRL] Rebuilding stops from breakdown: ${rebuiltPoints.length} points');
//         points = rebuiltPoints;
//         locationNames = rebuiltNames;
//         // Recalc polyline to reflect geometry
//         fetchRoutePoints();
//         onStateChanged?.call();
//       } else {
//         debugPrint('[EDIT_CTRL] Rebuild skipped: rebuiltPoints=${rebuiltPoints.length}, expected=$expectedStops');
//       }
//     } catch (e) {
//       debugPrint('[EDIT_CTRL] _maybeRebuildStopsFromBreakdown error: $e');
//     }
//   }
//           final name = stop['name'] ?? stop['stop_name'] ?? stop['address'] ?? 'Stop';
//           locationNames.add(name.toString());
//         }

//         // Fetch road-following route points
//         fetchRoutePoints();
//       }

//       // Fallback: If points are fewer than breakdown implies, rebuild from stop_breakdown
//       debugPrint('[EDIT_CTRL] invoke fallback after route parsing (has route object)');
//       _rebuildStopsFromBreakdownIfNeeded(rideData);
//     } else {
//       // Some responses might embed stops at top-level without a route object. Prefer route_coordinates if present.
//       final List<dynamic>? stops = (rideData['route_coordinates'] as List<dynamic>?) ??
//           (rideData['route_stops'] as List<dynamic>?) ??
//           (rideData['stops'] as List<dynamic>?);
//       if (stops != null && stops.isNotEmpty) {
//         points.clear();
//         locationNames.clear();
//         routePoints.clear();
//         for (final raw in stops) {
//           final stop = raw as Map<String, dynamic>;
//           final lat = (stop['latitude'] as num?)?.toDouble() ?? (stop['lat'] as num?)?.toDouble();
//           final lng = (stop['longitude'] as num?)?.toDouble() ?? (stop['lng'] as num?)?.toDouble();
//           if (lat != null && lng != null) {
//             points.add(LatLng(lat, lng));
//           }
//           final name = stop['name'] ?? stop['stop_name'] ?? stop['address'] ?? 'Stop';
//           locationNames.add(name.toString());
//         }
//         fetchRoutePoints();
//       }

//       // Fallback: If points are fewer than breakdown implies, rebuild from stop_breakdown
//       _maybeRebuildStopsFromBreakdown(rideData);
//     }

//     // Load ride details
//     if (rideData['trip_date'] != null) {
//       selectedDate = DateTime.parse(rideData['trip_date']);
//     }
//     if (rideData['departure_time'] != null) {
//       final timeParts = rideData['departure_time'].split(':');
//       selectedTime = TimeOfDay(
//         hour: int.parse(timeParts[0]),
//         minute: int.parse(timeParts[1]),
//       );
//     }

//     totalSeats = rideData['total_seats'] ?? 4;
    
//     // Handle both dedicated gender_preference field and legacy notes field
//     dynamic gp = rideData['gender_preference'];
//     if (gp == null && rideData['notes'] != null) {
//       // Try to extract gender preference from notes if it's a valid value
//       final String notes = rideData['notes'].toString();
//       if (genderOptions.contains(notes)) {
//         gp = notes;
//       }
//     }
    
//     // Validate and set gender preference
//     if (gp is String && genderOptions.contains(gp)) {
//       genderPreference = gp;
//     } else {
//       genderPreference = null;
//     }
    
//     // Use description field if available, otherwise use notes excluding gender preference
//     description = rideData['description'] ?? '';
//     if (description.isEmpty && rideData['notes'] != null) {
//       final String notes = rideData['notes'].toString();
//       if (!genderOptions.contains(notes)) {
//         description = notes;
//       }
//     }
//     dynamicPricePerSeat = (rideData['custom_price'] as num?)?.toDouble() ?? 0.0;

//     // Load fare calculation
//     if (rideData['fare_calculation'] != null) {
//       fareCalculation = Map<String, dynamic>.from(rideData['fare_calculation']);
//     }
//     // If stop breakdown isn't nested inside fare_calculation, pull it from top-level
//     if ((fareCalculation['stop_breakdown'] == null ||
//             (fareCalculation['stop_breakdown'] is List &&
//                 (fareCalculation['stop_breakdown'] as List).isEmpty)) &&
//         rideData['stop_breakdown'] != null) {
//       try {
//         fareCalculation = Map<String, dynamic>.from(fareCalculation);
//         fareCalculation['stop_breakdown'] = List<Map<String, dynamic>>.from(
//           rideData['stop_breakdown'],
//         );
//       } catch (_) {
//         // ignore parsing issues
//       }
//     }
//     // Debug presence/length of breakdowns
//     try {
//       final topLevelLen = (rideData['stop_breakdown'] is List) ? (rideData['stop_breakdown'] as List).length : null;
//       final nestedLen = (fareCalculation['stop_breakdown'] is List) ? (fareCalculation['stop_breakdown'] as List).length : null;
//       debugPrint('[EDIT_CTRL] init: top-level stop_breakdown len=$topLevelLen, nested len=$nestedLen');
//     } catch (_) {}

//     // Load vehicle data
//     if (rideData['vehicle'] != null) {
//       final vehicle = rideData['vehicle'] as Map<String, dynamic>;
//       selectedVehicle = vehicle['id']?.toString();
//     }

//     // Initialize price negotiation from ride data
//     if (rideData['is_negotiable'] != null) {
//       isPriceNegotiable = rideData['is_negotiable'] == true;
//       print('DEBUG: RideViewEditController - Initialized isPriceNegotiable from rideData: $isPriceNegotiable');
//     } else {
//       print('DEBUG: RideViewEditController - No is_negotiable field in rideData, defaulting to: $isPriceNegotiable');
//     }

//     onStateChanged?.call();
//   }

//   // Get current location
//   Future<void> getCurrentLocation() async {
//     try {
//       bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         onError?.call('Location services are disabled');
//         currentPosition = const LatLng(
//           31.5204,
//           74.3587,
//         ); // Default position (Lahore)
//         return;
//       }

//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//         if (permission == LocationPermission.denied) {
//           onError?.call('Location permissions are denied');
//           currentPosition = const LatLng(31.5204, 74.3587);
//           return;
//         }
//       }

//       if (permission == LocationPermission.deniedForever) {
//         onError?.call('Location permissions are permanently denied');
//         currentPosition = const LatLng(31.5204, 74.3587);
//         return;
//       }

//       Position position = await Geolocator.getCurrentPosition();
//       currentPosition = LatLng(position.latitude, position.longitude);
//       onStateChanged?.call();
//     } catch (e) {
//       onError?.call('Error getting location: $e');
//       currentPosition = const LatLng(31.5204, 74.3587);
//       onStateChanged?.call();
//     }
//   }

//   // Load user vehicles
//   Future<void> loadUserVehicles(int userId) async {
//     try {
//       final vehicles = await ApiService.getUserVehicles(userId);
//       userVehicles = vehicles;
//       if (vehicles.isNotEmpty && selectedVehicle == null) {
//         selectedVehicle = vehicles.first['id'].toString();
//         if (vehicles.first['seats'] != null) {
//           totalSeats = (vehicles.first['seats'] as int) - 1;
//         }
//       }
//       onStateChanged?.call();
//       // Auto-calc fare in edit mode once vehicles are available ONLY if no breakdown exists
//       final hasBreakdown = fareCalculation['stop_breakdown'] is List &&
//           (fareCalculation['stop_breakdown'] as List).isNotEmpty;
//       if (isEditMode && !hasBreakdown && points.length >= 2 && selectedVehicle != null) {
//         debugPrint('[EDIT_CTRL] loadUserVehicles: triggering calculateDynamicFare for edit mode (no breakdown present)');
//         calculateDynamicFare();
//       }
//     } catch (e) {
//       onError?.call('Failed to load vehicles: $e');
//     }
//   }

//   // Calculate dynamic fare based on current parameters (auto calculation)
//   void calculateDynamicFare() {
//     if (points.length < 2 || selectedVehicle == null || userVehicles.isEmpty) {
//       return;
//     }

//     try {
//       final selectedVehicleData = userVehicles.firstWhere(
//         (v) => v['id'].toString() == selectedVehicle!,
//         orElse: () => userVehicles.first,
//       );

//       final routeStops = points.asMap().entries.map((entry) {
//         return {
//           'latitude': entry.value.latitude,
//           'longitude': entry.value.longitude,
//           'stop_name':
//               locationNames.isNotEmpty && entry.key < locationNames.length
//               ? locationNames[entry.key]
//               : 'Stop ${entry.key + 1}',
//         };
//       }).toList();

//       final departureTime = DateTime(
//         selectedDate.year,
//         selectedDate.month,
//         selectedDate.day,
//         selectedTime.hour,
//         selectedTime.minute,
//       );

//       // Map backend vehicle type codes to calculator categories
//       String backendVehicleType = (selectedVehicleData['vehicle_type'] ?? 'FW')
//           .toString();
//       String calculatorVehicleType = _mapVehicleTypeForCalculator(
//         backendVehicleType,
//       );

//       debugPrint('[EDIT_CTRL] calculateDynamicFare: routeStops count=${routeStops.length}');
//       final result = FareCalculator.calculateFare(
//         routeStops: routeStops,
//         fuelType: selectedVehicleData['fuel_type'] ?? 'Petrol',
//         vehicleType: calculatorVehicleType,
//         departureTime: departureTime,
//         totalSeats: totalSeats,
//       );

//       autoFareCalculation = Map<String, dynamic>.from(result);
//       // if previously had manual edits, keep them; else mirror auto
//       if (hasManualAdjustments && manualFareCalculation.isNotEmpty) {
//         // keep manual as-is
//       } else {
//         manualFareCalculation = Map<String, dynamic>.from(result);
//         hasManualAdjustments = false;
//       }
//       fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
//       dynamicPricePerSeat = (manualFareCalculation['base_fare'] as num?)?.toDouble() ?? 0.0;
//       debugPrint('[EDIT_CTRL] Auto base=${autoFareCalculation['base_fare']} total=${autoFareCalculation['total_price']}');
//       final sb = (autoFareCalculation['stop_breakdown'] as List<dynamic>? ?? []).map((e) => (e['price'] ?? 0.0)).toList();
//       debugPrint('[EDIT_CTRL] Auto stop prices=${sb}');
//       debugPrint('[EDIT_CTRL] Exposed fareCalc total=${fareCalculation['total_price']} dynamicPricePerSeat=$dynamicPricePerSeat');
//       onStateChanged?.call();
//     } catch (e) {
//       dynamicPricePerSeat = 500.0;
//       autoFareCalculation = {
//         'base_fare': 500.0,
//         'total_distance_km': 0.0,
//         'total_duration_minutes': 0,
//         'stop_breakdown': [],
//         'calculation_breakdown': {},
//       };
//       manualFareCalculation = Map<String, dynamic>.from(autoFareCalculation);
//       fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
//       hasManualAdjustments = false;
//       onStateChanged?.call();
//     }
//   }

//   String _mapVehicleTypeForCalculator(String? backendType) {
//     switch ((backendType ?? '').toUpperCase()) {
//       case 'TW':
//         return 'Motorcycle';
//       case 'FW':
//         return 'Sedan';
//       default:
//         return backendType ?? 'Sedan';
//     }
//   }

//   // Update total price and distribute across stops (manual adjustment)
//   void updateTotalPrice(double newTotalPrice) {
//     if (manualFareCalculation.isEmpty) return;

//     final stopBreakdown =
//         manualFareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
//     if (stopBreakdown.isEmpty) return;

//     final updatedBreakdown = FareCalculator.distributeTotalPrice(
//       stopBreakdown.cast<Map<String, dynamic>>(),
//       newTotalPrice,
//     );

//     manualFareCalculation = Map<String, dynamic>.from(manualFareCalculation);
//     manualFareCalculation['stop_breakdown'] = updatedBreakdown;
//     manualFareCalculation['total_price'] = newTotalPrice;
//     manualFareCalculation['base_fare'] = newTotalPrice;

//     dynamicPricePerSeat = newTotalPrice;

//     final breakdown =
//         manualFareCalculation['calculation_breakdown'] as Map<String, dynamic>? ?? {};
//     breakdown['total_price'] = newTotalPrice;
//     manualFareCalculation['calculation_breakdown'] = breakdown;

//     fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
//     hasManualAdjustments = true;
//     debugPrint('[EDIT_CTRL] updateTotalPrice -> newTotal=$newTotalPrice');
//     debugPrint('[EDIT_CTRL] stop prices after distribute=${updatedBreakdown.map((e) => e['price']).toList()}');
//     debugPrint('[EDIT_CTRL] exposed total=${fareCalculation['total_price']}');

//     onStateChanged?.call();
//   }

//   // Update individual stop price (manual adjustment)
//   void updateStopPrice(int stopIndex, double newPrice) {
//     if (manualFareCalculation.isEmpty) return;

//     final stopBreakdown =
//         manualFareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
//     if (stopIndex < 0 || stopIndex >= stopBreakdown.length) return;

//     final updatedBreakdown = FareCalculator.updateStopPriceOnly(
//       stopBreakdown.cast<Map<String, dynamic>>(),
//       stopIndex,
//       newPrice,
//     );

//     manualFareCalculation = Map<String, dynamic>.from(manualFareCalculation);
//     manualFareCalculation['stop_breakdown'] = updatedBreakdown;

//     double calculatedTotal = updatedBreakdown.fold(
//       0.0,
//       (sum, stop) => sum + (stop['price'] ?? 0.0),
//     );

//     manualFareCalculation['total_price'] = calculatedTotal;
//     manualFareCalculation['base_fare'] = calculatedTotal;
//     dynamicPricePerSeat = calculatedTotal;

//     final breakdown =
//         manualFareCalculation['calculation_breakdown'] as Map<String, dynamic>? ?? {};
//     breakdown['total_price'] = calculatedTotal;
//     manualFareCalculation['calculation_breakdown'] = breakdown;

//     fareCalculation = Map<String, dynamic>.from(manualFareCalculation);
//     hasManualAdjustments = true;
//     debugPrint('[EDIT_CTRL] updateStopPrice -> index=$stopIndex newPrice=$newPrice');
//     debugPrint('[EDIT_CTRL] stop prices now=${updatedBreakdown.map((e) => e['price']).toList()}');
//     debugPrint('[EDIT_CTRL] new total=$calculatedTotal exposed total=${fareCalculation['total_price']}');

//     onStateChanged?.call();
//     onInfo?.call('Updated stop price to ₨${newPrice.toStringAsFixed(2)}');
//   }

//   // Update ride details
//   void updateSelectedDate(DateTime date) {
//     selectedDate = date;
//     onStateChanged?.call();
//     if (isEditMode) calculateDynamicFare();
//   }

//   void updateSelectedTime(TimeOfDay time) {
//     selectedTime = time;
//     onStateChanged?.call();
//     if (isEditMode) calculateDynamicFare();
//   }

//   void updateTotalSeats(int seats) {
//     totalSeats = seats;
//     onStateChanged?.call();
//     if (isEditMode) calculateDynamicFare();
//   }

//   void updateGenderPreference(String? preference) {
//     genderPreference = preference;
//     onStateChanged?.call();
//   }

//   void updateSelectedVehicle(String? vehicleId) {
//     selectedVehicle = vehicleId;
//     if (vehicleId != null) {
//       final vehicle = userVehicles.firstWhere(
//         (v) => v['id'].toString() == vehicleId,
//         orElse: () => userVehicles.first,
//       );
//       if (vehicle['seats'] != null) {
//         totalSeats = (vehicle['seats'] as int) - 1;
//       }
//     }
//     onStateChanged?.call();
//     if (isEditMode) calculateDynamicFare();
//   }

//   void updateDescription(String desc) {
//     description = desc;
//     onStateChanged?.call();
//   }

//   // Toggle price negotiation
//   void togglePriceNegotiation(bool value) {
//     print('DEBUG: RideViewEditController - togglePriceNegotiation called with value: $value');
//     print('DEBUG: RideViewEditController - isPriceNegotiable before: $isPriceNegotiable');
//     isPriceNegotiable = value;
//     print('DEBUG: RideViewEditController - isPriceNegotiable after: $isPriceNegotiable');
//     onStateChanged?.call();
//   }

//   // Set map loading state
//   void setMapLoading(bool loading) {
//     isMapLoading = loading;
//     onStateChanged?.call();
//   }

//   // Update ride via API
//   Future<void> updateRide(Map<String, dynamic> userData) async {
//     if (originalTripId == null) {
//       onError?.call('No ride ID found for update');
//       return;
//     }

//     if (selectedVehicle == null) {
//       onError?.call('Please select a vehicle');
//       return;
//     }

//     if (totalSeats <= 0) {
//       onError?.call('Please select at least 1 seat');
//       return;
//     }

//     try {
//       final Map<String, dynamic> payload = {
//         // Ensure backend ties the trip to the updated route
//         'route_id': createdRouteId,
//         'vehicle_id': int.parse(selectedVehicle!),
//         'trip_date': DateFormat('yyyy-MM-dd').format(selectedDate),
//         'departure_time':
//             '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
//         'total_seats': totalSeats,
//         'gender_preference': genderPreference,
//         // Backend update expects 'base_fare' (not 'custom_price')
//         'base_fare': dynamicPricePerSeat,
//         'fare_calculation': manualFareCalculation,
//         'auto_fare_calculation': autoFareCalculation,
//         'has_manual_adjustments': hasManualAdjustments,
//         'notes': description.isNotEmpty
//             ? description
//             : (locationNames.isNotEmpty
//                   ? locationNames.join(' → ')
//                   : 'Custom route'),
//         'is_negotiable': isPriceNegotiable,
//       };

//       // Persist the latest stops geometry so View screen map reflects changes
//       if (points.isNotEmpty) {
//         payload['route_stops'] = points.asMap().entries.map((entry) {
//           final i = entry.key;
//           final p = entry.value;
//           final name = (i < locationNames.length) ? locationNames[i] : 'Stop ${i + 1}';
//           return {
//             'latitude': p.latitude,
//             'longitude': p.longitude,
//             'stop_name': name,
//           };
//         }).toList();

//         // Also provide list-response friendly fields so MyRides/View screens get updated data
//         payload['route_coordinates'] = points.asMap().entries.map((entry) {
//           final i = entry.key;
//           final p = entry.value;
//           final name = (i < locationNames.length) ? locationNames[i] : 'Stop ${i + 1}';
//           return {
//             'lat': p.latitude,
//             'lng': p.longitude,
//             'name': name,
//             'order': i + 1,
//           };
//         }).toList();
//         payload['route_names'] = List<String>.from(locationNames);
//       }

//       print('DEBUG: RideViewEditController - Update payload is_negotiable: ${payload['is_negotiable']}');
//       print('DEBUG: RideViewEditController - Current isPriceNegotiable state: $isPriceNegotiable');

//       // Persist edited per-stop prices just like creation flow
//       final stopBreakdown = fareCalculation['stop_breakdown'];
//       if (stopBreakdown is List) {
//         payload['stop_breakdown'] = List<Map<String, dynamic>>.from(
//           stopBreakdown,
//         );
//       }

//       final response = await ApiService.updateTrip(originalTripId!, payload);

//       if (response['success']) {
//         onSuccess?.call('Ride updated successfully!');
//       } else {
//         onError?.call('Failed to update ride: ${response['error']}');
//       }
//     } catch (e) {
//       onError?.call('Error updating ride: $e');
//     }
//   }

//   // Cancel ride via API
//   Future<void> cancelRide(String tripId, {String? reason}) async {
//     try {
//       final response = await ApiService.cancelTrip(
//         tripId,
//         reason: reason ?? 'Cancelled by driver',
//       );

//       if (response['success']) {
//         onSuccess?.call('Ride cancelled successfully');
//       } else {
//         onError?.call('Failed to cancel ride: ${response['error']}');
//       }
//     } catch (e) {
//       onError?.call('Error cancelling ride: $e');
//     }
//   }

//   // Get ride data for API calls
//   Map<String, dynamic> getRideData() {
//     return {
//       'routeId': createdRouteId,
//       'vehicleId': selectedVehicle,
//       'tripDate': DateFormat('yyyy-MM-dd').format(selectedDate),
//       'departureTime':
//           '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
//       'totalSeats': totalSeats,
//       'genderPreference': genderPreference,
//       'customPrice': dynamicPricePerSeat,
//       'fareCalculation': fareCalculation,
//       'description': description,
//       'isPriceNegotiable': isPriceNegotiable,
//     };
//   }

//   // Get route data for navigation
//   Map<String, dynamic> getRouteData() {
//     return {
//       'points': points,
//       'locationNames': locationNames,
//       'routePoints': routePoints,
//       'routeId': createdRouteId,
//       'distance': routeDistance,
//       'duration': routeDuration,
//     };
//   }

//   // Apply updated route data coming back from route editor
//   void applyUpdatedRouteData(Map<String, dynamic> updated) {
//     try {
//       if (updated['points'] != null) {
//         points = List<LatLng>.from(updated['points']);
//       }
//       if (updated['locationNames'] != null) {
//         locationNames = List<String>.from(updated['locationNames']);
//       }
//       if (updated['routePoints'] != null) {
//         routePoints = List<LatLng>.from(updated['routePoints']);
//       } else {
//         // Instead of copying points directly, fetch road-following route
//         fetchRoutePoints();
//       }
//       createdRouteId = updated['routeId']?.toString();
//       routeDistance = (updated['distance'] as num?)?.toDouble();
//       // Ensure routeDuration is always an integer
//       final duration = updated['duration'];
//       if (duration != null) {
//         routeDuration = (duration is int) ? duration : (duration as num).toInt();
//       } else {
//         // Default duration based on distance if not provided
//         routeDuration = routeDistance != null ? (routeDistance! / 50 * 60).round() : 0;
//       }
//       onStateChanged?.call();
//       // Recalculate fare against the updated geometry in edit mode
//       if (isEditMode) calculateDynamicFare();
//     } catch (e) {
//       onError?.call('Failed to apply updated route: $e');
//     }
//   }

//   // Fetch road-following route points using OpenRouteService
//   Future<void> fetchRoutePoints() async {
//     if (points.length < 2) return;
    
//     try {
//       final coords = points.map((p) => [p.longitude, p.latitude]).toList();
      
//       final url = Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson');
      
//       final response = await http.post(
//         url,
//         headers: {
//           'Authorization': orsApiKey,
//           'Content-Type': 'application/json',
//         },
//         body: jsonEncode({
//           'coordinates': coords,
//         }),
//       );
      
//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
        
//         if (data['features'] != null && data['features'].isNotEmpty) {
//           final List<dynamic> routeCoords = data['features'][0]['geometry']['coordinates'];
          
//           routePoints = routeCoords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
//           onStateChanged?.call();
//         } else {
//           // Fallback to direct line if no route found
//           routePoints = List<LatLng>.from(points);
//           onStateChanged?.call();
//         }
//       } else {
//         // Fallback to direct line if API fails
//         routePoints = List<LatLng>.from(points);
//         onStateChanged?.call();
//       }
//     } catch (e) {
//       // Fallback to direct line on error
//       routePoints = List<LatLng>.from(points);
//       onStateChanged?.call();
//     }
//   }

//   // Dispose method for cleanup
//   void dispose() {
//     // Clean up any resources if needed in the future
//   }
// }
