import 'dart:math';

class FareCalculator {
  // Pakistan-specific base rates (PKR per km) - Updated for 2025
  static const Map<String, double> _baseRates = {
    'Petrol': 22.00,
    'Diesel': 20.00,
    'CNG': 16.00,
    'Electric': 14.00,
    'Hybrid': 18.00,
  };

  // Vehicle type multipliers
  static const Map<String, double> _vehicleMultipliers = {
    'Sedan': 1.0,
    'SUV': 1.2,
    'Van': 1.3,
    'Bus': 1.5,
    'Motorcycle': 0.7,
    'Auto Rickshaw': 0.8,
  };

  // Seat factors for different vehicle types
  static const Map<String, double> _seatFactors = {
    'Sedan': 1.0,
    'SUV': 1.1,
    'Van': 1.2,
    'Bus': 1.3,
    'Motorcycle': 0.5,
    'Auto Rickshaw': 0.6,
  };

  // Distance factors (longer trips get better rates)
  static const Map<String, double> _distanceFactors = {
    '0-10': 1.0, // 0-10 km: standard rate
    '10-25': 0.95, // 10-25 km: 5% discount
    '25-50': 0.90, // 25-50 km: 10% discount
    '50-100': 0.85, // 50-100 km: 15% discount
    '100+': 0.80, // 100+ km: 20% discount
  };

  // Bulk booking discounts
  static const Map<int, double> _bulkDiscounts = {
    1: 0.0, // No discount for 1 seat
    2: 0.05, // 5% discount for 2 seats
    3: 0.08, // 8% discount for 3 seats
    4: 0.10, // 10% discount for 4 seats
    5: 0.12, // 12% discount for 5 seats
    6: 0.15, // 15% discount for 6+ seats
  };

  // Minimum fares for different vehicle types (PKR)
  static const Map<String, int> _minimumFares = {
    'Sedan': 100,
    'SUV': 120,
    'Van': 150,
    'Bus': 200,
    'Motorcycle': 50,
    'Auto Rickshaw': 60,
  };

  // Fuel efficiency (km per liter)
  static const Map<String, double> _fuelEfficiency = {
    'Petrol': 12.0,
    'Diesel': 15.0,
    'CNG': 18.0,
    'Electric': 8.0, // km per kWh
    'Hybrid': 14.0,
  };

  // Current fuel prices in Pakistan (PKR per unit)
  static final Map<String, double> _fuelPrices = {
    'Petrol': 275.0, // PKR per liter
    'Diesel': 285.0, // PKR per liter
    'CNG': 220.0, // PKR per kg
    'Electric': 25.0, // PKR per kWh
    'Hybrid': 275.0, // Uses petrol price
  };

