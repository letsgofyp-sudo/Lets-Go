import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../constants.dart';

class ResetPasswordController {
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool isLoading = false;
  String? errorMessage;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  VoidCallback? onStateChanged;

  ResetPasswordController({this.onStateChanged});

  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
  }

  void toggleObscurePassword() {
    obscurePassword = !obscurePassword;
    onStateChanged?.call();
  }

  void toggleObscureConfirmPassword() {
    obscureConfirmPassword = !obscureConfirmPassword;
    onStateChanged?.call();
  }

  Future<void> resetPassword(
    BuildContext context,
    String method,
    String value,
  ) async {
    if (passwordController.text != confirmPasswordController.text) {
      errorMessage = 'Passwords do not match.';
      onStateChanged?.call();
      return;
    }
    isLoading = true;
    onStateChanged?.call();
    final urlEndpoint = Uri.parse('$url/lets_go/reset_password/');
    final response = await http.post(
      urlEndpoint,
      body: {
        'method': method,
        'value': value,
        'new_password': passwordController.text.trim(),
      },
    );
    isLoading = false;
    if (response.statusCode == 200) {
      onStateChanged?.call();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } else {
      errorMessage = 'Failed to reset password.';
      onStateChanged?.call();
    }
  }
}
