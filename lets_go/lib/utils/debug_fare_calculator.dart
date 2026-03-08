import 'dart:math';
import 'package:flutter/foundation.dart';
import 'fare_calculator.dart';

class DebugFareCalculator {
  /// Test the frontend fare calculator with sample data
  static void testFrontendCalculator() {
    debugPrint('🔍 Testing Frontend Fare Calculator...');
    
    // Sample route stops (Lahore to Islamabad)
    List<Map<String, dynamic>> routeStops = [
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
    List<Map<String, dynamic>> testScenarios = [
      {
        'name': 'Petrol Car - Peak Hour',
        'fuelType': 'Petrol',
        'vehicleType': 'FW',
        'departureTime': DateTime(2025, 1, 15, 8, 0), // 8:00 AM
        'totalSeats': 1,
      },
      {
        'name': 'Diesel Car - Off Peak',
        'fuelType': 'Diesel',
        'vehicleType': 'FW',
        'departureTime': DateTime(2025, 1, 15, 14, 0), // 2:00 PM
        'totalSeats': 1,
      },
      {
        'name': 'CNG Car - Peak Hour - 4 Seats',
        'fuelType': 'CNG',
        'vehicleType': 'FW',
        'departureTime': DateTime(2025, 1, 15, 18, 0), // 6:00 PM
        'totalSeats': 4,
      },
      {
        'name': 'Motorcycle - Off Peak',
        'fuelType': 'Petrol',
        'vehicleType': 'TW',
        'departureTime': DateTime(2025, 1, 15, 12, 0), // 12:00 PM
        'totalSeats': 1,
      },
    ];
    
    for (final scenario in testScenarios) {
      debugPrint('\n📊 ${scenario['name']}');
      debugPrint('   Fuel: ${scenario['fuelType']}');
      debugPrint('   Vehicle: ${scenario['vehicleType']}');
      debugPrint('   Time: ${scenario['departureTime'].hour}:${scenario['departureTime'].minute.toString().padLeft(2, '0')}');
      debugPrint('   Seats: ${scenario['totalSeats']}');
      
      try {
        final result = FareCalculator.calculateFare(
          routeStops: routeStops,
          fuelType: scenario['fuelType'],
          vehicleType: scenario['vehicleType'],
          departureTime: scenario['departureTime'],
          totalSeats: scenario['totalSeats'],
        );
        
        debugPrint('   ✅ Success!');
        debugPrint('   💰 Total Fare: PKR ${result['base_fare']?.toStringAsFixed(2) ?? 'N/A'}');
        debugPrint('   📏 Distance: ${result['total_distance_km']?.toStringAsFixed(1) ?? 'N/A'} km');
        
        final breakdown = result['calculation_breakdown'];
        if (breakdown != null) {
          debugPrint('   ⛽ Fuel Type: ${breakdown['fuel_type'] ?? 'N/A'}');
          debugPrint('   🚗 Vehicle Multiplier: ${breakdown['vehicle_multiplier']?.toStringAsFixed(2) ?? 'N/A'}x');
          debugPrint('   ⏰ Time Multiplier: ${breakdown['time_multiplier']?.toStringAsFixed(2) ?? 'N/A'}x');
          debugPrint('   🪑 Seat Factor: ${breakdown['seat_factor']?.toStringAsFixed(2) ?? 'N/A'}x');
          debugPrint('   📍 Distance Factor: ${breakdown['distance_factor']?.toStringAsFixed(2) ?? 'N/A'}x');
          
          if (breakdown['is_peak_hour'] == true) {
            debugPrint('   🚦 Peak Hour: YES (+30%)');
          }
          
          if (breakdown['bulk_discount_percentage'] != null && breakdown['bulk_discount_percentage'] > 0) {
            debugPrint('   🎁 Bulk Discount: -${breakdown['bulk_discount_percentage']?.toStringAsFixed(1) ?? 'N/A'}%');
          }
        }
        
        // Check stop breakdown
        final stopBreakdown = result['stop_breakdown'];
        if (stopBreakdown != null && stopBreakdown.isNotEmpty) {
          debugPrint('   🛣️  Stop Breakdown:');
          for (final stop in stopBreakdown) {
            debugPrint('      ${stop['from_stop_name']} → ${stop['to_stop_name']}: ${stop['distance']?.toStringAsFixed(1) ?? 'N/A'} km, PKR ${stop['price']?.toStringAsFixed(2) ?? 'N/A'}');
          }
        }
        
      } catch (e) {
        debugPrint('   ❌ Error: $e');
      }
      
      debugPrint('   ${'-' * 40}');
    }
    
    debugPrint('\n✅ Frontend calculator test completed!');
  }
  
  /// Test specific calculation components
  static void testCalculationComponents() {
    debugPrint('\n🔧 Testing Calculation Components...');
    
    // Test distance calculation manually (since methods are private)
    double lat1 = 31.5204, lon1 = 74.3587;
    double lat2 = 33.6844, lon2 = 73.0479;
    
    const double earthRadius = 6371; // Earth's radius in kilometers
    double dLat = (lat2 - lat1) * (pi / 180);
    double dLon = (lon2 - lon1) * (pi / 180);
    double a = sin(dLat / 2) * sin(dLat / 2) +
               cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
               sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;
    
    debugPrint('   📏 Distance (Lahore to Islamabad): ${distance.toStringAsFixed(1)} km');
    
    // Test peak hour detection manually
    DateTime peakTime = DateTime(2025, 1, 15, 8, 0); // 8:00 AM
    DateTime offPeakTime = DateTime(2025, 1, 15, 14, 0); // 2:00 PM
    
    bool isPeak1 = (peakTime.hour >= 7 && peakTime.hour <= 9) || (peakTime.hour >= 17 && peakTime.hour <= 19);
    bool isPeak2 = (offPeakTime.hour >= 7 && offPeakTime.hour <= 9) || (offPeakTime.hour >= 17 && offPeakTime.hour <= 19);
    
    debugPrint('   ⏰ Peak Hour (8:00 AM): $isPeak1');
    debugPrint('   ⏰ Peak Hour (2:00 PM): $isPeak2');
    
    // Test distance categories manually
    List<double> testDistances = [3.0, 12.0, 25.0, 50.0, 120.0];
    for (final dist in testDistances) {
      String category;
      if (dist <= 10) {
        category = '0-10';
      } else if (dist <= 25) {
        category = '10-25';
      } else if (dist <= 50) {
        category = '25-50';
      } else if (dist <= 100) {
        category = '50-100';
      } else {
        category = '100+';
      }
      
      debugPrint('   📍 Distance ${dist.toStringAsFixed(1)} km → Category: $category');
    }
  }
  
  /// Compare frontend vs expected backend results
  static void compareWithBackend() {
    debugPrint('\n🔄 Comparing Frontend vs Expected Backend Results...');
    
    // Sample calculation that should match backend
    List<Map<String, dynamic>> routeStops = [
      {'latitude': 31.5204, 'longitude': 74.3587, 'stop_name': 'Lahore'},
      {'latitude': 33.6844, 'longitude': 73.0479, 'stop_name': 'Islamabad'},
    ];
    
    final result = FareCalculator.calculateFare(
      routeStops: routeStops,
      fuelType: 'Petrol',
      vehicleType: 'FW',
      departureTime: DateTime(2025, 1, 15, 8, 0), // Peak hour
      totalSeats: 1,
    );
    
    debugPrint('   📊 Frontend Result:');
    debugPrint('      Total Fare: PKR ${result['base_fare']?.toStringAsFixed(2) ?? 'N/A'}');
    debugPrint('      Distance: ${result['total_distance_km']?.toStringAsFixed(1) ?? 'N/A'} km');
    
    // Expected backend calculation (manual)
    double expectedDistance = 240.0; // Approximate Lahore to Islamabad
    double baseRate = 22.0; // Petrol
    double vehicleMultiplier = 1.0; // FW
    double timeMultiplier = 1.3; // Peak hour
    double seatFactor = 1.0; // Standard
    double distanceFactor = 0.85; // Long trip discount
    double bulkDiscount = 0.0; // Single seat
    
    double expectedFare = baseRate * expectedDistance * vehicleMultiplier * 
                         timeMultiplier * seatFactor * distanceFactor * (1 - bulkDiscount);
    
    debugPrint('   📊 Expected Backend Result:');
    debugPrint('      Total Fare: PKR ${expectedFare.toStringAsFixed(2)}');
    debugPrint('      Distance: ${expectedDistance.toStringAsFixed(1)} km');
    
    // Compare
    double frontendFare = result['base_fare'] ?? 0.0;
    double difference = (frontendFare - expectedFare).abs();
    double percentageDiff = (difference / expectedFare) * 100;
    
    debugPrint('   📊 Comparison:');
    debugPrint('      Difference: PKR ${difference.toStringAsFixed(2)}');
    debugPrint('      Percentage: ${percentageDiff.toStringAsFixed(1)}%');
    
    if (percentageDiff < 5.0) {
      debugPrint('   ✅ Results are within acceptable range (< 5%)');
    } else {
      debugPrint('   ⚠️  Results differ significantly (> 5%)');
    }
  }

  /// Test the hybrid fare calculation system
  static void testHybridFareCalculation() {
    debugPrint('=== HYBRID FARE CALCULATION TEST ===');
    
    // Sample route stops
    List<Map<String, dynamic>> routeStops = [
      {'latitude': 30.3753, 'longitude': 69.3451, 'stop_name': 'Start Point'},
      {'latitude': 30.3853, 'longitude': 69.3551, 'stop_name': 'Stop 1'},
      {'latitude': 30.3953, 'longitude': 69.3651, 'stop_name': 'Stop 2'},
    ];
    
    // Test 1: Initial calculation
    debugPrint('\n1. Initial Fare Calculation:');
    Map<String, dynamic> initialFare = FareCalculator.calculateHybridFare(
      routeStops: routeStops,
      fuelType: 'Petrol',
      vehicleType: 'Sedan',
      departureTime: DateTime.now(),
      totalSeats: 1,
    );
    
    debugPrint('Total Fare: ${initialFare['total_price']} PKR');
    debugPrint('Individual Stops:');
    List<Map<String, dynamic>> stops = List<Map<String, dynamic>>.from(initialFare['stop_breakdown']);
    for (int i = 0; i < stops.length; i++) {
      debugPrint('  Stop ${i + 1}: ${stops[i]['price']} PKR');
    }
    
    // Test 2: Update total fare
    debugPrint('\n2. Update Total Fare to 150 PKR:');
    Map<String, dynamic> updatedTotalFare = FareCalculator.updateTotalFare(
      currentFareData: initialFare,
      newTotalFare: 150.0,
    );
    
    debugPrint('New Total Fare: ${updatedTotalFare['total_price']} PKR');
    debugPrint('Redistributed Individual Stops:');
    List<Map<String, dynamic>> updatedStops = List<Map<String, dynamic>>.from(updatedTotalFare['stop_breakdown']);
    for (int i = 0; i < updatedStops.length; i++) {
      debugPrint('  Stop ${i + 1}: ${updatedStops[i]['price']} PKR');
    }
    
    // Test 3: Update individual stop fare
    debugPrint('\n3. Update Individual Stop Fare (Stop 1 to 60 PKR):');
    Map<String, dynamic> updatedIndividualFare = FareCalculator.updateIndividualStopFare(
      currentFareData: initialFare,
      stopIndex: 0,
      newStopFare: 60.0,
    );
    
    debugPrint('Recalculated Total Fare: ${updatedIndividualFare['total_price']} PKR');
    debugPrint('Updated Individual Stops:');
    List<Map<String, dynamic>> individualUpdatedStops = List<Map<String, dynamic>>.from(updatedIndividualFare['stop_breakdown']);
    for (int i = 0; i < individualUpdatedStops.length; i++) {
      debugPrint('  Stop ${i + 1}: ${individualUpdatedStops[i]['price']} PKR');
    }
    
    // Test 4: Fare summary
    debugPrint('\n4. Fare Summary:');
    Map<String, dynamic> summary = FareCalculator.getFareSummary(initialFare);
    debugPrint('Total Fare: ${summary['total_fare']} PKR');
    debugPrint('Total Distance: ${summary['total_distance_km']} km');
    debugPrint('Total Duration: ${summary['total_duration_minutes']} minutes');
    debugPrint('Number of Stops: ${summary['number_of_stops']}');
    debugPrint('Average Fare per Stop: ${summary['average_fare_per_stop']} PKR');
    debugPrint('Fare per km: ${summary['fare_per_km']} PKR/km');
    debugPrint('Custom Fare Applied: ${summary['custom_fare_applied']}');
  }

  /// Test fare consistency
  static void testFareConsistency() {
    debugPrint('\n=== FARE CONSISTENCY TEST ===');
    
    List<Map<String, dynamic>> routeStops = [
      {'latitude': 30.3753, 'longitude': 69.3451, 'stop_name': 'Start'},
      {'latitude': 30.3853, 'longitude': 69.3551, 'stop_name': 'Stop 1'},
      {'latitude': 30.3953, 'longitude': 69.3651, 'stop_name': 'Stop 2'},
    ];
    
    Map<String, dynamic> fare = FareCalculator.calculateHybridFare(
      routeStops: routeStops,
      fuelType: 'Petrol',
      vehicleType: 'Sedan',
      departureTime: DateTime.now(),
      totalSeats: 1,
    );
    
    List<Map<String, dynamic>> stops = List<Map<String, dynamic>>.from(fare['stop_breakdown']);
    double totalFromStops = stops.fold(0.0, (sum, stop) => sum + (stop['price'] ?? 0.0));
    double totalFare = fare['total_price'] ?? 0.0;
    
    debugPrint('Total Fare: $totalFare PKR');
    debugPrint('Sum of Individual Stops: $totalFromStops PKR');
    debugPrint('Consistent: ${(totalFare - totalFromStops).abs() < 0.01}');
    
    if ((totalFare - totalFromStops).abs() < 0.01) {
      debugPrint('✅ Fare calculation is consistent!');
    } else {
      debugPrint('❌ Fare calculation is inconsistent!');
    }
  }

  /// Test the specific issue reported by user (individual fare > total fare)
  static void testUserReportedIssue() {
    debugPrint('\n=== TESTING USER REPORTED ISSUE ===');
    
    // Simulate the user's scenario: 2 stops, individual fare > total fare
    List<Map<String, dynamic>> routeStops = [
      {'latitude': 30.3753, 'longitude': 69.3451, 'stop_name': 'BABA PIZZA, restaurant, Karachi'},
      {'latitude': 36.23681, 'longitude': 137.972471, 'stop_name': 'تحصیل پشاور شہر'},
    ];
    
    debugPrint('Route: ${routeStops[0]['stop_name']} → ${routeStops[1]['stop_name']}');
    
    // Test with hybrid calculation (should fix the issue)
    debugPrint('\n1. Testing Hybrid Calculation (FIXED):');
    Map<String, dynamic> hybridResult = FareCalculator.calculateHybridFare(
      routeStops: routeStops,
      fuelType: 'Petrol',
      vehicleType: 'Sedan',
      departureTime: DateTime.now(),
      totalSeats: 1,
    );
    
    double hybridTotal = hybridResult['total_price'] ?? 0.0;
    List<Map<String, dynamic>> hybridStops = List<Map<String, dynamic>>.from(hybridResult['stop_breakdown'] ?? []);
    double hybridIndividualSum = hybridStops.fold(0.0, (sum, stop) => sum + (stop['price'] ?? 0.0));
    
    debugPrint('   Total Fare: ${hybridTotal.toStringAsFixed(2)} PKR');
    debugPrint('   Individual Stops Sum: ${hybridIndividualSum.toStringAsFixed(2)} PKR');
    debugPrint('   Consistent: ${(hybridTotal - hybridIndividualSum).abs() < 0.01}');
    
    if ((hybridTotal - hybridIndividualSum).abs() < 0.01) {
      debugPrint('   ✅ Hybrid calculation is consistent!');
    } else {
      debugPrint('   ❌ Hybrid calculation is still inconsistent!');
    }
    
    // Test with old calculation (should show the issue)
    debugPrint('\n2. Testing Old Calculation (SHOULD SHOW ISSUE):');
    Map<String, dynamic> oldResult = FareCalculator.calculateFare(
      routeStops: routeStops,
      fuelType: 'Petrol',
      vehicleType: 'Sedan',
      departureTime: DateTime.now(),
      totalSeats: 1,
    );
    
    double oldTotal = oldResult['total_price'] ?? 0.0;
    List<Map<String, dynamic>> oldStops = List<Map<String, dynamic>>.from(oldResult['stop_breakdown'] ?? []);
    double oldIndividualSum = oldStops.fold(0.0, (sum, stop) => sum + (stop['price'] ?? 0.0));
    
    debugPrint('   Total Fare: ${oldTotal.toStringAsFixed(2)} PKR');
    debugPrint('   Individual Stops Sum: ${oldIndividualSum.toStringAsFixed(2)} PKR');
    debugPrint('   Consistent: ${(oldTotal - oldIndividualSum).abs() < 0.01}');
    
    if ((oldTotal - oldIndividualSum).abs() < 0.01) {
      debugPrint('   ✅ Old calculation is consistent!');
    } else {
      debugPrint('   ❌ Old calculation shows the reported issue!');
    }
    
    // Show the difference
    debugPrint('\n3. Comparison:');
    debugPrint('   Hybrid Total: ${hybridTotal.toStringAsFixed(2)} PKR');
    debugPrint('   Old Total: ${oldTotal.toStringAsFixed(2)} PKR');
    debugPrint('   Difference: ${(hybridTotal - oldTotal).abs().toStringAsFixed(2)} PKR');
    
    if (hybridIndividualSum == hybridTotal) {
      debugPrint('   ✅ Hybrid calculation fixes the issue!');
    } else {
      debugPrint('   ❌ Hybrid calculation still has issues!');
    }
  }
} 