  /// Calculate comprehensive fare with stop-to-stop pricing breakdown
  static Map<String, dynamic> calculateFare({
    required List<Map<String, dynamic>> routeStops,
    required String fuelType,
    required String vehicleType,
    required DateTime departureTime,
    required int totalSeats,
  }) {
    assert(_bulkDiscounts.isNotEmpty);
    // 1. Calculate stop-to-stop distances and durations with pricing
    List<Map<String, dynamic>> stopBreakdown =
        _calculateStopBreakdownWithPricing(
          routeStops,
          fuelType,
          vehicleType,
          departureTime,
          totalSeats,
        );

    // 2. Calculate totals from individual stops
    double totalDistance = stopBreakdown.fold(
      0.0,
      (sum, stop) => sum + (stop['distance'] ?? 0.0),
    );
    int totalDuration = stopBreakdown.fold(
      0,
      (sum, stop) => sum + (stop['duration'] as int? ?? 0),
    );
    double totalPrice = stopBreakdown.fold(
      0.0,
      (sum, stop) => sum + (stop['price'] ?? 0.0),
    );

    // Apply minimum fare at the TOTAL level (not per segment).
    // The minimum is treated as a minimum per segment, multiplied by number of segments.
    final int minPerSegment = _minimumFares[vehicleType] ?? _minimumFares['Sedan']!;
    final int minimumTotalFare = minPerSegment * stopBreakdown.length;
    int finalTotalPrice = totalPrice.round();
    if (stopBreakdown.isNotEmpty && totalPrice > 0 && finalTotalPrice < minimumTotalFare) {
      finalTotalPrice = minimumTotalFare;

      final int totalInt = totalPrice.round();
      int running = 0;
      for (int i = 0; i < stopBreakdown.length; i++) {
        final seg = Map<String, dynamic>.from(stopBreakdown[i]);
        final original = (seg['price'] as num?)?.toInt() ?? 0;
        int scaled;
        if (i == stopBreakdown.length - 1) {
          scaled = finalTotalPrice - running;
        } else {
          scaled = totalInt > 0 ? ((finalTotalPrice * original) / totalInt).round() : 0;
          running += scaled;
        }
        seg['price'] = scaled;
        stopBreakdown[i] = seg;
      }
    }

    // 3. Bulk booking discounts removed: total fare is pure sum of stop prices
    double bulkDiscount = 0.0;
    double discountAmount = 0.0;

    // 3. Get calculation parameters for breakdown
    double baseRatePerKm = _baseRates[fuelType] ?? _baseRates['Petrol']!;
    double vehicleMultiplier =
        _vehicleMultipliers[vehicleType] ?? _vehicleMultipliers['Sedan']!;

    // 4. Check peak hour multiplier
    bool isPeakHour = _isPeakHour(departureTime);
    // Align with backend multiplier (30% during peak hours)
    double timeMultiplier = isPeakHour ? 1.3 : 1.0;

    // 5. Get seat factor
    double seatFactor = _seatFactors[vehicleType] ?? _seatFactors['Sedan']!;

    // 6. Get distance factor
    String distanceCategory = _getDistanceCategory(totalDistance);
    double distanceFactor =
        _distanceFactors[distanceCategory] ?? _distanceFactors['0-10']!;

    // 7. Calculate fuel cost for transparency
    double fuelEfficiency =
        _fuelEfficiency[fuelType] ?? _fuelEfficiency['Petrol']!;
    double fuelPrice = _fuelPrices[fuelType] ?? _fuelPrices['Petrol']!;
    double fuelCost = (totalDistance / fuelEfficiency) * fuelPrice;

    return {
      'base_fare': finalTotalPrice, // Final total price without bulk discount
      'total_distance_km': totalDistance,
      'total_duration_minutes': totalDuration,
      'total_price': finalTotalPrice,
      'bulk_discount_amount': discountAmount,
      'bulk_discount_percentage': bulkDiscount * 100,
      'stop_breakdown': stopBreakdown,
      'calculation_breakdown': {
        'total_distance_km': totalDistance,
        'total_duration_minutes': totalDuration,
        'total_price': finalTotalPrice,
        'minimum_total_fare': minimumTotalFare,
        'base_rate_per_km': baseRatePerKm,
        'vehicle_multiplier': vehicleMultiplier,
        'time_multiplier': timeMultiplier,
        'is_peak_hour': isPeakHour,
        'seat_factor': seatFactor,
        'distance_factor': distanceFactor,
        'distance_category': distanceCategory,
        'fuel_cost': fuelCost,
        'fuel_efficiency_km_per_unit': fuelEfficiency,
        'fuel_price_per_unit': fuelPrice,
        'vehicle_type': vehicleType,
        'fuel_type': fuelType,
        'total_seats': totalSeats,
        // Bulk discount disabled; keep fields for compatibility but always zero
        'bulk_discount_percentage': 0.0,
        'bulk_discount_amount': 0.0,
        'stop_breakdown': stopBreakdown,
      },
    };
  }

  /// Update fuel prices (for real-time updates)
  static void updateFuelPrices(Map<String, double> newPrices) {
    _fuelPrices.addAll(newPrices);
  }

  /// Get current fuel prices
  static Map<String, double> getFuelPrices() {
    return Map.from(_fuelPrices);
  }

  /// Get fuel efficiency data
  static Map<String, double> getFuelEfficiency() {
    return Map.from(_fuelEfficiency);
  }

