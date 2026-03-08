import 'package:flutter/material.dart';
import '../../controllers/signup_login_controllers/reset_password_controller.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late ResetPasswordController _controller;
  late String method;
  late String value;

  @override
  void initState() {
    super.initState();
    _controller = ResetPasswordController(onStateChanged: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    method = args?['method'] ?? 'email';
    value = args?['value'] ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _controller.passwordController,
              decoration: InputDecoration(
                labelText: 'New Password',
                suffixIcon: IconButton(
                  icon: Icon(_controller.obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: _controller.toggleObscurePassword,
                ),
              ),
              obscureText: _controller.obscurePassword,
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _controller.confirmPasswordController,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                suffixIcon: IconButton(
                  icon: Icon(_controller.obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: _controller.toggleObscureConfirmPassword,
                ),
              ),
              obscureText: _controller.obscureConfirmPassword,
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 24),
            _buildPasswordValidation(),
            if (_controller.errorMessage != null)
              Text(_controller.errorMessage!, style: TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _controller.isLoading
                  ? null
                  : () async {
                      await _controller.resetPassword(context, method, value);
                    },
              child: _controller.isLoading ? CircularProgressIndicator(color: Colors.white) : Text('Reset Password'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordValidation() {
    final password = _controller.passwordController.text;
    final confirm = _controller.confirmPasswordController.text;
    List<Widget> errors = [];
    if (password.isNotEmpty && password.length < 8) {
      errors.add(Text('Min 8 characters', style: TextStyle(color: Colors.red)));
    } else if (password.isNotEmpty && !RegExp(r'[A-Z]').hasMatch(password)) {
      errors.add(Text('Must have uppercase', style: TextStyle(color: Colors.red)));
    } else if (password.isNotEmpty && !RegExp(r'[a-z]').hasMatch(password)) {
      errors.add(Text('Must have lowercase', style: TextStyle(color: Colors.red)));
    } else if (password.isNotEmpty && !RegExp(r'\d').hasMatch(password)) {
      errors.add(Text('Must have digit', style: TextStyle(color: Colors.red)));
    } else if (password.isNotEmpty && !RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      errors.add(Text('Must have special char', style: TextStyle(color: Colors.red)));
    }
    if (confirm.isNotEmpty && confirm != password) {
      errors.add(Text('Passwords do not match.', style: TextStyle(color: Colors.red)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: errors,
    );
  }
} 