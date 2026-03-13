import 'package:flutter/material.dart';
import '../../controllers/signup_login_controllers/otp_verification_reset_controller.dart';

class OTPVerificationResetScreen extends StatefulWidget {
  const OTPVerificationResetScreen({super.key});

  @override
  State<OTPVerificationResetScreen> createState() => _OTPVerificationResetScreenState();
}

class _OTPVerificationResetScreenState extends State<OTPVerificationResetScreen> {
  late OTPVerificationResetController _controller;
  late String method;
  late String value;

  @override
  void initState() {
    super.initState();
    _controller = OTPVerificationResetController(onStateChanged: () {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      method = args?['method'] ?? 'email';
      value = args?['value'] ?? '';
      _controller.initExpiryFromArgs(args);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Verify OTP',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Enter the OTP sent to your ${method == 'email' ? 'email' : 'phone'}'),
            SizedBox(height: 24),
            TextField(
              controller: _controller.otpController,
              decoration: InputDecoration(labelText: 'OTP'),
              keyboardType: TextInputType.number,
              maxLength: 6,
              onChanged: (value) {
                if (value.length == 6 && !RegExp(r'^\d{6}?$').hasMatch(value)) {
                  setState(() {
                    _controller.errorMessage = 'Enter 6-digit OTP';
                  });
                } else {
                  setState(() {
                    _controller.errorMessage = null;
                  });
                }
              },
              enabled: _controller.secondsLeft > 0,
            ),
            SizedBox(height: 16),
            if (_controller.secondsLeft > 0)
              Text('OTP expires in ${_controller.secondsLeft ~/ 60}:${(_controller.secondsLeft % 60).toString().padLeft(2, '0')}'),
            if (_controller.secondsLeft == 0)
              Text('OTP expired. Please request a new OTP.', style: TextStyle(color: Colors.red)),
            SizedBox(height: 16),
            if (_controller.errorMessage != null)
              Text(_controller.errorMessage!, style: TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _controller.isLoading || _controller.secondsLeft == 0
                  ? null
                  : () async {
                      await _controller.verifyOtp(method, value, context);
                    },
              child: _controller.isLoading ? CircularProgressIndicator(color: Colors.white) : Text('Verify OTP'),
            ),
            SizedBox(height: 12),
            TextButton(
              onPressed: _controller.isLoading || _controller.secondsLeft > 0
                  ? null
                  : () => _controller.resendOtp(method, value),
              child: Text('Resend OTP'),
            ),
          ],
        ),
      ),
    );
  }
} 