  /// Calculate stop-to-stop breakdown with distances, durations, and pricing
  static List<Map<String, dynamic>> _calculateStopBreakdownWithPricing(
    List<Map<String, dynamic>> routeStops,
    String fuelType,
    String vehicleType,
    DateTime departureTime,
    int totalSeats,
  ) {
    if (routeStops.length < 2) return [];

    List<Map<String, dynamic>> breakdown = [];

    // Get calculation parameters
    double baseRatePerKm = _baseRates[fuelType] ?? _baseRates['Petrol']!;
    double vehicleMultiplier =
        _vehicleMultipliers[vehicleType] ?? _vehicleMultipliers['Sedan']!;
    bool isPeakHour = _isPeakHour(departureTime);
    double timeMultiplier = isPeakHour ? 1.3 : 1.0;
    double seatFactor = _seatFactors[vehicleType] ?? _seatFactors['Sedan']!;

    for (int i = 0; i < routeStops.length - 1; i++) {
      double lat1 = routeStops[i]['latitude']?.toDouble() ?? 0.0;
      double lon1 = routeStops[i]['longitude']?.toDouble() ?? 0.0;
      double lat2 = routeStops[i + 1]['latitude']?.toDouble() ?? 0.0;
      double lon2 = routeStops[i + 1]['longitude']?.toDouble() ?? 0.0;

      double distance = _haversineDistance(lat1, lon1, lat2, lon2);
      int duration = _calculateDuration(distance); // minutes

      // Calculate individual stop price
      int stopPrice = _calculateStopPrice(
        distance,
        baseRatePerKm,
        vehicleMultiplier,
        timeMultiplier,
        seatFactor,
        totalSeats,
      );

      breakdown.add({
        'from_stop': i + 1,
        'to_stop': i + 2,
        'from_stop_name': routeStops[i]['stop_name'] ?? 'Stop ${i + 1}',
        'to_stop_name': routeStops[i + 1]['stop_name'] ?? 'Stop ${i + 2}',
        'distance': distance,
        'duration': duration,
        'price': stopPrice,
        'from_coordinates': {'lat': lat1, 'lng': lon1},
        'to_coordinates': {'lat': lat2, 'lng': lon2},
        'price_breakdown': {
          'base_rate_per_km': baseRatePerKm,
          'vehicle_multiplier': vehicleMultiplier,
          'time_multiplier': timeMultiplier,
          'is_peak_hour': isPeakHour,
          'seat_factor': seatFactor,
          'distance_km': distance,
          'duration_minutes': duration,
        },
      });
    }

    return breakdown;
  }

  /// Calculate individual stop price based on distance and factors
  static int _calculateStopPrice(
    double distance,
    double baseRatePerKm,
    double vehicleMultiplier,
    double timeMultiplier,
    double seatFactor,
    int totalSeats,
  ) {
    // Calculate base price for this specific stop segment
    double basePrice =
        baseRatePerKm *
        distance *
        vehicleMultiplier *
        timeMultiplier *
        seatFactor;

    // Get distance category for this specific stop
    String distanceCategory = _getDistanceCategory(distance);
    double distanceFactor =
        _distanceFactors[distanceCategory] ?? _distanceFactors['0-10']!;

    // Apply distance factor to this stop
    basePrice *= distanceFactor;

    final rounded = basePrice.round();
    if (rounded <= 0 && distance > 0) {
      return 1;
    }

    // Note: Bulk discount should be applied to total fare, not individual stops
    // Individual stops should reflect their actual distance-based pricing
    return rounded;
  }

  /// Calculate estimated duration based on distance
  static int _calculateDuration(double distanceKm) {
    // Assume average speed of 50 km/h in urban areas
    double averageSpeedKmh = 50.0;
    double durationHours = distanceKm / averageSpeedKmh;
    return (durationHours * 60).round(); // Convert to minutes
  }

  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  static bool _isPeakHour(DateTime time) {
    int hour = time.hour;
    // Peak hours: 7-9 AM and 5-7 PM
    return (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19);
  }

  static String _getDistanceCategory(double distance) {
    if (distance <= 10) return '0-10';
    if (distance <= 25) return '10-25';
    if (distance <= 50) return '25-50';
    if (distance <= 100) return '50-100';
    return '100+';
  }

  // ===== LEGACY METHODS FOR FARE MATRIX SYSTEM =====

  /// Convert Django fare matrix to Flutter format
  static List<Map<String, dynamic>> convertFareMatrix(
    List<dynamic> djangoFareMatrix,
  ) {
    return djangoFareMatrix.map((item) {
      if (item is Map<String, dynamic>) {
        return item;
      } else if (item is Map) {
        return Map<String, dynamic>.from(item);
      } else {
        return <String, dynamic>{};
      }
    }).toList();
  }

