import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../constants.dart';
import 'dart:io';

class OTPVerificationController {
  TextEditingController emailOtpController = TextEditingController();
  TextEditingController mobileOtpController = TextEditingController();

  bool isLoading = false;
  bool isSubmittingRegistration = false;
  bool needsResubmit = false;
  String? errorMessage;
  String? lastServerErrorField;
  Map<String, dynamic>? signupData;
  bool emailVerified = false;
  bool phoneVerified = false;
  int? emailExpiryTimestamp;
  int? phoneExpiryTimestamp;
  int emailSecondsLeft = 0;
  int phoneSecondsLeft = 0;
  Timer? emailTimer;
  Timer? phoneTimer;

  // Callbacks for UI updates
  VoidCallback? onStateChanged;

  OTPVerificationController({this.onStateChanged});

  void dispose() {
    emailOtpController.dispose();
    mobileOtpController.dispose();
    emailTimer?.cancel();
    phoneTimer?.cancel();
  }

  Future<void> loadSignupData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('pending_signup');
    final status = prefs.getString('pending_signup_status');
    final resubmit = prefs.getBool('signup_needs_resubmit');
    if (data != null) {
      signupData = jsonDecode(data);
    }
    if (status != null) {
      final statusMap = jsonDecode(status);
      emailVerified = statusMap['email_verified'] == true;
      phoneVerified = statusMap['phone_verified'] == true;
    }
    needsResubmit = resubmit == true;
    onStateChanged?.call();
  }

  Future<void> _setNeedsResubmit(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    needsResubmit = v;
    await prefs.setBool('signup_needs_resubmit', v);
    onStateChanged?.call();
  }

  Future<void> saveOtpStatus({
    bool? emailVerifiedOverride,
    bool? phoneVerifiedOverride,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final status = {
      'email_verified': emailVerifiedOverride ?? emailVerified,
      'phone_verified': phoneVerifiedOverride ?? phoneVerified,
    };
    await prefs.setString('pending_signup_status', jsonEncode(status));
    emailVerified = status['email_verified'] == true;
    phoneVerified = status['phone_verified'] == true;
    onStateChanged?.call();
  }

  void initExpiryFromArgs(Map<String, dynamic>? args) {
    // print('initExpiryFromArgs: $args');
    // print('Current time (s): ${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    if (args != null) {
      if (args['email_expiry'] != null) {
        emailExpiryTimestamp = int.tryParse(args['email_expiry'].toString());
        // print('Parsed emailExpiryTimestamp: $emailExpiryTimestamp');
        startEmailTimer();
      }
      if (args['phone_expiry'] != null) {
        phoneExpiryTimestamp = int.tryParse(args['phone_expiry'].toString());
        // print('Parsed phoneExpiryTimestamp: $phoneExpiryTimestamp');
        startPhoneTimer();
      }
    }
  }

  void startEmailTimer() {
    emailTimer?.cancel();
    if (emailExpiryTimestamp == null) return;
    emailSecondsLeft =
        emailExpiryTimestamp! - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (emailSecondsLeft < 0) emailSecondsLeft = 0;
    onStateChanged?.call();
    emailTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      emailSecondsLeft =
          emailExpiryTimestamp! - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (emailSecondsLeft <= 0) {
        emailSecondsLeft = 0;
        timer.cancel();
      }
      onStateChanged?.call();
    });
  }

  void startPhoneTimer() {
    phoneTimer?.cancel();
    if (phoneExpiryTimestamp == null) return;
    phoneSecondsLeft =
        phoneExpiryTimestamp! - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (phoneSecondsLeft < 0) phoneSecondsLeft = 0;
    onStateChanged?.call();
    phoneTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      phoneSecondsLeft =
          phoneExpiryTimestamp! - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (phoneSecondsLeft <= 0) {
        phoneSecondsLeft = 0;
        timer.cancel();
      }
      onStateChanged?.call();
    });
  }

  Future<Map<String, dynamic>> verifyOtp({
    required bool verifyEmail,
    required bool verifyPhone,
    required BuildContext context,
  }) async {
    if ((verifyEmail && emailOtpController.text.isEmpty) ||
        (verifyPhone && mobileOtpController.text.isEmpty)) {
      errorMessage = 'Please enter all required OTPs.';
      onStateChanged?.call();
      return {'success': false};
    }
    // OTP validation
    if (verifyEmail && !RegExp(r'^\d{6}?$').hasMatch(emailOtpController.text)) {
      errorMessage = 'Email OTP must be 6 digits.';
      onStateChanged?.call();
      return {'success': false};
    }
    if (verifyPhone &&
        !RegExp(r'^\d{6}?$').hasMatch(mobileOtpController.text)) {
      errorMessage = 'Mobile OTP must be 6 digits.';
      onStateChanged?.call();
      return {'success': false};
    }
    isLoading = true;
    onStateChanged?.call();
    final urlEndpoint = Uri.parse('$url/lets_go/verify_otp/');
    try {
      // Only send minimal data for OTP verification
      final Map<String, String> body = {};
      if (signupData != null) {
        if (signupData!['email'] != null) body['email'] = signupData!['email'];
        if (signupData!['phone_no'] != null) {
          body['phone_no'] = signupData!['phone_no'];
        }
      }
      body['otp_for'] = 'registration';
      if (verifyEmail) {
        body['otp'] = emailOtpController.text;
        body['which'] = 'email';
      } else if (verifyPhone) {
        body['otp'] = mobileOtpController.text;
        body['which'] = 'phone';
      }
      final response = await http.post(urlEndpoint, body: body);
      final data = jsonDecode(response.body);
      isLoading = false;
      if (response.statusCode == 200 && data['success'] == true) {
        await saveOtpStatus(
          emailVerifiedOverride: verifyEmail ? true : null,
          phoneVerifiedOverride: verifyPhone ? true : null,
        );
        if (data['email_expiry'] != null) {
          emailExpiryTimestamp = data['email_expiry'];
          startEmailTimer();
        }
        if (data['phone_expiry'] != null) {
          phoneExpiryTimestamp = data['phone_expiry'];
          startPhoneTimer();
        }
        // Automatically register as soon as both OTPs are verified
        if ((emailVerified || data['email_verified'] == true) &&
            (phoneVerified || data['phone_verified'] == true)) {
          if (context.mounted) {
            await submitFinalRegistration(context);
          }
        } else {
          errorMessage = 'OTP verified. Please verify the remaining OTP.';
        }
      } else {
        errorMessage = data['error'] ?? 'OTP verification failed.';
      }
      onStateChanged?.call();
      return data;
    } catch (e) {
      isLoading = false;
      errorMessage = 'OTP verification failed. Try again.';
      onStateChanged?.call();
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> resendOtp(String type) async {
    isLoading = true;
    onStateChanged?.call();
    final urlEndpoint = Uri.parse('$url/lets_go/send_otp/');
    try {
      // Only send minimal data for OTP resend
      final Map<String, String> body = {};
      if (signupData != null) {
        if (signupData!['email'] != null) body['email'] = signupData!['email'];
        if (signupData!['phone_no'] != null) {
          body['phone_no'] = signupData!['phone_no'];
        }
      }
      body['otp_for'] = 'registration';
      body['resend'] = type;
      final response = await http.post(urlEndpoint, body: body);
      isLoading = false;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          errorMessage = 'OTP resent to your $type.';
          if (type == 'email' || type == 'both') {
            if (data['email_expiry'] != null) {
              emailExpiryTimestamp = data['email_expiry'];
              startEmailTimer();
            }
          }
          if (type == 'phone' || type == 'both') {
            if (data['phone_expiry'] != null) {
              phoneExpiryTimestamp = data['phone_expiry'];
              startPhoneTimer();
            }
          }
        } else {
          errorMessage = data['error'] ?? 'Failed to resend OTP.';
        }
        onStateChanged?.call();
        return data;
      } else {
        final data = jsonDecode(response.body);
        errorMessage = data['error'] ?? 'Failed to resend OTP.';
        onStateChanged?.call();
        return {'success': false};
      }
    } catch (e) {
      isLoading = false;
      errorMessage = 'Failed to resend OTP. Please check your connection.';
      onStateChanged?.call();
      return {'success': false};
    }
  }

  // Cleanup all temporary signup data and any local image files after successful registration
  Future<void> cleanupSignupData() async {
    final prefs = await SharedPreferences.getInstance();

    // Read pending_signup once so we can also clean up any local image files it references
    final data = prefs.getString('pending_signup');
    if (data != null) {
      final allFields = Map<String, dynamic>.from(jsonDecode(data));
      allFields.forEach((k, v) {
        if (v is String) {
          final s = v.trim();
          final low = s.toLowerCase();
          final isImagePath = low.endsWith('.jpg') ||
              low.endsWith('.jpeg') ||
              low.endsWith('.png') ||
              low.endsWith('.webp');
          if (!isImagePath) return;

          final file = File(s);
          if (file.existsSync()) {
            file.deleteSync();
          }
        }
      });
    }

    // Remove all signup-related SharedPreferences keys
    await prefs.remove('pending_signup');
    await prefs.remove('pending_signup_status');
    await prefs.remove('signup_personal');
    await prefs.remove('signup_emergency');
    await prefs.remove('signup_cnic');
    await prefs.remove('signup_vehicles');
    await prefs.remove('signup_vehicle_images');
    await prefs.remove('signup_step');
    await prefs.remove('signup_locked');
    await prefs.remove('signup_username_verified');
    await prefs.remove('signup_verified_username');
    await prefs.remove('signup_last_reserved_username');
    await prefs.remove('signup_needs_resubmit');
  }

  Future<void> submitFinalRegistration(BuildContext context) async {
    isLoading = true;
    isSubmittingRegistration = true;
    errorMessage = null;
    lastServerErrorField = null;
    await _setNeedsResubmit(false);
    onStateChanged?.call();
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('pending_signup');
      if (data == null) {
        errorMessage = 'No registration data found.';
        isLoading = false;
        isSubmittingRegistration = false;
        await _setNeedsResubmit(true);
        onStateChanged?.call();
        return;
      }
      final Map<String, dynamic> allFields = Map<String, dynamic>.from(
        jsonDecode(data),
      );
      // print('All fields in pending_signup: ${allFields.keys}');
      final Map<String, String> fields = {};
      final Map<String, File> images = {};

      bool isKnownImageKey(String k) {
        if (k == 'profile_photo' ||
            k == 'live_photo' ||
            k == 'cnic_front_image' ||
            k == 'cnic_back_image' ||
            k == 'driving_license_front' ||
            k == 'driving_license_back' ||
            k == 'accountqr') {
          return true;
        }
        if (k.startsWith('photo_front_') ||
            k.startsWith('photo_back_') ||
            k.startsWith('documents_image_')) {
          return true;
        }
        return false;
      }

      bool isImagePath(String v) {
        final s = v.trim().toLowerCase();
        return s.endsWith('.jpg') ||
            s.endsWith('.jpeg') ||
            s.endsWith('.png') ||
            s.endsWith('.webp');
      }

      allFields.forEach((k, v) {
        if (v is! String) return;
        final s = v.trim();
        if (s.isEmpty) return;
        if (s.toLowerCase() == 'null') return;

        final file = File(s);
        final exists = file.existsSync();
        final shouldAttachAsImage = isImagePath(s) || (exists && isKnownImageKey(k));
        if (shouldAttachAsImage) {
          if (exists) {
            images[k] = file;
          }
          return;
        }

        fields[k] = s;
      });
      final urlEndpoint = Uri.parse('$url/lets_go/signup/');
      final request = http.MultipartRequest('POST', urlEndpoint);
      fields.forEach((k, v) => request.fields[k] = v);
      images.forEach((k, file) {
        request.files.add(
          http.MultipartFile.fromBytes(
            k,
            file.readAsBytesSync(),
            filename: file.path.split('/').last,
          ),
        );
      });
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final dataResp = jsonDecode(responseData);
      isLoading = false;
      isSubmittingRegistration = false;
      if (response.statusCode == 200 &&
          (dataResp['success'] == true ||
              dataResp['success'] == 'true' ||
              dataResp['success'] == 'True')) {
        // Cleanup after successful registration (prefs + any local image files)
        await cleanupSignupData();
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/login');
          return; // Prevent further UI updates after navigation
        }
      } else {
        await _setNeedsResubmit(true);
        final base = (dataResp['error'] ?? 'Registration failed.').toString();
        final fieldsErr = dataResp['fields'];
        if (fieldsErr is Map && fieldsErr.isNotEmpty) {
          final firstKey = fieldsErr.keys.first.toString();
          lastServerErrorField = firstKey;
          final val = fieldsErr[firstKey];
          String firstMsg = '';
          if (val is List && val.isNotEmpty) {
            firstMsg = val.first.toString();
          } else if (val != null) {
            firstMsg = val.toString();
          }
          errorMessage = firstMsg.isNotEmpty ? '$base ($firstKey: $firstMsg)' : base;
        } else {
          errorMessage = base;
        }
        onStateChanged?.call();
      }
    } catch (e) {
      isLoading = false;
      isSubmittingRegistration = false;
      await _setNeedsResubmit(true);
      errorMessage = 'Registration failed. Try again. Error: $e';
      onStateChanged?.call();
    }
  }
}
