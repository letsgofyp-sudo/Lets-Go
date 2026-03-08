import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../../constants.dart';

class ForgotPasswordController {
  String method = 'email';
  TextEditingController valueController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;
  VoidCallback? onStateChanged;

  ForgotPasswordController({this.onStateChanged});

  void dispose() {
    valueController.dispose();
  }

  Future<void> sendOtp(BuildContext context) async {
    isLoading = true;
    onStateChanged?.call();
    final urlEndpoint = Uri.parse('$url/lets_go/send_otp/');
    final response = await http.post(
      urlEndpoint,
      body: {
        'email': method == 'email' ? valueController.text.trim() : '',
        'phone_no': method == 'phone' ? valueController.text.trim() : '',
        'resend': method, // 'email' or 'phone'
        'otp_for': 'reset_password',
      },
    );
    isLoading = false;
    if (response.statusCode == 200) {
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      onStateChanged?.call();
      if (context.mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/otp_verification_reset',
          arguments: {
            'method': method,
            'value': valueController.text.trim(),
            'expiry': data['email_expiry'] ?? data['phone_expiry'],
          },
        );
      }
    } else {
      errorMessage = 'Failed to send OTP.';
      onStateChanged?.call();
    }
  }
}