  /// Validate fare calculation parameters
  static List<String> validateFareCalculation({
    required int fromStopOrder,
    required int toStopOrder,
    required List<Map<String, dynamic>> fareMatrix,
  }) {
    List<String> errors = [];

    if (fromStopOrder >= toStopOrder) {
      errors.add('Pickup stop must be before drop-off stop');
    }

    if (fareMatrix.isEmpty) {
      errors.add('Fare matrix is empty');
    }

    // Check if stops exist in fare matrix
    bool fromStopExists = fareMatrix.any(
      (item) => item['from_stop'] == fromStopOrder,
    );
    bool toStopExists = fareMatrix.any(
      (item) => item['to_stop'] == toStopOrder,
    );

    if (!fromStopExists) {
      errors.add('Pickup stop not found in fare matrix');
    }

    if (!toStopExists) {
      errors.add('Drop-off stop not found in fare matrix');
    }

    return errors;
  }

  /// Calculate booking fare using fare matrix
  static Map<String, dynamic> calculateBookingFare({
    required int fromStopOrder,
    required int toStopOrder,
    required int numberOfSeats,
    required List<Map<String, dynamic>> fareMatrix,
    required DateTime bookingTime,
    double baseFareMultiplier = 1.0,
    double seatDiscount = 0.0,
  }) {
    // Find the fare entry for the selected route
    Map<String, dynamic>? fareEntry = fareMatrix.firstWhere(
      (item) =>
          item['from_stop'] == fromStopOrder && item['to_stop'] == toStopOrder,
      orElse: () => <String, dynamic>{},
    );

    if (fareEntry.isEmpty) {
      throw Exception('Fare not found for selected route');
    }

    double baseFare = (fareEntry['fare'] ?? 0.0).toDouble();
    baseFare *= baseFareMultiplier;

    // Apply seat discount
    double discountAmount = baseFare * seatDiscount;
    double discountedFare = baseFare - discountAmount;

    // Calculate total fare
    double totalFare = discountedFare * numberOfSeats;

    // Check if it's peak hour
    bool isPeakHour = _isPeakHour(bookingTime);
    double peakHourMultiplier = isPeakHour ? 1.2 : 1.0;
    totalFare *= peakHourMultiplier;

    return {
      'base_fare': baseFare,
      'discount_amount': discountAmount,
      'discounted_fare': discountedFare,
      'number_of_seats': numberOfSeats,
      'total_fare': totalFare,
      'is_peak_hour': isPeakHour,
      'peak_hour_multiplier': peakHourMultiplier,
      'seat_discount_percentage': seatDiscount * 100,
      'from_stop': fromStopOrder,
      'to_stop': toStopOrder,
    };
  }

  /// Get available seats for a trip
  static List<int> getAvailableSeats({
    required int totalSeats,
    required List<int> occupiedSeats,
  }) {
    List<int> allSeats = List.generate(totalSeats, (index) => index + 1);
    return allSeats.where((seat) => !occupiedSeats.contains(seat)).toList();
  }

  /// Format fare for display
  static String formatFare(dynamic fare) {
    if (fare == null) return 'PKR 0';

    int fareValue = 0;
    if (fare is int) {
      fareValue = fare;
    } else if (fare is num) {
      fareValue = fare.round();
    } else if (fare is String) {
      fareValue = int.tryParse(fare) ?? (double.tryParse(fare)?.round() ?? 0);
    }

    return 'PKR $fareValue';
  }

  /// Get fare breakdown text for display
  static String getFareBreakdownText(Map<String, dynamic> breakdown) {
    if (breakdown.isEmpty) return 'No fare breakdown available';

    List<String> parts = [];

    if (breakdown['base_fare'] != null) {
      parts.add('Base Fare: ${formatFare(breakdown['base_fare'])}');
    }

    if (breakdown['discount_amount'] != null &&
        breakdown['discount_amount'] > 0) {
      parts.add('Discount: -${formatFare(breakdown['discount_amount'])}');
    }

    if (breakdown['number_of_seats'] != null &&
        breakdown['number_of_seats'] > 1) {
      parts.add('Seats: ${breakdown['number_of_seats']}');
    }

    if (breakdown['is_peak_hour'] == true) {
      parts.add('Peak Hour: +20%');
    }

    if (breakdown['total_fare'] != null) {
      parts.add('Total: ${formatFare(breakdown['total_fare'])}');
    }

    return parts.join('\n');
  }

