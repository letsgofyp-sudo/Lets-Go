import 'package:flutter/material.dart';
import '../../controllers/signup_login_controllers/otp_verification_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // Added for jsonDecode

class OTPVerificationScreen extends StatefulWidget {
  const OTPVerificationScreen({super.key});

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  late OTPVerificationController _controller;
  String? _previousEmail;
  String? _previousPhone;

  String? _routeForServerField(String? field) {
    final f = (field ?? '').trim();
    if (f.isEmpty) return null;

    const personalFields = {
      'name',
      'username',
      'email',
      'password',
      'confirm_password',
      'address',
      'phone_no',
      'cnic_no',
      'gender',
      'driving_license_no',
      'accountno',
      'bankname',
      'iban',
    };

    const cnicFields = {
      'profile_photo',
      'live_photo',
      'cnic_front_image',
      'cnic_back_image',
      'driving_license_front',
      'driving_license_back',
    };

    const emergencyFields = {
      'emergency_name',
      'emergency_relation',
      'emergency_email',
      'emergency_phone_no',
    };

    if (personalFields.contains(f)) return '/signup_personal';
    if (cnicFields.contains(f)) return '/signup_cnic';
    if (emergencyFields.contains(f)) return '/signup_emergency';
    if (f == 'vehicles' || f.startsWith('photo_front_') || f.startsWith('photo_back_') || f.startsWith('documents_image_')) {
      return '/signup_vehicle';
    }
    return '/signup_personal';
  }

