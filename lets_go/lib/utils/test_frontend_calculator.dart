import 'package:flutter/foundation.dart';
import 'fare_calculator.dart';

void main() {
  // Test the frontend fare calculator
  debugPrint('🧪 Testing Frontend Fare Calculator\n');
  
  // Sample route stops (Lahore to Islamabad)
  final routeStops = [
    {
      'latitude': 31.5204,
      'longitude': 74.3587,
      'stop_name': 'Lahore',
    },
    {
      'latitude': 33.6844,
      'longitude': 73.0479,
      'stop_name': 'Islamabad',
    },
  ];
  
  // Test different scenarios
  final testScenarios = [
    {
      'name': 'Petrol Car - Peak Hour',
      'fuelType': 'Petrol',
      'vehicleType': 'FW',
      'departureTime': DateTime(2025, 1, 15, 8, 30), // 8:30 AM (peak hour)
      'totalSeats': 1,
    },
    {
      'name': 'Diesel Car - Off Peak',
      'fuelType': 'Diesel',
      'vehicleType': 'FW',
      'departureTime': DateTime(2025, 1, 15, 14, 30), // 2:30 PM (off peak)
      'totalSeats': 2,
    },
    {
      'name': 'CNG Car - Peak Hour - Bulk Booking',
      'fuelType': 'CNG',
      'vehicleType': 'FW',
      'departureTime': DateTime(2025, 1, 15, 18, 30), // 6:30 PM (peak hour)
      'totalSeats': 4,
    },
    {
      'name': 'Two Wheeler - Short Distance',
      'fuelType': 'Petrol',
      'vehicleType': 'TW',
      'departureTime': DateTime(2025, 1, 15, 10, 0), // 10:00 AM (off peak)
      'totalSeats': 1,
    },
  ];
  
  for (final scenario in testScenarios) {
    debugPrint('📋 ${scenario['name']}');
    debugPrint('   Fuel: ${scenario['fuelType']}');
    debugPrint('   Vehicle: ${scenario['vehicleType']}');
    debugPrint('   Time: ${scenario['departureTime']}');
    debugPrint('   Seats: ${scenario['totalSeats']}');
    
    try {
      final result = FareCalculator.calculateFare(
        routeStops: routeStops,
        fuelType: scenario['fuelType'] as String,
        vehicleType: scenario['vehicleType'] as String,
        departureTime: scenario['departureTime'] as DateTime,
        totalSeats: scenario['totalSeats'] as int,
      );
      
      final fare = result['base_fare'] as double;
      final breakdown = result['calculation_breakdown'] as Map<String, dynamic>;
      
      debugPrint('   💰 Total Fare: Rs. ${fare.toStringAsFixed(2)}');
      debugPrint('   📏 Distance: ${breakdown['total_distance_km']?.toStringAsFixed(1)} km');
      debugPrint('   ⛽ Fuel Cost: Rs. ${breakdown['fuel_cost']?.toStringAsFixed(2)}');
      debugPrint('   💼 Profit: Rs. ${breakdown['profit_margin']?.toStringAsFixed(2)} (${breakdown['profit_percentage']?.toStringAsFixed(1)}%)');
      
      if (breakdown['is_peak_hour'] == true) {
        debugPrint('   ⏰ Peak Hour: Yes (+30%)');
      }
      
      if (breakdown['bulk_discount'] != null && breakdown['bulk_discount'] > 0) {
        debugPrint('   🎫 Bulk Discount: ${breakdown['bulk_discount']?.toStringAsFixed(1)}%');
      }
      
    } catch (e) {
      debugPrint('   ❌ Error: $e');
    }
    
    debugPrint('');
  }
  
  // Test fuel prices
  debugPrint('⛽ Current Fuel Prices:');
  final fuelPrices = FareCalculator.getFuelPrices();
  fuelPrices.forEach((fuel, price) {
    debugPrint('   $fuel: Rs. ${price.toStringAsFixed(2)}/unit');
  });
  
  debugPrint('\n✅ Frontend calculator test completed!');
} 