  /// Distribute total price across stops proportionally based on distance
  static List<Map<String, dynamic>> distributeTotalPrice(
    List<Map<String, dynamic>> stopBreakdown,
    int newTotalPrice,
  ) {
    if (stopBreakdown.isEmpty) return stopBreakdown;

    final int n = stopBreakdown.length;
    if (n <= 0) return stopBreakdown;

    // Calculate total distance for proportional distribution
    double totalDistance = stopBreakdown.fold(
      0.0,
      (sum, stop) => sum + (stop['distance'] ?? 0.0),
    );

    // Fallback: if distance data is missing/invalid, split evenly.
    // Example: 10 across 3 segments => 3, 3, 4 (remainder goes to last).
    if (totalDistance <= 0) {
      final int base = newTotalPrice ~/ n;
      final int remainder = newTotalPrice - (base * n);
      final List<Map<String, dynamic>> updatedBreakdown = [];
      for (int i = 0; i < n; i++) {
        final stop = stopBreakdown[i];
        final Map<String, dynamic> updatedStop = Map<String, dynamic>.from(stop);
        updatedStop['price'] = i == n - 1 ? (base + remainder) : base;
        updatedBreakdown.add(updatedStop);
      }
      return updatedBreakdown;
    }

    // Distribute new price based on distance proportion.
    // Use floor for first N-1 segments and give remainder to last segment.
    final List<Map<String, dynamic>> updatedBreakdown = [];
    int distributedTotal = 0;
    for (int i = 0; i < n; i++) {
      final stop = stopBreakdown[i];
      final double stopDistance = (stop['distance'] as num?)?.toDouble() ?? 0.0;

      int newPrice;
      if (i == n - 1) {
        newPrice = newTotalPrice - distributedTotal;
      } else {
        final double proportion = stopDistance / totalDistance;
        newPrice = (newTotalPrice * proportion).floor();
        distributedTotal += newPrice;
      }

      final Map<String, dynamic> updatedStop = Map<String, dynamic>.from(stop);
      updatedStop['price'] = newPrice;
      updatedBreakdown.add(updatedStop);
    }

    return updatedBreakdown;
  }

  /// Update individual stop price and redistribute remaining total
  static List<Map<String, dynamic>> updateStopPrice(
    List<Map<String, dynamic>> stopBreakdown,
    int stopIndex,
    int newPrice,
  ) {
    if (stopBreakdown.isEmpty ||
        stopIndex < 0 ||
        stopIndex >= stopBreakdown.length) {
      return stopBreakdown;
    }

    List<Map<String, dynamic>> updatedBreakdown = List.from(stopBreakdown);

    // Update the specific stop price
    updatedBreakdown[stopIndex] = Map<String, dynamic>.from(
      stopBreakdown[stopIndex],
    );
    updatedBreakdown[stopIndex]['price'] = newPrice;

    // Calculate remaining stops
    List<int> remainingIndices = [];
    for (int i = 0; i < updatedBreakdown.length; i++) {
      if (i != stopIndex) {
        remainingIndices.add(i);
      }
    }

    if (remainingIndices.isNotEmpty) {
      // Calculate current total of all stops
      int currentTotal = stopBreakdown.fold<int>(
        0,
        (sum, stop) => sum + ((stop['price'] as num?)?.toInt() ?? 0),
      );

      // Calculate the difference to redistribute
      int oldPrice = (stopBreakdown[stopIndex]['price'] as num?)?.toInt() ?? 0;
      int priceDifference = newPrice - oldPrice;

      // Calculate remaining total (excluding the updated stop)
      int remainingTotal = currentTotal - oldPrice;

      if (remainingTotal > 0) {
        // Redistribute the remaining amount proportionally
        final int newRemainingTotal = remainingTotal - priceDifference;
        int redistributedTotal = 0;
        for (int i = 0; i < remainingIndices.length; i++) {
          int index = remainingIndices[i];
          int oldRemainingPrice = (stopBreakdown[index]['price'] as num?)?.toInt() ?? 0;
          int newRemainingPrice = remainingTotal > 0
              ? ((newRemainingTotal * oldRemainingPrice) / remainingTotal).round()
              : 0;

          // For the last remaining stop, ensure exact total
          if (i == remainingIndices.length - 1) {
            newRemainingPrice = newRemainingTotal - redistributedTotal;
          } else {
            redistributedTotal += newRemainingPrice;
          }

          updatedBreakdown[index]['price'] = newRemainingPrice;
        }
      }
    }

    return updatedBreakdown;
  }

