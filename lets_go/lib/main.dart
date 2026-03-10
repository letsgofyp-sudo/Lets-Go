import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';
import 'services/background_live_tracking_service.dart';
import 'widgets/sos_floating_button.dart';

// Screens
import 'screens/signup_login_screens/login_screen.dart';
import 'screens/signup_login_screens/signup_personal_screen.dart';
import 'screens/signup_login_screens/signup_emergency_contact_screen.dart';
import 'screens/signup_login_screens/signup_cnic_screen.dart';
import 'screens/signup_login_screens/signup_vehicle_screen.dart';
import 'screens/signup_login_screens/register_pending_screen.dart';
import 'screens/signup_login_screens/otp_verification_screen.dart';
import 'screens/signup_login_screens/forgot_password_screen.dart';
import 'screens/signup_login_screens/otp_verification_reset_screen.dart';
import 'screens/signup_login_screens/reset_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/ride_posting_screens/create_ride_details_screen.dart';
import 'screens/ride_posting_screens/create_ride_screen.dart';
import 'screens/ride_posting_screens/create_route_screen.dart';
import 'screens/ride_posting_screens/my_rides_screen.dart';
import 'screens/ride_posting_screens/ride_view_screen.dart';
import 'screens/ride_posting_screens/ride_edit_screen.dart';
import 'screens/ride_booking_screens/ride_booking_details_screen.dart';
import 'screens/ride_booking_screens/ride_request_screen.dart';
import 'screens/profile_screens/profile_screen.dart';
import 'screens/support_chat_screen.dart';
import 'screens/notifications_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    debugPrint('[main] FlutterError: ${details.exceptionAsString()}');
  };
  
  // Initialize Firebase
  // ignore: avoid_print
  debugPrint('[main] Initializing Firebase...');
  try {
    await Firebase.initializeApp();
    // ignore: avoid_print
    debugPrint('[main] Firebase initialized');
  } catch (e) {
    // ignore: avoid_print
    debugPrint('[main] Firebase initializeApp failed: $e');
  }
  
  // Initialize notification service
  // ignore: avoid_print
  debugPrint('[main] Initializing NotificationService...');
  try {
    NotificationService.setNavigatorKey(MyApp.navigatorKey);
    await NotificationService.initialize();
    // ignore: avoid_print
    debugPrint('[main] NotificationService initialized');
  } catch (e) {
    // ignore: avoid_print
    debugPrint('[main] NotificationService initialize failed: $e');
  }

  try {
    await BackgroundLiveTrackingService.initialize();
  } catch (e) {
    // ignore: avoid_print
    debugPrint('[main] BackgroundLiveTrackingService initialize failed: $e');
  }
  
  // Check signup status
  String? signupStep;
  bool signupLocked = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    signupStep = prefs.getString('signup_step');
    signupLocked = prefs.getBool('signup_locked') ?? false;
  } catch (e) {
    // ignore: avoid_print
    debugPrint('[main] SharedPreferences init failed: $e');
  }

  String initialRoute;
  if (signupLocked) {
    initialRoute = '/otp_verification';
  } else if (signupStep == 'vehicle') {
    initialRoute = '/signup_vehicle';
  } else if (signupStep == 'cnic') {
    initialRoute = '/signup_cnic';
  } else if (signupStep == 'emergency') {
    initialRoute = '/signup_emergency';
  } else if (signupStep == 'personal') {
    initialRoute = '/signup_personal';
  } else {
    initialRoute = '/';
  }

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lets Go',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          primary: const Color(0xFF00897B),
          secondary: const Color(0xFF26A69A),
          tertiary: const Color(0xFF4DB6AC),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00897B),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        ),
      ),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            SosFloatingButtonOverlay(navigatorKey: navigatorKey),
          ],
        );
      },
      initialRoute: initialRoute,
      routes: {
        '/': (context) => LoginScreen(),
        '/login': (context) => LoginScreen(),
        '/signup_personal': (context) => SignupPersonalScreen(),
        '/signup_emergency': (context) => SignupEmergencyContactScreen(),
        '/signup_cnic': (context) => SignupCnicScreen(),
        '/signup_vehicle': (context) => SignupVehicleScreen(),
        '/register_pending': (context) => RegisterPendingScreen(),
        '/otp_verification': (context) => OTPVerificationScreen(),
        '/forgot_password': (context) => ForgotPasswordScreen(),
        '/otp_verification_reset': (context) => OTPVerificationResetScreen(),
        '/reset_password': (context) => ResetPasswordScreen(),
        '/home': (context) => HomeScreen(userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {}),
        '/ride_details': (context) => RideDetailsScreen(
          userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
          routeData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
        ),
        '/ride_booking_details': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is Map) {
            final m = Map<String, dynamic>.from(args);
            return RideBookingDetailsScreen(
              userData: (m['userData'] is Map) ? Map<String, dynamic>.from(m['userData'] as Map) : <String, dynamic>{},
              tripId: (m['tripId'] ?? m['trip_id'] ?? '').toString(),
            );
          }
          // Backward compatibility: allow passing just tripId string.
          final tripId = (args ?? '').toString();
          return RideBookingDetailsScreen(
            userData: <String, dynamic>{},
            tripId: tripId,
          );
        },
        '/ride-request': (context) {
          final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {});
          return RideRequestScreen(
            userData: args['userData'] ?? {},
            tripId: args['tripId'] ?? '',
            rideData: args['rideData'] ?? {},
          );
        },
        '/create_ride': (context) => CreateRideScreen(userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {}),
        '/create_route': (context) => CreateRouteScreen(
          userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
          existingRouteData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
        ),
        '/my-rides': (context) => MyRidesScreen(
          userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
        ),
        '/ride-view-edit': (context) {
          final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {});
          final bool isEditMode = args['isEditMode'] == true;
          final Map<String, dynamic> userData = args['userData'] ?? {};
          final Map<String, dynamic> rideData = args['ride'] ?? args['rideData'] ?? {};
          if (isEditMode) {
            return RideEditScreen(userData: userData, rideData: rideData);
          } else {
            return RideViewScreen(userData: userData, rideData: rideData);
          }
        },
        '/profile': (context) => ProfileScreen(
          userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
        ),
        '/support-chat': (context) => SupportChatScreen(
          userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
        ),
        '/notifications': (context) => NotificationsScreen(
          userData: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {},
        ),
      },
    );
  }
}
