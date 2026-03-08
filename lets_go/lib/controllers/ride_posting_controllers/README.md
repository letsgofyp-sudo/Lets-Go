# Ride Posting Controllers

This directory contains the controllers for the ride posting functionality, following the same pattern as the signup/login controllers. The controllers handle all business logic, API calls, and state management, while the UI screens focus purely on presentation.

## Controller Structure

### 1. CreateRideController
- **Purpose**: Handles navigation to route creation screen
- **Responsibilities**: 
  - Navigation logic
  - Future extensibility for ride creation flow
- **Usage**: Used by `CreateRideScreen`

### 2. CreateRouteController
- **Purpose**: Manages route creation and map interaction
- **Responsibilities**:
  - Location services and permissions
  - Map point management (add, edit, delete stops)
  - Route calculation and API calls
  - Place search (hybrid local + internet)
  - Route data management
- **Key Methods**:
  - `getCurrentLocation()`: Get user's current location
  - `searchPlaces()`: Search for places using hybrid approach
  - `addPointToRoute()`: Add a point to the route
  - `deleteStop()`: Remove a stop from the route
  - `updateStopName()`: Edit stop name
  - `fetchRoute()`: Get route polyline from OpenRouteService
  - `createRoute()`: Create route via API
- **Usage**: Used by `CreateRouteScreen`

### 3. RideDetailsController
- **Purpose**: Manages ride details and fare calculation
- **Responsibilities**:
  - Ride details management (date, time, seats, vehicle, etc.)
  - Dynamic fare calculation
  - Vehicle loading and selection
  - Fare breakdown and price editing
  - Ride creation via API
- **Key Methods**:
  - `loadUserVehicles()`: Load user's vehicles from API
  - `calculateDynamicFare()`: Calculate fare based on current parameters
  - `updateTotalPrice()`: Update total price and redistribute across stops
  - `updateStopPrice()`: Update individual stop price
  - `createRide()`: Create ride via API
- **Usage**: Used by `RideDetailsScreen`

## Controller Pattern

Each controller follows this pattern:

```dart
class ExampleController {
  // State variables
  List<SomeType> someData = [];
  bool isLoading = false;
  
  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  
  ExampleController({
    this.onStateChanged,
    this.onError,
    this.onSuccess,
  });
  
  // Business logic methods
  Future<void> someMethod() async {
    try {
      // Do work
      onSuccess?.call('Success message');
    } catch (e) {
      onError?.call('Error message: $e');
    } finally {
      onStateChanged?.call();
    }
  }
}
```

## Screen Integration

Screens use controllers like this:

```dart
class ExampleScreen extends StatefulWidget {
  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  late ExampleController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = ExampleController(
      onStateChanged: () => setState(() {}),
      onError: (message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      ),
      onSuccess: (message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      ),
    );
    
    // Initialize controller
    _controller.initialize();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _controller.isLoading 
        ? CircularProgressIndicator()
        : YourUIWidget(controller: _controller),
    );
  }
}
```

## Benefits of This Structure

1. **Separation of Concerns**: UI logic is separated from business logic
2. **Testability**: Controllers can be easily unit tested
3. **Reusability**: Controllers can be reused across different UI implementations
4. **Maintainability**: Changes to business logic don't affect UI code
5. **State Management**: Centralized state management through controllers
6. **Error Handling**: Consistent error handling across all controllers

## API Integration

Controllers handle all API calls through the `ApiService`:
- Route creation
- Vehicle loading
- Trip creation
- Fare calculation

## State Management

Controllers manage state through:
- Direct state variables
- Callback functions for UI updates
- Automatic state synchronization with UI

## Error Handling

All controllers implement consistent error handling:
- Try-catch blocks for async operations
- User-friendly error messages
- Fallback mechanisms for API failures
- Graceful degradation when services are unavailable 