  @override
  void initState() {
    super.initState();
    _lockSignup();
    _setSignupStep();
    _controller = OTPVerificationController(onStateChanged: () {
      if (mounted) setState(() {});
    });
    _controller.loadSignupData().then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('pending_signup');
      if (data != null) {
        final map = Map<String, dynamic>.from(jsonDecode(data));
        _previousEmail = map['email'];
        _previousPhone = map['phone_no'];
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _controller.initExpiryFromArgs(args);
    });
  }

  Future<void> _lockSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('signup_locked', true);
  }

  Future<void> _setSignupStep() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('signup_step', 'otp');
  }

  Future<void> _cancelSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('signup_personal');
    await prefs.remove('signup_emergency');
    await prefs.remove('signup_cnic');
    await prefs.remove('signup_vehicles');
    await prefs.remove('signup_vehicle_images');
    await prefs.remove('pending_signup_status');
    await prefs.remove('signup_username_verified');
    await prefs.remove('signup_verified_username');
    await prefs.remove('signup_last_reserved_username');
    await prefs.remove('signup_step');
    await prefs.remove('signup_locked');
    await prefs.remove('pending_signup');
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Future<void> _unlockSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('signup_locked', false);
  }

  Future<void> _handleBack() async {
    await _unlockSignup();
    final prefs = await SharedPreferences.getInstance();
    final step = prefs.getString('signup_step');
    if (!mounted) return;
    if (step == 'vehicle') {
      Navigator.pushReplacementNamed(context, '/signup_vehicle');
    } else if (step == 'cnic') {
      Navigator.pushReplacementNamed(context, '/signup_cnic');
    } else {
      Navigator.pushReplacementNamed(context, '/signup_personal');
    }
  }

  Future<void> _goBackAndFix() async {
    final target = _routeForServerField(_controller.lastServerErrorField);
    if (target == null) return;

    await _unlockSignup();
    final prefs = await SharedPreferences.getInstance();

    if (target == '/signup_vehicle') {
      await prefs.setString('signup_step', 'vehicle');
    } else if (target == '/signup_cnic') {
      await prefs.setString('signup_step', 'cnic');
    } else if (target == '/signup_emergency') {
      await prefs.setString('signup_step', 'emergency');
    } else {
      await prefs.setString('signup_step', 'personal');
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, target);
  }

  Future<void> _resignup() async {
    await _controller.loadSignupData();
    if (!mounted) return;
    await _controller.submitFinalRegistration(context);
  }

  Future<void> _checkAndResendOtpIfChanged() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('pending_signup');
    if (data != null) {
      final map = Map<String, dynamic>.from(jsonDecode(data));
      final currentEmail = map['email'];
      final currentPhone = map['phone_no'];
      if (_previousEmail != null && currentEmail != _previousEmail) {
        await _controller.resendOtp('email');
        _previousEmail = currentEmail;
      }
      if (_previousPhone != null && currentPhone != _previousPhone) {
        await _controller.resendOtp('phone');
        _previousPhone = currentPhone;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAndResendOtpIfChanged();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'OTP Verification',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: _controller.isSubmittingRegistration ? null : _handleBack,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: _controller.signupData == null
                ? Center(child: Text('No pending signup data found.'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Enter the OTPs sent to your email and mobile number.'),
                      SizedBox(height: 24),
                      if (_controller.isSubmittingRegistration) ...[
                        const Center(
                          child: SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Submitting your registration…',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _controller.emailOtpController,
                              enabled: !_controller.isSubmittingRegistration &&
                                  !_controller.emailVerified &&
                                  _controller.emailSecondsLeft > 0,
                              decoration: InputDecoration(
                                labelText: 'Email OTP',
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Required';
                                if (!RegExp(r'^\d{6}\$').hasMatch(value)) return 'Enter 6-digit OTP';
                                return null;
                              },
                            ),
                          ),
                          if (_controller.emailVerified)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text('Verified', style: TextStyle(color: Colors.green)),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _controller.isLoading ||
                                    _controller.isSubmittingRegistration ||
                                    _controller.emailVerified ||
                                    _controller.emailSecondsLeft == 0
                                ? null
                                : () async {
                                    if (!mounted) return;
                                    await _controller.verifyOtp(verifyEmail: true, verifyPhone: false, context: context);
                                    if ((_controller.emailVerified && _controller.phoneVerified)) {
                                      if (!mounted) return;
                                      // Navigation now handled in controller
                                    }
                                  },
                            child: Text('Verify Email OTP'),
                          ),
                          SizedBox(width: 8),
                          TextButton(
                            onPressed: _controller.isLoading ||
                                    _controller.isSubmittingRegistration ||
                                    _controller.emailVerified ||
                                    _controller.emailSecondsLeft > 0
                                ? null
                                : () => _controller.resendOtp('email'),
                            child: Text('Resend Email OTP'),
                          ),
                        ],
                      ),
                      if (_controller.emailSecondsLeft > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('Email OTP expires in ${_controller.emailSecondsLeft ~/ 60}:${(_controller.emailSecondsLeft % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      if (_controller.emailSecondsLeft == 0 && !_controller.emailVerified)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('Email OTP expired. Please request a new OTP.', style: TextStyle(color: Colors.red)),
                        ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _controller.mobileOtpController,
                              enabled: !_controller.isSubmittingRegistration &&
                                  !_controller.phoneVerified &&
                                  _controller.phoneSecondsLeft > 0,
                              decoration: InputDecoration(
                                labelText: 'Mobile OTP',
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Required';
                                if (!RegExp(r'^\d{6}\$').hasMatch(value)) return 'Enter 6-digit OTP';
                                return null;
                              },
                            ),
                          ),
                          if (_controller.phoneVerified)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text('Verified', style: TextStyle(color: Colors.green)),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _controller.isLoading ||
                                    _controller.isSubmittingRegistration ||
                                    _controller.phoneVerified ||
                                    _controller.phoneSecondsLeft == 0
                                ? null
                                : () async {
                                    if (!mounted) return;
                                    await _controller.verifyOtp(verifyEmail: false, verifyPhone: true, context: context);
                                    if ((_controller.emailVerified && _controller.phoneVerified)) {
                                      if (!mounted) return;
                                      // Navigation now handled in controller
                                    }
                                  },
                            child: Text('Verify Phone OTP'),
                          ),
                          SizedBox(width: 8),
                          TextButton(
                            onPressed: _controller.isLoading ||
                                    _controller.isSubmittingRegistration ||
                                    _controller.phoneVerified ||
                                    _controller.phoneSecondsLeft > 0
                                ? null
                                : () => _controller.resendOtp('phone'),
                            child: Text('Resend Phone OTP'),
                          ),
                        ],
                      ),
                      if (_controller.phoneSecondsLeft > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('Phone OTP expires in ${_controller.phoneSecondsLeft ~/ 60}:${(_controller.phoneSecondsLeft % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      if (_controller.phoneSecondsLeft == 0 && !_controller.phoneVerified)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text('Phone OTP expired. Please request a new OTP.', style: TextStyle(color: Colors.red)),
                        ),
                      if (!_controller.emailVerified || !_controller.phoneVerified)
                        SizedBox.shrink(),
                      if (_controller.emailSecondsLeft == 0 &&
                          (!_controller.emailVerified || !_controller.phoneVerified))
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('OTP expired. Please request a new OTP.', style: TextStyle(color: Colors.red)),
                        ),
                      SizedBox(height: 24),
                      if (_controller.errorMessage != null)
                        Text(_controller.errorMessage!, style: TextStyle(color: Colors.red)),
                      if ((_controller.errorMessage != null || _controller.needsResubmit) &&
                          !_controller.isSubmittingRegistration &&
                          _controller.emailVerified &&
                          _controller.phoneVerified) ...[
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _resignup,
                          child: const Text('Resignup'),
                        ),
                      ],
                      if (_controller.errorMessage != null &&
                          !_controller.isSubmittingRegistration &&
                          _routeForServerField(_controller.lastServerErrorField) != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _goBackAndFix,
                          child: const Text('Go Back & Fix'),
                        ),
                      ],
                      SizedBox.shrink(),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _controller.isSubmittingRegistration ? null : _cancelSignup,
                        child: const Text('Cancel Signup'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
} 