  /// Update individual stop price without affecting other stops (just increases total)
  static List<Map<String, dynamic>> updateStopPriceOnly(
    List<Map<String, dynamic>> stopBreakdown,
    int stopIndex,
    int newPrice,
  ) {
    if (stopBreakdown.isEmpty ||
        stopIndex < 0 ||
        stopIndex >= stopBreakdown.length) {
      return stopBreakdown;
    }

    List<Map<String, dynamic>> updatedBreakdown = List.from(stopBreakdown);

    // Update only the specific stop price, leave others unchanged
    updatedBreakdown[stopIndex] = Map<String, dynamic>.from(
      stopBreakdown[stopIndex],
    );
    updatedBreakdown[stopIndex]['price'] = newPrice;

    return updatedBreakdown;
  }

  /// HYBRID FARE CALCULATION METHODS
  /// These methods allow users to edit either total fare or individual stop fares
  /// and automatically adjust the other values accordingly

  /// Calculate fare with hybrid editing capability
  static Map<String, dynamic> calculateHybridFare({
    required List<Map<String, dynamic>> routeStops,
    required String fuelType,
    required String vehicleType,
    required DateTime departureTime,
    required int totalSeats,
    double? customTotalFare, // If user edits total fare
    Map<int, double>? customStopFares, // If user edits individual stop fares
  }) {
    // 1. Calculate initial fare breakdown
    List<Map<String, dynamic>> stopBreakdown = _calculateSimpleStopBreakdown(
      routeStops,
      fuelType,
      vehicleType,
      departureTime,
    );

    // 2. Apply user customizations if provided
    if (customTotalFare != null) {
      // User edited total fare - redistribute to individual stops
      stopBreakdown = _redistributeTotalToStops(stopBreakdown, customTotalFare);
    } else if (customStopFares != null && customStopFares.isNotEmpty) {
      // User edited individual stop fares - recalculate total
      stopBreakdown = _updateIndividualStopFares(
        stopBreakdown,
        customStopFares,
      );
    }

    // 3. Calculate final totals
    double totalDistance = stopBreakdown.fold(
      0.0,
      (sum, stop) => sum + (stop['distance'] ?? 0.0),
    );
    int totalDuration = stopBreakdown.fold(
      0,
      (sum, stop) => sum + (stop['duration'] as int? ?? 0),
    );
    double totalPrice = stopBreakdown.fold(
      0.0,
      (sum, stop) => sum + (stop['price'] ?? 0.0),
    );

    // 4. Apply minimum fare to total (if needed)
    double minimumFare =
        (_minimumFares[vehicleType] ?? _minimumFares['Sedan']!).toDouble();
    double finalTotalPrice = totalPrice < minimumFare
        ? minimumFare
        : totalPrice;

    // 5. If minimum fare was applied, redistribute to individual stops proportionally
    if (totalPrice < minimumFare && totalPrice > 0) {
      double redistributionRatio = finalTotalPrice / totalPrice;
      for (int i = 0; i < stopBreakdown.length; i++) {
        double originalPrice =
            (stopBreakdown[i]['price'] as num?)?.toDouble() ?? 0.0;
        double newPrice = originalPrice * redistributionRatio;
        stopBreakdown[i]['price'] = newPrice;
      }
    }

    // 6. Get calculation parameters for breakdown
    double baseRatePerKm = _baseRates[fuelType] ?? _baseRates['Petrol']!;
    double vehicleMultiplier =
        _vehicleMultipliers[vehicleType] ?? _vehicleMultipliers['Sedan']!;
    bool isPeakHour = _isPeakHour(departureTime);
    double timeMultiplier = isPeakHour ? 1.3 : 1.0;
    double seatFactor = _seatFactors[vehicleType] ?? _seatFactors['Sedan']!;
    String distanceCategory = _getDistanceCategory(totalDistance);
    double distanceFactor =
        _distanceFactors[distanceCategory] ?? _distanceFactors['0-10']!;

    return {
      'base_fare': finalTotalPrice,
      'total_distance_km': totalDistance,
      'total_duration_minutes': totalDuration,
      'total_price': finalTotalPrice,
      'stop_breakdown': stopBreakdown,
      'calculation_breakdown': {
        'total_distance_km': totalDistance,
        'total_duration_minutes': totalDuration,
        'total_price': finalTotalPrice,
        'base_rate_per_km': baseRatePerKm,
        'vehicle_multiplier': vehicleMultiplier,
        'time_multiplier': timeMultiplier,
        'is_peak_hour': isPeakHour,
        'seat_factor': seatFactor,
        'distance_factor': distanceFactor,
        'distance_category': distanceCategory,
        'minimum_fare_applied': totalPrice < minimumFare,
        'minimum_fare': minimumFare,
        'vehicle_type': vehicleType,
        'fuel_type': fuelType,
        'total_seats': totalSeats,
        'custom_total_fare_applied': customTotalFare != null,
        'custom_stop_fares_applied':
            customStopFares != null && customStopFares.isNotEmpty,
      },
    };
  }

