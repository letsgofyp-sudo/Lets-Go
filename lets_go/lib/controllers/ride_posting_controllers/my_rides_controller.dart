import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class MyRidesController {
  // User rides data
  List<Map<String, dynamic>> userRides = [];
  List<Map<String, dynamic>> userBookings = [];
  bool isLoading = false;
  
  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  Function(String)? onInfo;
  
  MyRidesController({
    this.onStateChanged,
    this.onError,
    this.onSuccess,
    this.onInfo,
  });

  Future<void> loadCreatedRides(int userId) async {
    debugPrint('DEBUG: loadCreatedRides called for userId: $userId');
    isLoading = true;
    onStateChanged?.call();

    try {
      final rides = await ApiService.getUserRides(userId.toString());
      userRides = rides;
      onStateChanged?.call();
      if (userRides.isEmpty) {
        onInfo?.call('No created rides found');
      } else {
        onSuccess?.call('Loaded ${userRides.length} rides');
      }
    } catch (e) {
      debugPrint('DEBUG: Exception in loadCreatedRides: $e');
      onError?.call('Failed to load rides: $e');
      debugPrint('DEBUG: Falling back to mock rides');
      userRides = _createMockRides();
      onStateChanged?.call();
    } finally {
      isLoading = false;
      onStateChanged?.call();
    }
  }

  Future<void> loadBookedRides(int userId) async {
    debugPrint('DEBUG: loadBookedRides called for userId: $userId');
    isLoading = true;
    onStateChanged?.call();

    try {
      final bookings = await ApiService.getUserBookings(userId);
      userBookings = bookings;
      onStateChanged?.call();
      if (userBookings.isEmpty) {
        onInfo?.call('No bookings found');
      } else {
        onSuccess?.call('Loaded ${userBookings.length} bookings');
      }
    } catch (e) {
      debugPrint('DEBUG: Exception in loadBookedRides: $e');
      onError?.call('Failed to load bookings: $e');
      debugPrint('DEBUG: Falling back to mock bookings');
      userBookings = _createMockBookings();
      onStateChanged?.call();
    } finally {
      isLoading = false;
      onStateChanged?.call();
    }
  }

  // Backwards compatible method (loads BOTH). Prefer per-tab methods.
  Future<void> loadUserRides(int userId) async {
    debugPrint('DEBUG: loadUserRides called for userId: $userId');
    await Future.wait([
      loadCreatedRides(userId),
      loadBookedRides(userId),
    ]);
  }

  // Delete a ride
  Future<void> deleteRide(String tripId) async {
    try {
      final response = await ApiService.deleteTrip(tripId);
      
      if (response['success']) {
        // Remove from local list
        userRides.removeWhere((ride) => ride['trip_id'] == tripId);
        onStateChanged?.call();
        onSuccess?.call('Ride deleted successfully');
      } else {
        onError?.call('Failed to delete ride: ${response['error']}');
      }
    } catch (e) {
      onError?.call('Error deleting ride: $e');
      // For local testing, remove from mock data
      userRides.removeWhere((ride) => ride['trip_id'] == tripId);
      onStateChanged?.call();
      onSuccess?.call('Ride deleted successfully (Local Mode)');
    }
  }

  // Cancel a ride
  Future<void> cancelRide(String tripId) async {
    try {
      final response = await ApiService.cancelTrip(tripId, reason: 'Cancelled by driver');
      
      if (response['success']) {
        // Update ride status in local list
        final rideIndex = userRides.indexWhere((ride) => ride['trip_id'] == tripId);
        if (rideIndex != -1) {
          userRides[rideIndex]['status'] = 'cancelled';
          userRides[rideIndex]['can_edit'] = false;
          userRides[rideIndex]['can_delete'] = false;
          userRides[rideIndex]['can_cancel'] = false;
        }
        onStateChanged?.call();
        onSuccess?.call('Ride cancelled successfully');
      } else {
        onError?.call('Failed to cancel ride: ${response['error']}');
      }
    } catch (e) {
      onError?.call('Error cancelling ride: $e');
      // For local testing, update mock data
      final rideIndex = userRides.indexWhere((ride) => ride['trip_id'] == tripId);
      if (rideIndex != -1) {
        userRides[rideIndex]['status'] = 'cancelled';
        userRides[rideIndex]['can_edit'] = false;
        userRides[rideIndex]['can_delete'] = false;
        userRides[rideIndex]['can_cancel'] = false;
      }
      onStateChanged?.call();
      onSuccess?.call('Ride cancelled successfully (Local Mode)');
    }
  }

  // Cancel a booking request
  Future<void> cancelBooking(int bookingId, String reason) async {
    try {
      final response = await ApiService.cancelBooking(bookingId, reason);
      
      if (response['success']) {
        // Update booking status in local list
        final bookingIndex = userBookings.indexWhere((booking) => booking['booking_id'] == bookingId);
        if (bookingIndex != -1) {
          userBookings[bookingIndex]['status'] = 'cancelled';
        }
        onStateChanged?.call();
        onSuccess?.call('Booking cancelled successfully');
      } else {
        onError?.call('Failed to cancel booking: ${response['error']}');
      }
    } catch (e) {
      onError?.call('Error cancelling booking: $e');
      // For local testing, update mock data
      final bookingIndex = userBookings.indexWhere((booking) => booking['booking_id'] == bookingId);
      if (bookingIndex != -1) {
        userBookings[bookingIndex]['status'] = 'cancelled';
      }
      onStateChanged?.call();
      onSuccess?.call('Booking cancelled successfully (Local Mode)');
    }
  }

  // Create mock rides for local testing
  List<Map<String, dynamic>> _createMockRides() {
    return [
      {
        'trip_id': 'T001-2024-01-15-0830',
        'trip_date': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'departure_time': '08:30',
        'route_names': ['Lahore', 'Islamabad'],
        'route_coordinates': [
          {'lat': 31.5204, 'lng': 74.3587, 'name': 'Lahore', 'order': 1},
          {'lat': 33.6844, 'lng': 73.0479, 'name': 'Islamabad', 'order': 2},
        ],
        'distance': 350.5,
        'duration': 240,
        'custom_price': 1200.0,
        'total_seats': 3,
        'available_seats': 2,
        'booking_count': 1,
        'gender_preference': 'Any',
        'description': 'Comfortable ride with AC',
        'status': 'pending',
        'created_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'updated_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'vehicle': {
          'id': 1,
          'model_number': 'Civic',
          'company_name': 'Honda',
          'plate_number': 'ABC-123',
          'vehicle_type': 'FW',
          'color': 'White',
          'seats': 4,
          'fuel_type': 'Petrol',
        },
        'route': {
          'id': 'R001',
          'name': 'Lahore to Islamabad',
          'description': 'Route from Lahore to Islamabad',
          'total_distance_km': 350.5,
          'estimated_duration_minutes': 240,
          'stops': [
            {
              'name': 'Lahore',
              'order': 1,
              'latitude': 31.5204,
              'longitude': 74.3587,
              'address': 'Lahore, Pakistan',
              'estimated_time_from_start': 0,
            },
            {
              'name': 'Islamabad',
              'order': 2,
              'latitude': 33.6844,
              'longitude': 73.0479,
              'address': 'Islamabad, Pakistan',
              'estimated_time_from_start': 240,
            },
          ],
        },
        'fare_calculation': {
          'total_distance_km': 350.5,
          'base_rate_per_km': 22.0,
          'total_fare': 1200.0,
        },
        'stop_breakdown': [
          {
            'from_stop_name': 'Lahore',
            'to_stop_name': 'Islamabad',
            'distance': 350.5,
            'duration': 240,
            'price': 1200.0,
            'from_coordinates': {'lat': 31.5204, 'lng': 74.3587},
            'to_coordinates': {'lat': 33.6844, 'lng': 73.0479},
          },
        ],
        'can_edit': true,
        'can_delete': true,
        'can_cancel': true,
      },
      {
        'trip_id': 'T002-2024-01-16-1400',
        'trip_date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        'departure_time': '14:00',
        'route_names': ['Karachi', 'Lahore'],
        'route_coordinates': [
          {'lat': 24.8607, 'lng': 67.0011, 'name': 'Karachi', 'order': 1},
          {'lat': 31.5204, 'lng': 74.3587, 'name': 'Lahore', 'order': 2},
        ],
        'distance': 1200.0,
        'duration': 720,
        'custom_price': 2500.0,
        'total_seats': 2,
        'available_seats': 1,
        'booking_count': 1,
        'gender_preference': 'Male',
        'description': 'Long journey with breaks',
        'status': 'pending',
        'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'updated_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'vehicle': {
          'id': 2,
          'model_number': 'Corolla',
          'company_name': 'Toyota',
          'plate_number': 'XYZ-789',
          'vehicle_type': 'FW',
          'color': 'Black',
          'seats': 5,
          'fuel_type': 'Petrol',
        },
        'route': {
          'id': 'R002',
          'name': 'Karachi to Lahore',
          'description': 'Route from Karachi to Lahore',
          'total_distance_km': 1200.0,
          'estimated_duration_minutes': 720,
          'stops': [
            {
              'name': 'Karachi',
              'order': 1,
              'latitude': 24.8607,
              'longitude': 67.0011,
              'address': 'Karachi, Pakistan',
              'estimated_time_from_start': 0,
            },
            {
              'name': 'Lahore',
              'order': 2,
              'latitude': 31.5204,
              'longitude': 74.3587,
              'address': 'Lahore, Pakistan',
              'estimated_time_from_start': 720,
            },
          ],
        },
        'fare_calculation': {
          'total_distance_km': 1200.0,
          'base_rate_per_km': 22.0,
          'total_fare': 2500.0,
        },
        'stop_breakdown': [
          {
            'from_stop_name': 'Karachi',
            'to_stop_name': 'Lahore',
            'distance': 1200.0,
            'duration': 720,
            'price': 2500.0,
            'from_coordinates': {'lat': 24.8607, 'lng': 67.0011},
            'to_coordinates': {'lat': 31.5204, 'lng': 74.3587},
          },
        ],
        'can_edit': true,
        'can_delete': true,
        'can_cancel': true,
      },
      {
        'trip_id': 'T003-2024-01-14-1000',
        'trip_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'departure_time': '10:00',
        'route_names': ['Islamabad', 'Peshawar'],
        'route_coordinates': [
          {'lat': 33.6844, 'lng': 73.0479, 'name': 'Islamabad', 'order': 1},
          {'lat': 34.0153, 'lng': 71.5249, 'name': 'Peshawar', 'order': 2},
        ],
        'distance': 180.0,
        'duration': 120,
        'custom_price': 800.0,
        'total_seats': 4,
        'available_seats': 0,
        'booking_count': 4,
        'gender_preference': 'Any',
        'description': 'Quick trip',
        'status': 'completed',
        'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'updated_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'vehicle': {
          'id': 3,
          'model_number': 'Swift',
          'company_name': 'Suzuki',
          'plate_number': 'DEF-456',
          'vehicle_type': 'FW',
          'color': 'Red',
          'seats': 4,
          'fuel_type': 'Petrol',
        },
        'route': {
          'id': 'R003',
          'name': 'Islamabad to Peshawar',
          'description': 'Route from Islamabad to Peshawar',
          'total_distance_km': 180.0,
          'estimated_duration_minutes': 120,
          'stops': [
            {
              'name': 'Islamabad',
              'order': 1,
              'latitude': 33.6844,
              'longitude': 73.0479,
              'address': 'Islamabad, Pakistan',
              'estimated_time_from_start': 0,
            },
            {
              'name': 'Peshawar',
              'order': 2,
              'latitude': 34.0153,
              'longitude': 71.5249,
              'address': 'Peshawar, Pakistan',
              'estimated_time_from_start': 120,
            },
          ],
        },
        'fare_calculation': {
          'total_distance_km': 180.0,
          'base_rate_per_km': 22.0,
          'total_fare': 800.0,
        },
        'stop_breakdown': [
          {
            'from_stop_name': 'Islamabad',
            'to_stop_name': 'Peshawar',
            'distance': 180.0,
            'duration': 120,
            'price': 800.0,
            'from_coordinates': {'lat': 33.6844, 'lng': 73.0479},
            'to_coordinates': {'lat': 34.0153, 'lng': 71.5249},
          },
        ],
        'can_edit': false,
        'can_delete': false,
        'can_cancel': false,
      },
    ];
  }

  // Create mock bookings for local testing
  List<Map<String, dynamic>> _createMockBookings() {
    return [
      {
        'booking_id': 1,
        'trip_id': 'T004-2024-01-16-1200',
        'trip_date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        'departure_time': '12:00',
        'route_names': ['Karachi', 'Hyderabad'],
        'route_coordinates': [
          {'lat': 24.8607, 'lng': 67.0011, 'name': 'Karachi', 'order': 1},
          {'lat': 25.3960, 'lng': 68.3578, 'name': 'Hyderabad', 'order': 2},
        ],
        'distance': 165.0,
        'duration': 120,
        'custom_price': 800.0,
        'total_seats': 4,
        'available_seats': 2,
        'booking_count': 2,
        'gender_preference': 'Any',
        'description': 'Comfortable journey',
        'status': 'pending',
        'seats_booked': 1,
        'total_amount': 800.0,
        'created_at': DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
        'updated_at': DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
        'pickup_stop': 'Karachi',
        'dropoff_stop': 'Hyderabad',
        'driver_name': 'Ahmed Ali',
        'driver_phone': '+92-300-1234567',
        'vehicle': {
          'model_number': 'Corolla',
          'company_name': 'Toyota',
          'plate_number': 'KHI-456',
          'color': 'White',
        },
      },
      {
        'booking_id': 2,
        'trip_id': 'T005-2024-01-17-0900',
        'trip_date': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'departure_time': '09:00',
        'route_names': ['Islamabad', 'Lahore'],
        'route_coordinates': [
          {'lat': 33.6844, 'lng': 73.0479, 'name': 'Islamabad', 'order': 1},
          {'lat': 31.5204, 'lng': 74.3587, 'name': 'Lahore', 'order': 2},
        ],
        'distance': 350.0,
        'duration': 240,
        'custom_price': 1500.0,
        'total_seats': 3,
        'available_seats': 1,
        'booking_count': 2,
        'gender_preference': 'Male',
        'description': 'Express ride',
        'status': 'booked',
        'seats_booked': 2,
        'total_amount': 3000.0,
        'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'updated_at': DateTime.now().subtract(const Duration(hours: 12)).toIso8601String(),
        'pickup_stop': 'Islamabad',
        'dropoff_stop': 'Lahore',
        'driver_name': 'Hassan Khan',
        'driver_phone': '+92-321-9876543',
        'vehicle': {
          'model_number': 'Civic',
          'company_name': 'Honda',
          'plate_number': 'ISB-789',
          'color': 'Black',
        },
      },
      {
        'booking_id': 3,
        'trip_id': 'T006-2024-01-14-1500',
        'trip_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'departure_time': '15:00',
        'route_names': ['Lahore', 'Faisalabad'],
        'route_coordinates': [
          {'lat': 31.5204, 'lng': 74.3587, 'name': 'Lahore', 'order': 1},
          {'lat': 31.4504, 'lng': 73.1350, 'name': 'Faisalabad', 'order': 2},
        ],
        'distance': 120.0,
        'duration': 90,
        'custom_price': 600.0,
        'total_seats': 4,
        'available_seats': 0,
        'booking_count': 4,
        'gender_preference': 'Any',
        'description': 'Quick trip',
        'status': 'completed',
        'seats_booked': 1,
        'total_amount': 600.0,
        'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'updated_at': DateTime.now().subtract(const Duration(hours: 8)).toIso8601String(),
        'pickup_stop': 'Lahore',
        'dropoff_stop': 'Faisalabad',
        'driver_name': 'Ali Raza',
        'driver_phone': '+92-333-4567890',
        'vehicle': {
          'model_number': 'City',
          'company_name': 'Honda',
          'plate_number': 'LHR-321',
          'color': 'Silver',
        },
      },
    ];
  }

  // Dispose method for cleanup
  void dispose() {
    // Clean up any resources if needed in the future
  }
} 