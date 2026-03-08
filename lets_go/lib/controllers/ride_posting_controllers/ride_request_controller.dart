import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
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
  double? routeDistance;
  int? routeDuration;
  
  // Price negotiation
  final TextEditingController priceController = TextEditingController();
  double? proposedPricePerSeat;
  double originalPricePerSeat = 0.0;
  bool isPriceNegotiable = false;
  
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

  // Initialize controller with ride data
  void initializeWithRideData(Map<String, dynamic> data) {
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
        
        for (final stop in stops) {
          locationNames.add(stop['name'] ?? 'Unknown Stop');
          if (stop['latitude'] != null && stop['longitude'] != null) {
            routePoints.add(LatLng(
              (stop['latitude'] as num).toDouble(),
              (stop['longitude'] as num).toDouble(),
            ));
          }
        }
        
        // Set default from/to stops
        if (locationNames.length >= 2) {
          selectedFromStop = 1;
          selectedToStop = locationNames.length;
        }
      }
    }
    
    // Extract pricing information
    if (data['trip'] != null) {
      final trip = data['trip'] as Map<String, dynamic>;
      // Don't set original price here, it will be calculated based on selected stops
      isPriceNegotiable = trip['is_negotiable'] ?? false;
      
      // Set initial proposed price to null, will be calculated when stops are set
      proposedPricePerSeat = null;
      priceController.text = '';
      
      // Set default seats based on trip gender preference
      final tripGenderPreference = trip['gender_preference'] ?? 'Any';
      if (tripGenderPreference.toString().toLowerCase() == 'female') {
        maleSeats = 0;
        femaleSeats = 1;
      } else if (tripGenderPreference.toString().toLowerCase() == 'male') {
        maleSeats = 1;
        femaleSeats = 0;
      }
      if (locationNames.length >= 2) {
        selectedFromStop = 1;
        selectedToStop = locationNames.length;
        // Calculate initial price based on default stops
        _updatePriceBasedOnStops();
      }
    }
    
    onStateChanged?.call();
  }

  // Update selected from stop
  void updateFromStop(int stopOrder) {
    selectedFromStop = stopOrder;
    _updatePriceBasedOnStops();
    onStateChanged?.call();
  }

  // Update selected to stop
  void updateToStop(int stopOrder) {
    selectedToStop = stopOrder;
    _updatePriceBasedOnStops();
    onStateChanged?.call();
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
    return MapUtil.generateInterpolatedRoute(stops);
  }
  
  // Calculate distance between two points using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    return MapUtil.calculateDistanceMeters(point1, point2);
  }

  // Get interpolated route points for display
  List<LatLng> getInterpolatedRoutePoints() {
    if (routePoints.length < 2) return routePoints;
    return _generateInterpolatedRoute(routePoints);
  }

  // Update special requests
  void updateSpecialRequests(String requests) {
    specialRequests = requests;
    onStateChanged?.call();
  }

  // Update proposed price
  void updateProposedPrice(String price) {
    final priceValue = double.tryParse(price) ?? 0.0;
    if (priceValue >= 0) {
      proposedPricePerSeat = priceValue;
      onStateChanged?.call();
    }
  }

  // Calculate price based on selected stops (no fare matrix, direct calculation)
  void _updatePriceBasedOnStops() {
    if (routePoints.length < 2) return;
    
    // Calculate distance between selected stops
    double totalDistance = 0.0;
    for (int i = selectedFromStop - 1; i < selectedToStop - 1; i++) {
      if (i < routePoints.length - 1) {
        totalDistance += _calculateDistance(routePoints[i], routePoints[i + 1]);
      }
    }
    
    // Convert to kilometers
    totalDistance = totalDistance / 1000.0;
    
    // Base rate per km (Pakistan market rate)
    const double baseRatePerKm = 22.0; // PKR per km
    
    // Calculate new price based on distance
    double newPrice = totalDistance * baseRatePerKm;
    
    // Update original price and proposed price
    originalPricePerSeat = newPrice;
    if (proposedPricePerSeat == null || proposedPricePerSeat! > newPrice) {
      proposedPricePerSeat = newPrice;
    }
    
    // Update price controller text
    priceController.text = proposedPricePerSeat!.toStringAsFixed(2);
  }

  // Get minimum price (0 for bargaining)
  double getMinPrice() {
    return 0.0;
  }

  // Get maximum price (original calculated price)
  double getMaxPrice() {
    return originalPricePerSeat;
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

  // Get base fare
  double getBaseFare() {
    return _calculatePriceForSelectedStops();
  }

  // Get original price per seat
  double getOriginalPricePerSeat() {
    return _calculatePriceForSelectedStops();
  }

  // Calculate price for currently selected stops
  double _calculatePriceForSelectedStops() {
    if (routePoints.length < 2) return originalPricePerSeat;
    
    // Calculate distance between selected stops
    double totalDistance = 0.0;
    for (int i = selectedFromStop - 1; i < selectedToStop - 1; i++) {
      if (i < routePoints.length - 1) {
        totalDistance += _calculateDistance(routePoints[i], routePoints[i + 1]);
      }
    }
    
    // Convert to kilometers
    totalDistance = totalDistance / 1000.0;
    
    // Base rate per km (Pakistan market rate)
    const double baseRatePerKm = 22.0; // PKR per km
    
    return totalDistance * baseRatePerKm;
  }

  // Get final price per seat (negotiated or original)
  double getFinalPricePerSeat() {
    return proposedPricePerSeat ?? originalPricePerSeat;
  }

  // Check if price is negotiable
  bool getIsPriceNegotiable() {
    return isPriceNegotiable;
  }

  // Get potential savings per seat
  double getSavings() {
    if (proposedPricePerSeat != null && proposedPricePerSeat! < originalPricePerSeat) {
      return originalPricePerSeat - proposedPricePerSeat!;
    }
    return 0.0;
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
  double calculateTotalFare() {
    return getFinalPricePerSeat() * getTotalSeats();
  }

  // Request ride booking
  Future<void> requestRideBooking(int userId) async {
    if (!_validateBooking()) {
      return;
    }

    try {
      setState(() {
        isBookingInProgress = true;
      });

      // Prepare booking data
      final bookingData = {
        'trip_id': rideData['trip']?['trip_id'],
        'passenger_id': userId,
        'from_stop_order': selectedFromStop,
        'to_stop_order': selectedToStop,
        'number_of_seats': getTotalSeats(),
        'male_seats': maleSeats,
        'female_seats': femaleSeats,
        'special_requests': specialRequests,
        'original_fare': originalPricePerSeat,
        'proposed_fare': proposedPricePerSeat,
        'final_fare': getFinalPricePerSeat(),
        'is_negotiated': proposedPricePerSeat != null && proposedPricePerSeat != originalPricePerSeat,
      };

      // Make API call to request booking
      final response = await ApiService.requestRideBooking(bookingData);
      
      if (response['success'] == true) {
        onSuccess?.call('Ride request submitted successfully! The driver will review your offer.');
      } else {
        onError?.call(response['error'] ?? 'Failed to submit ride request');
      }
    } catch (e) {
      onError?.call('Error submitting ride request: $e');
    } finally {
      setState(() {
        isBookingInProgress = false;
      });
    }
  }

  // Validate booking data
  bool _validateBooking() {
    if (selectedFromStop >= selectedToStop) {
      onError?.call('Pickup location must come before drop-off location');
      return false;
    }

    if (getTotalSeats() <= 0 || getTotalSeats() > getMaxSeats()) {
      onError?.call('Invalid number of seats selected');
      return false;
    }

    if (maleSeats < 0 || femaleSeats < 0) {
      onError?.call('Number of seats cannot be negative');
      return false;
    }

    if (getTotalSeats() == 0) {
      onError?.call('Please select at least one seat');
      return false;
    }

    if (proposedPricePerSeat != null && proposedPricePerSeat! <= 0) {
      onError?.call('Invalid price offered');
      return false;
    }

    return true;
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