  /// When user updates total fare, redistribute it to individual stops based on distance
  static List<Map<String, dynamic>> _redistributeTotalToStops(
    List<Map<String, dynamic>> stopBreakdown,
    double newTotalFare,
  ) {
    if (stopBreakdown.isEmpty) return stopBreakdown;

    // Calculate total distance for proportional distribution
    double totalDistance = stopBreakdown.fold(
      0.0,
      (sum, stop) => sum + (stop['distance'] ?? 0.0),
    );

    if (totalDistance <= 0) return stopBreakdown;

    // Distribute new total fare based on distance proportion
    List<Map<String, dynamic>> updatedBreakdown = [];
    double distributedTotal = 0.0;

    for (int i = 0; i < stopBreakdown.length; i++) {
      var stop = Map<String, dynamic>.from(stopBreakdown[i]);
      double stopDistance = stop['distance'] ?? 0.0;

      // Calculate price based on distance proportion
      double distanceProportion = stopDistance / totalDistance;
      double newPrice = newTotalFare * distanceProportion;

      // For the last stop, ensure the total adds up exactly
      if (i == stopBreakdown.length - 1) {
        newPrice = newTotalFare - distributedTotal;
      } else {
        newPrice = double.parse(newPrice.toStringAsFixed(2));
        distributedTotal += newPrice;
      }

      stop['price'] = newPrice;
      updatedBreakdown.add(stop);
    }

    return updatedBreakdown;
  }

  /// When user updates individual stop fares, recalculate total
  static List<Map<String, dynamic>> _updateIndividualStopFares(
    List<Map<String, dynamic>> stopBreakdown,
    Map<int, double> customStopFares,
  ) {
    List<Map<String, dynamic>> updatedBreakdown = List.from(stopBreakdown);

    // Update individual stop prices
    customStopFares.forEach((stopIndex, newPrice) {
      if (stopIndex >= 0 && stopIndex < updatedBreakdown.length) {
        updatedBreakdown[stopIndex] = Map<String, dynamic>.from(
          stopBreakdown[stopIndex],
        );
        updatedBreakdown[stopIndex]['price'] = newPrice;
      }
    });

    return updatedBreakdown;
  }

  /// Calculate individual stop breakdown with simple pricing (no bulk discounts)
  static List<Map<String, dynamic>> _calculateSimpleStopBreakdown(
    List<Map<String, dynamic>> routeStops,
    String fuelType,
    String vehicleType,
    DateTime departureTime,
  ) {
    if (routeStops.length < 2) return [];

    List<Map<String, dynamic>> breakdown = [];

    // Get calculation parameters
    double baseRatePerKm = _baseRates[fuelType] ?? _baseRates['Petrol']!;
    double vehicleMultiplier =
        _vehicleMultipliers[vehicleType] ?? _vehicleMultipliers['Sedan']!;
    bool isPeakHour = _isPeakHour(departureTime);
    double timeMultiplier = isPeakHour ? 1.2 : 1.0;
    double seatFactor = _seatFactors[vehicleType] ?? _seatFactors['Sedan']!;

    for (int i = 0; i < routeStops.length - 1; i++) {
      double lat1 = routeStops[i]['latitude']?.toDouble() ?? 0.0;
      double lon1 = routeStops[i]['longitude']?.toDouble() ?? 0.0;
      double lat2 = routeStops[i + 1]['latitude']?.toDouble() ?? 0.0;
      double lon2 = routeStops[i + 1]['longitude']?.toDouble() ?? 0.0;

      double distance = _haversineDistance(lat1, lon1, lat2, lon2);
      int duration = _calculateDuration(distance);

      // Simple price calculation: Base Rate × Distance × Multipliers
      double stopPrice =
          baseRatePerKm *
          distance *
          vehicleMultiplier *
          timeMultiplier *
          seatFactor;

      // Apply distance factor
      String distanceCategory = _getDistanceCategory(distance);
      double distanceFactor =
          _distanceFactors[distanceCategory] ?? _distanceFactors['0-10']!;
      stopPrice *= distanceFactor;

      breakdown.add({
        'from_stop': i + 1,
        'to_stop': i + 2,
        'from_stop_name': routeStops[i]['stop_name'] ?? 'Stop ${i + 1}',
        'to_stop_name': routeStops[i + 1]['stop_name'] ?? 'Stop ${i + 2}',
        'distance': distance,
        'duration': duration,
        'price': stopPrice,
        'from_coordinates': {'lat': lat1, 'lng': lon1},
        'to_coordinates': {'lat': lat2, 'lng': lon2},
        'price_breakdown': {
          'base_rate_per_km': baseRatePerKm,
          'vehicle_multiplier': vehicleMultiplier,
          'time_multiplier': timeMultiplier,
          'is_peak_hour': isPeakHour,
          'seat_factor': seatFactor,
          'distance_km': distance,
          'duration_minutes': duration,
          'distance_factor': distanceFactor,
        },
      });
    }

    return breakdown;
  }

