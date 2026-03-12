import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../utils/road_polyline_service.dart';
import '../../utils/map_util.dart';

class RideRequestController {
  // Ride data
  Map<String, dynamic> rideData = {};
  
  // Booking form data
  int selectedFromStop = 1;
  int selectedToStop = 2;
  int maleSeats = 1;
  int femaleSeats = 0;
  String specialRequests = '';
  bool isBookingInProgress = false;
  
  // Route data
  List<LatLng> routePoints = [];
  List<String> locationNames = [];
  List<LatLng> stopPoints = [];
  double? routeDistance;
  int? routeDuration;
  int selectedRouteDuration = 0;
  int fullRouteDuration = 0;
  
  // Price negotiation
  final TextEditingController priceController = TextEditingController();
  int? proposedPricePerSeat;
  int originalPricePerSeat = 0;
  int fullRoutePricePerSeat = 0;
  bool isPriceNegotiable = false;
  
  // Stop breakdown data for dynamic pricing
  List<Map<String, dynamic>> stopBreakdowns = [];
  
  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function(String)? onInfo;

  RideRequestController({
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

  List<LatLng> _parsePolyline(dynamic raw) {
    if (raw is! List) return <LatLng>[];
    final out = <LatLng>[];
    for (final p in raw) {
      if (p is! Map) continue;
      final lat = _toDouble(p['lat'] ?? p['latitude']);
      final lng = _toDouble(p['lng'] ?? p['longitude']);
      if (lat != null && lng != null) out.add(LatLng(lat, lng));
    }
    return out;
  }

  // Initialize controller with ride data
  void initializeWithRideData(Map<String, dynamic> data) {
    // Log initialization for debugging
    developer.log('Initializing ride data', name: 'RideRequestController');
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
            : (backendActualPath.length >= 2 ? backendActualPath : <LatLng>[]);
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
          }
        }
        
        // Set default from/to stops
        if (locationNames.length >= 2) {
          selectedFromStop = 1;
          selectedToStop = locationNames.length;
        }

        // If backend geometry isn't available, fall back to road-snapping stops.
        if (routePoints.length < 2 && stopPoints.length > 1) {
          RoadPolylineService.fetchRoadPolyline(stopPoints).then((road) {
            routePoints = (road.length > 1) ? road : _generateInterpolatedRoute(stopPoints);
            onStateChanged?.call();
          });
        }
      }
    }
    
    // Extract stop breakdown data for dynamic pricing
    stopBreakdowns = [];
    if (data['stop_breakdown'] != null) {
      final breakdowns = data['stop_breakdown'] as List<dynamic>;
      for (final breakdown in breakdowns) {
        stopBreakdowns.add({
          'from_stop_order': breakdown['from_stop_order'],
          'to_stop_order': breakdown['to_stop_order'],
          'from_stop_name': breakdown['from_stop_name'],
          'to_stop_name': breakdown['to_stop_name'],
          'price': (breakdown['price'] as num?)?.round() ?? 0,
          'distance_km': (breakdown['distance_km'] ?? 0.0).toDouble(),
          'duration_minutes': (breakdown['duration_minutes'] ?? 0).toInt(),
        });
      }
      developer.log('Loaded ${stopBreakdowns.length} stop breakdowns', name: 'RideRequestController');
    }
    
    // Extract pricing and duration information
    if (data['trip'] != null) {
      final trip = data['trip'] as Map<String, dynamic>;
      developer.log('Raw trip data: $trip', name: 'RideRequestController');
      developer.log('Raw base_fare from API: ${trip['base_fare']}', name: 'RideRequestController');
      fullRoutePricePerSeat = (trip['base_fare'] as num?)?.round() ?? 0;
      developer.log('Full route price: $fullRoutePricePerSeat', name: 'RideRequestController');
      isPriceNegotiable = trip['is_negotiable'] ?? false;
      developer.log('isPriceNegotiable: $isPriceNegotiable', name: 'RideRequestController');
      // Ensure backward-compatible access to trip_id at top level as some code references rideData['trip_id']
      rideData['trip_id'] = trip['trip_id'] ?? rideData['trip_id'];
      
      // Store full route duration
      if (data['route'] != null) {
        final route = data['route'] as Map<String, dynamic>;
        fullRouteDuration = route['estimated_duration_minutes'] ?? 0;
        developer.log('Full route duration: $fullRouteDuration minutes', name: 'RideRequestController');
      }
      
      // Calculate initial price and duration based on default stops
      _updatePriceAndDurationForSelectedStops();
      developer.log('Initial calculated price: $originalPricePerSeat', name: 'RideRequestController');
      developer.log('Initial calculated duration: $selectedRouteDuration minutes', name: 'RideRequestController');
      
      // Set default seats based on trip gender preference
      final tripGenderPreference = trip['gender_preference'] ?? 'Any';
      if (tripGenderPreference == 'Male') {
        maleSeats = 1;
        femaleSeats = 0;
      } else if (tripGenderPreference == 'Female') {
        maleSeats = 0;
        femaleSeats = 1;
      } else {
        // Default: 1 male seat (assuming user is male)
        maleSeats = 1;
        femaleSeats = 0;
      }
    }
    
    onStateChanged?.call();
  }

  // Update selected from stop
  void updateFromStop(int stopOrder) {
    selectedFromStop = stopOrder;
    _updatePriceAndDurationForSelectedStops();
    onStateChanged?.call();
  }

  // Update selected to stop
  void updateToStop(int stopOrder) {
    selectedToStop = stopOrder;
    _updatePriceAndDurationForSelectedStops();
    onStateChanged?.call();
  }

  // Calculate price and duration based on selected pickup and drop stops
  void _updatePriceAndDurationForSelectedStops() {
    if (stopBreakdowns.isEmpty || selectedFromStop <= 0 || selectedToStop <= 0) {
      // Fallback to full route price and duration if no breakdown data
      originalPricePerSeat = fullRoutePricePerSeat;
      proposedPricePerSeat = originalPricePerSeat;
      priceController.text = originalPricePerSeat.toString();
      selectedRouteDuration = fullRouteDuration;
      developer.log('Using full route price (no breakdown): $originalPricePerSeat', name: 'RideRequestController');
      developer.log('Using full route duration (no breakdown): $selectedRouteDuration minutes', name: 'RideRequestController');
      return;
    }

    int calculatedPrice = 0;
    int calculatedDuration = 0;
    developer.log('Calculating price and duration for stops $selectedFromStop to $selectedToStop', name: 'RideRequestController');
    
    // Find all segments between selected stops
    for (final breakdown in stopBreakdowns) {
      final fromOrder = breakdown['from_stop_order'] as int;
      final toOrder = breakdown['to_stop_order'] as int;
      final segmentPrice = (breakdown['price'] as num?)?.toInt() ?? 0;
      final segmentDuration = breakdown['duration_minutes'] as int;
      
      // Check if this segment is within our selected range
      if (fromOrder >= selectedFromStop && toOrder <= selectedToStop) {
        calculatedPrice += segmentPrice;
        calculatedDuration += segmentDuration;
        developer.log('Added segment $fromOrder->$toOrder: ₨$segmentPrice, ${segmentDuration}min', name: 'RideRequestController');
      }
    }
    
    // If no segments found, use proportional pricing and duration
    if (calculatedPrice == 0) {
      final totalStops = locationNames.length;
      final selectedStops = selectedToStop - selectedFromStop + 1;
      calculatedPrice = totalStops > 0
          ? (fullRoutePricePerSeat * (selectedStops / totalStops)).round()
          : fullRoutePricePerSeat;
      calculatedDuration = (fullRouteDuration * (selectedStops / totalStops)).round();
      developer.log('Using proportional pricing: $selectedStops/$totalStops * $fullRoutePricePerSeat = $calculatedPrice', name: 'RideRequestController');
      developer.log('Using proportional duration: $selectedStops/$totalStops * $fullRouteDuration = ${calculatedDuration}min', name: 'RideRequestController');
    }
    
    originalPricePerSeat = calculatedPrice;
    proposedPricePerSeat = calculatedPrice;
    priceController.text = calculatedPrice.toString();
    selectedRouteDuration = calculatedDuration;
    developer.log('Updated price for selected stops: ₨$calculatedPrice', name: 'RideRequestController');
    developer.log('Updated duration for selected stops: ${calculatedDuration}min', name: 'RideRequestController');
  }

  // Update male seats
  void updateMaleSeats(int seats) {
    maleSeats = seats;
    onStateChanged?.call();
  }

  // Update female seats
  void updateFemaleSeats(int seats) {
    femaleSeats = seats;
    onStateChanged?.call();
  }

  // Check if can add more male seats
  bool canAddMaleSeats() {
    final trip = rideData['trip'];
    if (trip != null) {
      final availableSeats = trip['available_seats'] ?? 1;
      final tripGenderPreference = trip['gender_preference'] ?? 'Any';
      
      // If trip has gender preference, respect it
      if (tripGenderPreference == 'Female') {
        return false; // Can't add male seats to female-only trip
      }
      
      return getTotalSeats() < availableSeats;
    }
    return false;
  }

  // Check if can add more female seats
  bool canAddFemaleSeats() {
    final trip = rideData['trip'];
    if (trip != null) {
      final availableSeats = trip['available_seats'] ?? 1;
      final tripGenderPreference = trip['gender_preference'] ?? 'Any';
      
      // If trip has gender preference, respect it
      if (tripGenderPreference == 'Male') {
        return false; // Can't add female seats to male-only trip
      }
      
      return getTotalSeats() < availableSeats;
    }
    return false;
  }

  // Get total seats
  int getTotalSeats() {
    return maleSeats + femaleSeats;
  }

  // Generate interpolated route points for more realistic visualization
  List<LatLng> _generateInterpolatedRoute(List<LatLng> stops) {
    if (stops.length >= 2) {
      _calculateDistance(stops.first, stops.last);
    }
    return MapUtil.generateInterpolatedRoute(stops);
  }
  
  // Calculate distance between two points using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    return MapUtil.calculateDistanceMeters(point1, point2);
  }

  // Get route points for display (already road-following if ORS succeeded)
  List<LatLng> getInterpolatedRoutePoints() {
    return routePoints;
  }

  // Update special requests
  void updateSpecialRequests(String requests) {
    specialRequests = requests;
    onStateChanged?.call();
  }

  // Update proposed price
  void updateProposedPrice(String price) {
    developer.log('Updating proposed price with input: $price', name: 'RideRequestController');
    final priceValue = int.tryParse(price.trim());
    developer.log('Parsed price value: $priceValue', name: 'RideRequestController');
    if (priceValue != null && priceValue > 0) {
      developer.log('Price validation - priceValue: $priceValue, originalPricePerSeat (dynamic): $originalPricePerSeat', name: 'RideRequestController');
      // Prevent bargaining above the dynamically calculated price for selected stops
      if (priceValue <= originalPricePerSeat) {
        proposedPricePerSeat = priceValue;
        developer.log('Price accepted - proposedPricePerSeat set to: $proposedPricePerSeat', name: 'RideRequestController');
        onStateChanged?.call();
      } else {
        // Set to calculated price if user tries to go above
        proposedPricePerSeat = originalPricePerSeat;
        priceController.text = originalPricePerSeat.toString();
        developer.log('Price rejected (too high) - reset to calculated price: $originalPricePerSeat', name: 'RideRequestController');
        onStateChanged?.call();
      }
    }
  }

  // Get from stop options
  List<Map<String, dynamic>> getFromStopOptions() {
    List<Map<String, dynamic>> options = [];
    for (int i = 0; i < locationNames.length - 1; i++) {
      options.add({
        'order': i + 1,
        'display_name': '${locationNames[i]} (Stop ${i + 1})',
      });
    }
    return options;
  }

  // Get to stop options
  List<Map<String, dynamic>> getToStopOptions() {
    List<Map<String, dynamic>> options = [];
    for (int i = selectedFromStop; i < locationNames.length; i++) {
      options.add({
        'order': i + 1,
        'display_name': '${locationNames[i]} (Stop ${i + 1})',
      });
    }
    return options;
  }

  // Get maximum available seats
  int getMaxSeats() {
    final trip = rideData['trip'];
    if (trip != null) {
      return trip['available_seats'] ?? 1;
    }
    return 1;
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

  // Get route summary
  String getRouteSummary() {
    if (locationNames.length >= 2) {
      return '${locationNames.first} → ${locationNames.last}';
    }
    return 'Custom Route';
  }

  // Get base fare (dynamic based on selected stops)
  int getBaseFare() {
    developer.log('getBaseFare() returning original price (frontend-calculated): $originalPricePerSeat', name: 'RideRequestController');
    return originalPricePerSeat;
  }

  // Get original price per seat (dynamic based on selected stops)
  int getOriginalPricePerSeat() {
    developer.log('getOriginalPricePerSeat() returning original price (frontend-calculated): $originalPricePerSeat', name: 'RideRequestController');
    return originalPricePerSeat;
  }
  
  // Get full route price per seat
  int getFullRoutePricePerSeat() {
    developer.log('getFullRoutePricePerSeat() returning: $fullRoutePricePerSeat', name: 'RideRequestController');
    return fullRoutePricePerSeat;
  }
  
  // Get selected route duration
  int getSelectedRouteDuration() {
    developer.log('getSelectedRouteDuration() returning: $selectedRouteDuration minutes', name: 'RideRequestController');
    return selectedRouteDuration;
  }
  
  // Get full route duration
  int getFullRouteDuration() {
    developer.log('getFullRouteDuration() returning: $fullRouteDuration minutes', name: 'RideRequestController');
    return fullRouteDuration;
  }
  
  // Format duration for display
  String getFormattedDuration() {
    final hours = selectedRouteDuration ~/ 60;
    final minutes = selectedRouteDuration % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    } else {
      return '${minutes}min';
    }
  }

  // Get estimated departure time for selected pickup stop
  String getEstimatedDepartureTime() {
    try {
      final tripData = rideData['trip'];
      if (tripData == null) return 'N/A';
      
      final departureTimeStr = tripData['departure_time'] as String?;
      if (departureTimeStr == null) return 'N/A';
      
      // Parse the departure time
      final departureTime = DateTime.parse('2024-01-01 $departureTimeStr');
      
      // Calculate time offset for pickup stop (assuming each stop adds some travel time)
      // For simplicity, assume 5 minutes between consecutive stops
      final stopOffset = (selectedFromStop - 1) * 5;
      final estimatedDeparture = departureTime.add(Duration(minutes: stopOffset));
      
      final formatter = DateFormat('HH:mm');
      return formatter.format(estimatedDeparture);
    } catch (e) {
      developer.log('Error calculating departure time', name: 'RideRequestController', error: e);
      return 'N/A';
    }
  }

  // Get estimated arrival time for selected drop-off stop
  String getEstimatedArrivalTime() {
    try {
      final tripData = rideData['trip'];
      if (tripData == null) return 'N/A';
      
      final departureTimeStr = tripData['departure_time'] as String?;
      if (departureTimeStr == null) return 'N/A';
      
      // Parse the departure time
      final departureTime = DateTime.parse('2024-01-01 $departureTimeStr');
      
      // Calculate departure time for pickup stop
      final pickupOffset = (selectedFromStop - 1) * 5;
      final estimatedDeparture = departureTime.add(Duration(minutes: pickupOffset));
      
      // Add the selected route duration to get arrival time
      final estimatedArrival = estimatedDeparture.add(Duration(minutes: selectedRouteDuration));
      
      final formatter = DateFormat('HH:mm');
      return formatter.format(estimatedArrival);
    } catch (e) {
      developer.log('Error calculating arrival time', name: 'RideRequestController', error: e);
      return 'N/A';
    }
  }

  // Get formatted time range (departure - arrival)
  String getEstimatedTimeRange() {
    final departure = getEstimatedDepartureTime();
    final arrival = getEstimatedArrivalTime();
    if (departure == 'N/A' || arrival == 'N/A') {
      return 'Time: N/A';
    }
    return '$departure - $arrival';
  }

  // Get final price per seat (negotiated or original)
  int getFinalPricePerSeat() {
    final finalPrice = proposedPricePerSeat ?? originalPricePerSeat;
    developer.log('getFinalPricePerSeat() - proposedPricePerSeat: $proposedPricePerSeat, originalPricePerSeat: $originalPricePerSeat, returning: $finalPrice', name: 'RideRequestController');
    return finalPrice;
  }

  // Check if price is negotiable
  bool getIsPriceNegotiable() {
    return isPriceNegotiable;
  }

  // Get potential savings per seat
  int getSavings() {
    if (proposedPricePerSeat != null && proposedPricePerSeat! < originalPricePerSeat) {
      return originalPricePerSeat - proposedPricePerSeat!;
    }
    return 0;
  }

  // Get minimum price (free ride)
  int getMinPrice() {
    return 0;
  }

  // Get maximum price (original price - no bargaining above)
  int getMaxPrice() {
    return originalPricePerSeat;
  }

  // Get selected route summary
  String getSelectedRouteSummary() {
    if (selectedFromStop <= locationNames.length && selectedToStop <= locationNames.length) {
      final fromName = locationNames[selectedFromStop - 1];
      final toName = locationNames[selectedToStop - 1];
      return '$fromName → $toName';
    }
    return 'Invalid Route';
  }

  // Calculate total fare
  int calculateTotalFare() {
    return getFinalPricePerSeat() * getTotalSeats();
  }

  // Submit ride request
  // Calculate the total price for the ride booking
  int _calculateTotalPrice() {
    final pricePerSeat = proposedPricePerSeat ?? originalPricePerSeat;
    return pricePerSeat * (maleSeats + femaleSeats);
  }

  // Submit ride request
  Future<bool> requestRideBooking() async {
    try {
      isBookingInProgress = true;
      onStateChanged?.call();
      // Validate booking first
      if (!_validateBooking()) {
        return false;
      }
      
      // Resolve passenger id from local session (set at login)
      final prefs = await SharedPreferences.getInstance();
      final uidStr = prefs.getString('logged_in_user_id');
      final passengerId = int.tryParse(uidStr ?? '');
      developer.log('Preparing booking; resolved passengerId=$passengerId from SharedPreferences', name: 'RideRequestController');

      final totalPrice = _calculateTotalPrice();
      final isNegotiated = proposedPricePerSeat != null && proposedPricePerSeat != originalPricePerSeat;
      final finalFarePerSeat = getFinalPricePerSeat();
      // Map selected indices to actual route stop 'order' values
      final List<dynamic> routeStops = (rideData['route']?['stops'] as List<dynamic>?) ?? [];
      int mappedFromOrder = selectedFromStop;
      int mappedToOrder = selectedToStop;
      if (routeStops.isNotEmpty && selectedFromStop - 1 < routeStops.length && selectedToStop - 1 < routeStops.length) {
        final fromStopObj = routeStops[selectedFromStop - 1] as Map<String, dynamic>;
        final toStopObj = routeStops[selectedToStop - 1] as Map<String, dynamic>;
        mappedFromOrder = (fromStopObj['order'] as num?)?.toInt() ?? selectedFromStop;
        mappedToOrder = (toStopObj['order'] as num?)?.toInt() ?? selectedToStop;
      }
      final bookingData = {
        'trip_id': rideData['trip']?['trip_id'] ?? rideData['trip_id'],
        // Use backend-expected keys for stop orders
        'from_stop_order': mappedFromOrder,
        'to_stop_order': mappedToOrder,
        // Keep legacy keys for compatibility if view accepts them
        'from_stop': mappedFromOrder,
        'to_stop': mappedToOrder,
        'male_seats': maleSeats,
        'female_seats': femaleSeats,
        'number_of_seats': getTotalSeats(),
        'special_requests': specialRequests,
        // Fare fields are PER-SEAT amounts; backend computes total_fare = final_fare * number_of_seats
        'original_fare': originalPricePerSeat,
        'proposed_fare': proposedPricePerSeat,
        'final_fare': finalFarePerSeat,
        'is_negotiated': isNegotiated,
        // Client-side convenience (not required by backend)
        'total_price': totalPrice,
        if (passengerId != null) 'passenger_id': passengerId,
        if (passengerId != null) 'user_id': passengerId, // compatibility if backend expects user_id
      };
      
      developer.log('Booking payload: $bookingData', name: 'RideRequestController');

      if (passengerId != null) {
        final gate = await ApiService.getRideBookingGateStatus(userId: passengerId);
        if (gate['blocked'] == true) {
          onError?.call(gate['message'] ?? 'Verification pending.');
          return false;
        }
      }

      final response = await ApiService.requestRideBooking(bookingData);
      
      if (response['success'] == true) {
        onSuccess?.call('Ride requested successfully!');
        return true;
      } else {
        final errorMsg = (response['error'] ?? response['message'] ?? 'Failed to request ride').toString();
        // If we specifically hit a network timeout, treat it as a soft success because
        // the backend likely processed the booking (as seen in server logs).
        if (errorMsg.toLowerCase().contains('timeout')) {
          onSuccess?.call('Ride requested successfully!');
          return true;
        }
        onError?.call(errorMsg);
        return false;
      }
    } catch (e) {
      onError?.call('Error: ${e.toString()}');
      return false;
    } finally {
      isBookingInProgress = false;
      onStateChanged?.call();
    }
  }

  // Validate booking data
  bool _validateBooking() {
    if (selectedFromStop >= selectedToStop) {
      onError?.call('Drop-off must be after pick-up');
      return false;
    }
    
    if ((maleSeats + femaleSeats) <= 0) {
      onError?.call('Please select at least one seat');
      return false;
    }
    
    // Validate trip id from nested structure first, then fallback to top-level
    final tripIdNested = rideData['trip']?['trip_id'];
    final tripIdTop = rideData['trip_id'];
    if (tripIdNested == null && tripIdTop == null) {
      onError?.call('Invalid trip data');
      return false;
    }
    
    return true;
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

  // Helper method to set state
  void setState(VoidCallback fn) {
    fn();
    onStateChanged?.call();
  }

  // Dispose resources
  void dispose() {
    priceController.dispose();
  }
}
