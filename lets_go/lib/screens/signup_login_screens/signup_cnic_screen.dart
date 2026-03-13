import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../controllers/signup_login_controllers/signup_controller.dart';

class SignupCnicScreen extends StatefulWidget {
  const SignupCnicScreen({super.key});

  @override
  State<SignupCnicScreen> createState() => _SignupCnicScreenState();
}

class _SignupCnicScreenState extends State<SignupCnicScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, File?> _images = {
    'profile_photo': null,
    'live_photo': null,
    'cnic_front_image': null,
    'cnic_back_image': null,
    'driving_license_front': null,
    'driving_license_back': null,
    'accountqr': null, // Add accountqr
  };
  bool _hasLicense = false;
  bool _isLoading = false;
  String? _errorMessage;
  final picker = ImagePicker();
  static const int _maxProfileImageSizeBytes = 500 * 1024;
  static const int _maxDocumentImageSizeBytes = 1024 * 1024;

  Future<bool> _handleBack() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return false;
    final step = prefs.getString('signup_step');
    debugPrint('[SignupCNIC] back pressed. canPop=${Navigator.of(context).canPop()} signup_step=$step');
    await prefs.setString('signup_step', 'emergency');
    if (!mounted) return false;
    debugPrint('[SignupCNIC] redirecting back to /signup_emergency');
    Navigator.pushReplacementNamed(context, '/signup_emergency');
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadLicenseStatus();
    _loadSavedImages();
  }

  Future<void> _loadLicenseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final personalData = prefs.getString('signup_personal');
    if (personalData != null) {
      final data = jsonDecode(personalData);
      setState(() {
        _hasLicense =
            (data['driving_license_no'] != null &&
                data['driving_license_no'].toString().trim().isNotEmpty);
      });
    }
  }

  Future<void> _loadSavedImages() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('signup_locked') == true) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/otp_verification');
      return;
    }
    final data = prefs.getString('signup_cnic');
    if (data != null) {
      final map = Map<String, dynamic>.from(jsonDecode(data));
      setState(() {
        map.forEach((k, v) {
          if (v is String && v.isNotEmpty) _images[k] = File(v);
        });
      });
    }
  }

  Future<void> _pickImage(
    String key, {
    ImageSource source = ImageSource.gallery,
  }) async {
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 75,
    );
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final int sizeInBytes = await file.length();
      final int limit = (key == 'profile_photo' || key == 'live_photo')
          ? _maxProfileImageSizeBytes
          : _maxDocumentImageSizeBytes;
      if (sizeInBytes > limit) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected image is too large. Please choose an image under '
              '${(limit / (1024 * 1024)).toStringAsFixed(1)} MB.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _images[key] = file;
      });
    }
  }

  Future<void> _saveAndContinue() async {
    // Validate required images
    if (_images['profile_photo'] == null ||
        _images['live_photo'] == null ||
        _images['cnic_front_image'] == null ||
        _images['cnic_back_image'] == null ||
        (_hasLicense &&
            (_images['driving_license_front'] == null ||
                _images['driving_license_back'] == null))) {
      setState(() => _errorMessage = 'Please upload all required images.');
      return;
    }
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final Map<String, String> imagePaths = {
      'profile_photo': _images['profile_photo']?.path ?? '',
      'live_photo': _images['live_photo']?.path ?? '',
      'cnic_front_image': _images['cnic_front_image']?.path ?? '',
      'cnic_back_image': _images['cnic_back_image']?.path ?? '',
      'accountqr': _images['accountqr']?.path ?? '', // Save accountqr
    };
    if (_hasLicense) {
      imagePaths['driving_license_front'] =
          _images['driving_license_front']?.path ?? '';
      imagePaths['driving_license_back'] =
          _images['driving_license_back']?.path ?? '';
    }
    await prefs.setString('signup_cnic', jsonEncode(imagePaths));
    await prefs.setString('signup_step', 'cnic');
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (_hasLicense) {
      Navigator.pushNamed(context, '/signup_vehicle');
    } else {
      // No license: go to OTP screen, but do NOT register yet, just request OTPs
      final personalData = prefs.getString('signup_personal');
      final emergencyData = prefs.getString('signup_emergency');
      Map<String, dynamic> allFields = {};
      Map<String, File?> allImages = {};
      if (personalData != null) {
        allFields.addAll(Map<String, dynamic>.from(jsonDecode(personalData)));
      }
      if (emergencyData != null) {
        final em = Map<String, dynamic>.from(jsonDecode(emergencyData));
        if (em['name'] != null) allFields['emergency_name'] = em['name'].toString();
        if (em['relation'] != null) allFields['emergency_relation'] = em['relation'].toString();
        if (em['email'] != null) allFields['emergency_email'] = em['email'].toString();
        if (em['phone_no'] != null) allFields['emergency_phone_no'] = em['phone_no'].toString();
      }
      imagePaths.forEach((k, v) {
        if (v.isNotEmpty) allImages[k] = File(v);
      });
      // Request OTPs from backend (do not register yet)
      final result = await SignupController.signup(
        allFields.map((k, v) => MapEntry(k, v.toString())),
        allImages,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        await prefs.setString(
          'pending_signup',
          jsonEncode({...allFields, ...imagePaths}),
        );
        await prefs.setString('signup_step', 'otp');
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          '/otp_verification',
          arguments: {
            'email_expiry': result['email_expiry'],
            'phone_expiry': result['phone_expiry'],
          },
        );
      } else {
        setState(() => _errorMessage = result['message'] ?? 'Signup failed.');
      }
    }
  }

  Future<void> _cancelSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('signup_personal');
    await prefs.remove('signup_emergency');
    await prefs.remove('signup_cnic');
    await prefs.remove('signup_vehicles');
    await prefs.remove('signup_vehicle_images');
    await prefs.remove('signup_step');
    await prefs.remove('signup_locked');
    await prefs.remove('pending_signup');
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Widget _buildImagePicker(
    String label,
    String key, {
    bool required = true,
    bool useCamera = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed:
                  () => _pickImage(
                    key,
                    source:
                        useCamera ? ImageSource.camera : ImageSource.gallery,
                  ),
              icon: Icon(useCamera ? Icons.camera_alt : Icons.image),
              label: Text(_images[key] == null ? 'Upload' : 'Change'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            if (_images[key] != null)
              const Icon(Icons.check_circle, color: Colors.green),
            if (required && _images[key] == null)
              const Icon(Icons.error, color: Colors.red),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack().then((allowPop) {
          if (allowPop && context.mounted) {
            Navigator.pop(context);
          }
        });
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Signup - CNIC & Photos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final allowPop = await _handleBack();
              if (allowPop && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset('assets/images/app_logo.png', height: 100),
                ),
                const SizedBox(height: 16),
                _buildImagePicker('Profile Photo', 'profile_photo'),
                _buildImagePicker(
                  'Live Photo (Take a Selfie)',
                  'live_photo',
                  useCamera: true,
                ),
                _buildImagePicker('CNIC Front Image', 'cnic_front_image'),
                _buildImagePicker('CNIC Back Image', 'cnic_back_image'),
                _buildImagePicker(
                  'Account QR (Bank QR Code)',
                  'accountqr',
                  required: false,
                ), // Add accountqr picker
                if (_hasLicense) ...[
                  _buildImagePicker(
                    'Driving License Front',
                    'driving_license_front',
                  ),
                  _buildImagePicker(
                    'Driving License Back',
                    'driving_license_back',
                  ),
                ],
                const SizedBox(height: 20),
                if (_errorMessage != null)
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child:
                      _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save & Continue'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _cancelSignup,
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