  /// Update total fare and redistribute to individual stops
  static Map<String, dynamic> updateTotalFare({
    required Map<String, dynamic> currentFareData,
    required double newTotalFare,
  }) {
    List<Map<String, dynamic>> stopBreakdown = List<Map<String, dynamic>>.from(
      currentFareData['stop_breakdown'] ?? [],
    );

    // Redistribute new total to individual stops
    List<Map<String, dynamic>> updatedBreakdown = _redistributeTotalToStops(
      stopBreakdown,
      newTotalFare,
    );

    // Update the fare data
    Map<String, dynamic> updatedFareData = Map<String, dynamic>.from(
      currentFareData,
    );
    updatedFareData['total_price'] = newTotalFare;
    updatedFareData['base_fare'] = newTotalFare;
    updatedFareData['stop_breakdown'] = updatedBreakdown;
    updatedFareData['calculation_breakdown']['total_price'] = newTotalFare;
    updatedFareData['calculation_breakdown']['custom_total_fare_applied'] =
        true;

    return updatedFareData;
  }

  /// Update individual stop fare and recalculate total
  static Map<String, dynamic> updateIndividualStopFare({
    required Map<String, dynamic> currentFareData,
    required int stopIndex,
    required double newStopFare,
  }) {
    List<Map<String, dynamic>> stopBreakdown = List<Map<String, dynamic>>.from(
      currentFareData['stop_breakdown'] ?? [],
    );

    if (stopIndex < 0 || stopIndex >= stopBreakdown.length) {
      return currentFareData;
    }

    // Update the specific stop fare
    stopBreakdown[stopIndex] = Map<String, dynamic>.from(
      stopBreakdown[stopIndex],
    );
    stopBreakdown[stopIndex]['price'] = newStopFare;

    // Recalculate total
    double newTotalFare = stopBreakdown.fold(
      0.0,
      (sum, stop) => sum + (stop['price'] ?? 0.0),
    );

    // Update the fare data
    Map<String, dynamic> updatedFareData = Map<String, dynamic>.from(
      currentFareData,
    );
    updatedFareData['total_price'] = newTotalFare;
    updatedFareData['base_fare'] = newTotalFare;
    updatedFareData['stop_breakdown'] = stopBreakdown;
    updatedFareData['calculation_breakdown']['total_price'] = newTotalFare;
    updatedFareData['calculation_breakdown']['custom_stop_fares_applied'] =
        true;

    return updatedFareData;
  }

  /// Get fare summary for display
  static Map<String, dynamic> getFareSummary(Map<String, dynamic> fareData) {
    List<Map<String, dynamic>> stopBreakdown = List<Map<String, dynamic>>.from(
      fareData['stop_breakdown'] ?? [],
    );

    double totalPrice = fareData['total_price'] ?? 0.0;
    double totalDistance = fareData['total_distance_km'] ?? 0.0;
    int totalDuration = fareData['total_duration_minutes'] ?? 0;

    return {
      'total_fare': totalPrice,
      'total_distance_km': totalDistance,
      'total_duration_minutes': totalDuration,
      'number_of_stops': stopBreakdown.length + 1, // +1 for the starting point
      'average_fare_per_stop': stopBreakdown.isNotEmpty
          ? totalPrice / stopBreakdown.length
          : 0.0,
      'fare_per_km': totalDistance > 0 ? totalPrice / totalDistance : 0.0,
      'custom_fare_applied':
          fareData['calculation_breakdown']?['custom_total_fare_applied'] ==
              true ||
          fareData['calculation_breakdown']?['custom_stop_fares_applied'] ==
              true,
    };
  }
}
