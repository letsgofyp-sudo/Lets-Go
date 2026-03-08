# Controllers Directory

This directory contains all the controllers for the application, following a consistent pattern of separating business logic from UI presentation.

## Directory Structure

```
controllers/
├── signup_login_controllers/
│   ├── forgot_password_controller.dart
│   ├── login_controller.dart
│   ├── navigation_controller.dart
│   ├── otp_verification_controller.dart
│   ├── otp_verification_reset_controller.dart
│   ├── reset_password_controller.dart
│   └── signup_controller.dart
└── ride_posting_controllers/
    ├── create_ride_controller.dart
    ├── create_route_controller.dart
    ├── ride_details_controller.dart
    └── README.md
```

## Controller Categories

### 1. Signup/Login Controllers
These controllers handle user authentication and registration:
- **SignupController**: User registration with file uploads
- **LoginController**: User authentication
- **ForgotPasswordController**: Password reset functionality
- **OTP Controllers**: OTP verification for various flows
- **ResetPasswordController**: Password reset implementation
- **NavigationController**: Navigation state management

### 2. Ride Posting Controllers
These controllers handle ride creation and management:
- **CreateRideController**: Entry point for ride creation
- **CreateRouteController**: Route creation and map interaction
- **RideDetailsController**: Ride details and fare calculation

## Common Controller Pattern

All controllers follow this consistent pattern:

```dart
class ExampleController {
  // State variables
  List<SomeType> data = [];
  bool isLoading = false;
  String? errorMessage;
  
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
      isLoading = true;
      onStateChanged?.call();
      
      // Do work
      final result = await someApiCall();
      
      if (result['success']) {
        onSuccess?.call(result['message']);
      } else {
        onError?.call(result['error']);
      }
    } catch (e) {
      onError?.call('Error: $e');
    } finally {
      isLoading = false;
      onStateChanged?.call();
    }
  }
  
  void dispose() {
    // Cleanup resources
  }
}
```

## Screen Integration Pattern

Screens use controllers consistently:

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
      onError: (message) => _showError(message),
      onSuccess: (message) => _showSuccess(message),
    );
    
    _initializeController();
  }
  
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }
  
  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
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
        ? const Center(child: CircularProgressIndicator())
        : _buildContent(),
    );
  }
  
  Widget _buildContent() {
    // UI that uses _controller.data, _controller.methods(), etc.
  }
}
```

## Benefits of This Architecture

1. **Separation of Concerns**: UI and business logic are completely separated
2. **Testability**: Controllers can be easily unit tested without UI dependencies
3. **Reusability**: Controllers can be reused across different UI implementations
4. **Maintainability**: Changes to business logic don't affect UI code
5. **Consistency**: All controllers follow the same pattern
6. **Error Handling**: Centralized and consistent error handling
7. **State Management**: Clear state management through callbacks

## API Integration

Controllers handle all API calls through dedicated services:
- **ApiService**: Main API service for backend communication
- **PlacesService**: Location and place search functionality
- **FareCalculator**: Fare calculation utilities

## Error Handling Strategy

All controllers implement consistent error handling:
- Try-catch blocks for all async operations
- User-friendly error messages
- Fallback mechanisms for API failures
- Graceful degradation when services are unavailable
- Proper cleanup in dispose methods

## State Management

Controllers manage state through:
- Direct state variables
- Callback functions for UI updates
- Automatic state synchronization with UI
- Proper cleanup in dispose methods

## Future Extensibility

This architecture makes it easy to:
- Add new controllers for new features
- Modify business logic without touching UI
- Add new UI implementations using existing controllers
- Implement different state management solutions
- Add caching and offline support
- Implement different API services 