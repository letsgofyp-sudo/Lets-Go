import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../constants.dart';

class OTPVerificationResetController {
  TextEditingController otpController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;
  int? expiryTimestamp;
  int secondsLeft = 0;
  Timer? expiryTimer;
  VoidCallback? onStateChanged;

  OTPVerificationResetController({this.onStateChanged});

  void dispose() {
    otpController.dispose();
    expiryTimer?.cancel();
  }

  void initExpiryFromArgs(Map<String, dynamic>? args) {
    if (args != null && args['expiry'] != null) {
      expiryTimestamp = args['expiry'];
      updateExpiryTimer();
    }
  }

  void updateExpiryTimer() {
    expiryTimer?.cancel();
    if (expiryTimestamp == null) return;
    secondsLeft =
        expiryTimestamp! - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (secondsLeft < 0) secondsLeft = 0;
    onStateChanged?.call();
    expiryTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      secondsLeft =
          expiryTimestamp! - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (secondsLeft <= 0) {
        secondsLeft = 0;
        timer.cancel();
      }
      onStateChanged?.call();
    });
  }

  Future<Map<String, dynamic>> verifyOtp(
    String method,
    String value,
    BuildContext context,
  ) async {
    isLoading = true;
    onStateChanged?.call();
    // OTP validation
    if (otpController.text.isEmpty) {
      errorMessage = 'Please enter the OTP.';
      onStateChanged?.call();
      return {'success': false};
    }
    if (!RegExp(r'^\d{6}?$').hasMatch(otpController.text)) {
      errorMessage = 'OTP must be 6 digits.';
      onStateChanged?.call();
      return {'success': false};
    }
    final urlEndpoint = Uri.parse('$url/lets_go/verify_password_reset_otp/');
    final response = await http.post(
      urlEndpoint,
      body: {
        'method': method,
        'value': value,
        'otp': otpController.text.trim(),
      },
    );
    isLoading = false;
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['expiry'] != null) {
        expiryTimestamp = data['expiry'];
        updateExpiryTimer();
      }
      onStateChanged?.call();
      if (context.mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/reset_password',
          arguments: {'method': method, 'value': value},
        );
      }
      return data;
    } else {
      errorMessage = 'Invalid OTP.';
      onStateChanged?.call();
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> resendOtp(String method, String value) async {
    isLoading = true;
    onStateChanged?.call();
    final urlEndpoint = Uri.parse('$url/lets_go/send_otp/');
    final response = await http.post(
      urlEndpoint,
      body: {
        'email': method == 'email' ? value : '',
        'phone_no': method == 'phone' ? value : '',
        'resend': method, // 'email' or 'phone'
        'otp_for': 'reset_password',
      },
    );
    isLoading = false;
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['email_expiry'] != null || data['phone_expiry'] != null) {
        errorMessage = 'OTP resent.';
        expiryTimestamp = data['email_expiry'] ?? data['phone_expiry'];
        updateExpiryTimer();
      }
      onStateChanged?.call();
      return data;
    } else {
      errorMessage = 'Failed to resend OTP.';
      onStateChanged?.call();
      return {'success': false};
    }
  }
}
