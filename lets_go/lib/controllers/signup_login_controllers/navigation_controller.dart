import 'package:flutter/material.dart';
import '../../screens/home_screen.dart';
import '../../screens/signup_login_screens/register_pending_screen.dart';

class NavigationController {
  /// Navigate to appropriate screen after login based on user status
  static void navigateAfterLogin(BuildContext context, Map<String, dynamic> userData) {
    final userStatus = userData['status']?.toString().toLowerCase();
    
    switch (userStatus) {
      case 'verified':
      case 'active':
        // User is verified, navigate to home screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(userData: userData),
          ),
        );
        break;
        
      case 'pending':
      case 'under_review':
      case 'rejected':
      case 'banned':
      case 'baned':
      case 'suspended':
        // User is pending verification or rejected/suspended
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const RegisterPendingScreen(),
            settings: RouteSettings(arguments: userData),
          ),
        );
        break;
        
      default:
        // Unknown status, show error
        _showUnknownStatusDialog(context, userData);
        break;
    }
  }

  /// Show dialog for unknown account status
  static void _showUnknownStatusDialog(BuildContext context, Map<String, dynamic> userData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Account Status Unknown'),
        content: Text(
          'Your account status is unclear (${userData['status'] ?? 'null'}). '
          'Please contact support for assistance.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to login
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Check if user can create rides
  static bool canUserCreateRides(Map<String, dynamic> userData) {
    // Check if user has driving license and vehicle
    final hasLicense = userData['driving_license'] != null && 
                      userData['driving_license'].toString().isNotEmpty;
    final hasVehicle = userData['vehicles'] != null && 
                      (userData['vehicles'] as List).isNotEmpty;
    
    return hasLicense && hasVehicle;
  }

  /// Get user verification status message
  static String getUserStatusMessage(Map<String, dynamic> userData) {
    final status = userData['status']?.toString().toLowerCase();
    
    switch (status) {
      case 'verified':
      case 'active':
        return 'Your account is verified and active.';
      case 'pending':
      case 'under_review':
        return 'Your account is under review. Please wait for verification.';
      case 'rejected':
        return 'Your account has been rejected.';
      case 'banned':
      case 'baned':
        return 'Your account has been banned.';
      case 'suspended':
        return 'Your account has been suspended.';
      default:
        return 'Account status unknown. Please contact support.';
    }
  }

  /// Get user verification status color
  static Color getUserStatusColor(Map<String, dynamic> userData) {
    final status = userData['status']?.toString().toLowerCase();
    
    switch (status) {
      case 'verified':
      case 'active':
        return Colors.green;
      case 'pending':
      case 'under_review':
        return Colors.orange;
      case 'rejected':
      case 'banned':
      case 'baned':
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}