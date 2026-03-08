# Flutter Fare Calculator

This directory contains the client-side fare calculation implementation for the bus/shuttle service. The fare calculator runs entirely in Flutter, providing real-time fare calculations without requiring server round-trips.

## Features

- **Real-time fare calculation** - Instant fare updates as users select stops and seats
- **Peak hour detection** - Automatically applies peak hour pricing based on current time
- **Multi-seat discounts** - Supports discounts for booking multiple seats
- **Distance-based pricing** - Calculates fares based on distance between stops
- **Offline capability** - Works with cached fare matrices even without network
- **Validation** - Client-side validation of fare calculation parameters
- **Formatting utilities** - Built-in fare formatting and breakdown display

## Files

### `fare_calculator.dart`
The main fare calculation utility class with the following key methods:

- `isPeakHour(DateTime time)` - Determines if current time is peak hour
- `calculateDistanceFare()` - Calculates fare for a single seat between two stops
- `calculateBookingFare()` - Calculates total fare for a booking with multiple seats
- `validateFareCalculation()` - Validates fare calculation parameters
- `getAvailableSeats()` - Gets list of available seats for a trip
- `convertFareMatrix()` - Converts Django fare matrix format to Flutter format
- `formatFare()` - Formats fare amounts for display
- `getFareBreakdownText()` - Generates human-readable fare breakdown

### `api_service.dart`
API service for communicating with the Django backend:

- `getRouteWithFareMatrix()` - Fetches route data with fare matrix
- `getTripDetails()` - Fetches trip details
- `getAvailableSeats()` - Gets available seats for a trip
- `createBooking()` - Creates a new booking
- `searchRoutes()` - Searches for available routes

## Usage Examples

### Basic Fare Calculation

```dart
import '../utils/fare_calculator.dart';

// Convert Django fare matrix to Flutter format
final fareMatrix = FareCalculator.convertFareMatrix(djangoFareMatrix);

// Calculate fare for a booking
final breakdown = FareCalculator.calculateBookingFare(
  fromStopOrder: 1,
  toStopOrder: 3,
  numberOfSeats: 2,
  fareMatrix: fareMatrix,
  bookingTime: DateTime.now(),
  baseFareMultiplier: 1.0,
  seatDiscount: 0.1, // 10% discount for multiple seats
);

// Display fare
print('Total fare: ${FareCalculator.formatFare(breakdown['total_fare'])}');
```

### Real-time Fare Updates in UI

```dart
class BookingScreen extends StatefulWidget {
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  int? selectedFromStop;
  int? selectedToStop;
  int numberOfSeats = 1;
  Map<String, dynamic>? fareBreakdown;

  void _calculateFare() {
    if (selectedFromStop == null || selectedToStop == null) return;

    final breakdown = FareCalculator.calculateBookingFare(
      fromStopOrder: selectedFromStop!,
      toStopOrder: selectedToStop!,
      numberOfSeats: numberOfSeats,
      fareMatrix: fareMatrix,
      bookingTime: DateTime.now(),
    );

    setState(() {
      fareBreakdown = breakdown;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stop selection dropdowns
        DropdownButtonFormField<int>(
          value: selectedFromStop,
          items: routeStops.map((stop) => DropdownMenuItem(
            value: stop['stop_order'],
            child: Text(stop['stop_name']),
          )).toList(),
          onChanged: (value) {
            setState(() {
              selectedFromStop = value;
              fareBreakdown = null;
            });
          },
        ),
        
        // Fare display
        if (fareBreakdown != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                FareCalculator.getFareBreakdownText(fareBreakdown!),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }
}
```

### API Integration

```dart
import '../services/api_service.dart';

class BookingService {
  static Future<Map<String, dynamic>> getBookingData({
    required int routeId,
    required int tripId,
    required int fromStopOrder,
    required int toStopOrder,
    required int numberOfSeats,
  }) async {
    // Get route data with fare matrix from API
    final routeData = await ApiService.getRouteWithFareMatrix(routeId);
    
    // Calculate fare using Flutter calculator
    final fareBreakdown = FareCalculator.calculateBookingFare(
      fromStopOrder: fromStopOrder,
      toStopOrder: toStopOrder,
      numberOfSeats: numberOfSeats,
      fareMatrix: routeData['fare_matrix'],
      bookingTime: DateTime.now(),
    );
    
    return {
      'route_data': routeData,
      'fare_breakdown': fareBreakdown,
    };
  }
}
```

## Peak Hour Configuration

Peak hours are configured in the `isPeakHour()` method:

- **Morning Peak**: 7:00 AM - 9:00 AM
- **Evening Peak**: 5:00 PM - 7:00 PM

You can modify these times by updating the time ranges in the method:

```dart
static bool isPeakHour(DateTime time) {
  final hour = time.hour;
  final minute = time.minute;
  final timeInMinutes = hour * 60 + minute;
  
  // Customize peak hours here
  return (timeInMinutes >= 420 && timeInMinutes <= 540) ||  // 7:00-9:00 AM
         (timeInMinutes >= 1020 && timeInMinutes <= 1140);   // 5:00-7:00 PM
}
```

## Fare Matrix Format

The fare calculator expects fare matrices in the following format:

```dart
Map<String, dynamic> fareMatrix = {
  '1-2': {
    'base_fare': 50.0,
    'peak_fare': 60.0,
    'off_peak_fare': 45.0,
    'distance_km': 5.0,
    'from_stop_name': 'Stop A',
    'to_stop_name': 'Stop B',
  },
  '1-3': {
    'base_fare': 80.0,
    'peak_fare': 95.0,
    'off_peak_fare': 70.0,
    'distance_km': 8.0,
    'from_stop_name': 'Stop A',
    'to_stop_name': 'Stop C',
  },
  // ... more fare segments
};
```

## Caching Strategy

For optimal performance, implement caching for fare matrices:

```dart
class FareMatrixCache {
  static final Map<int, Map<String, dynamic>> _cache = {};
  static final Map<int, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(hours: 24);

  static Map<String, dynamic>? getCachedMatrix(int routeId) {
    final timestamp = _cacheTimestamps[routeId];
    if (timestamp != null && 
        DateTime.now().difference(timestamp) < _cacheExpiry) {
      return _cache[routeId];
    }
    return null;
  }

  static void cacheMatrix(int routeId, Map<String, dynamic> matrix) {
    _cache[routeId] = matrix;
    _cacheTimestamps[routeId] = DateTime.now();
  }

  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}
```

## Benefits of Client-Side Calculation

1. **Performance**: No network delays for fare calculations
2. **User Experience**: Instant fare updates as users make selections
3. **Offline Support**: Works with cached data even without internet
4. **Reduced Server Load**: Fewer API calls for fare calculations
5. **Real-time Updates**: Fare changes immediately when parameters change
6. **Consistency**: Same calculation logic across all client devices

## Integration with Django Backend

The Flutter fare calculator is designed to work seamlessly with the Django backend:

1. **Fare Matrix Sync**: Django provides fare matrices via API
2. **Validation**: Client validates calculations, server double-checks
3. **Caching**: Fare matrices are cached locally and updated periodically
4. **Booking Creation**: Client sends calculated fare breakdown to server
5. **Audit Trail**: Server logs all fare calculations for verification

## Testing

Test the fare calculator with various scenarios:

```dart
void testFareCalculation() {
  final fareMatrix = {
    '1-2': {
      'base_fare': 50.0,
      'peak_fare': 60.0,
      'off_peak_fare': 45.0,
      'distance_km': 5.0,
    },
  };

  // Test single seat, off-peak
  final breakdown1 = FareCalculator.calculateBookingFare(
    fromStopOrder: 1,
    toStopOrder: 2,
    numberOfSeats: 1,
    fareMatrix: fareMatrix,
    bookingTime: DateTime(2024, 1, 1, 10, 0), // 10 AM (off-peak)
  );
  assert(breakdown1['total_fare'] == 45.0);

  // Test multiple seats, peak hour
  final breakdown2 = FareCalculator.calculateBookingFare(
    fromStopOrder: 1,
    toStopOrder: 2,
    numberOfSeats: 2,
    fareMatrix: fareMatrix,
    bookingTime: DateTime(2024, 1, 1, 8, 0), // 8 AM (peak)
    seatDiscount: 0.1,
  );
  assert(breakdown2['total_fare'] == 108.0); // 60 * 2 * 0.9
}
```

## Performance Considerations

- **Memory Usage**: Fare matrices are typically small (< 1MB)
- **Calculation Speed**: Calculations complete in < 1ms
- **Cache Size**: Limit cache to most frequently used routes
- **Updates**: Refresh fare matrices when prices change
- **Validation**: Always validate server-side for security

## Security Notes

- **Client-side validation only**: Server must always validate fare calculations
- **Audit logging**: Log all client-side calculations on server
- **Price verification**: Server should verify final fare before booking
- **Rate limiting**: Implement rate limiting on fare calculation APIs
- **Data integrity**: Use checksums or signatures for fare matrix integrity 