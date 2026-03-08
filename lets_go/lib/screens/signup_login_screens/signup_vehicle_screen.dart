import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../controllers/signup_login_controllers/signup_controller.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class SignupVehicleScreen extends StatefulWidget {
  const SignupVehicleScreen({super.key});

  @override
  State<SignupVehicleScreen> createState() => _SignupVehicleScreenState();
}

class _SignupVehicleScreenState extends State<SignupVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<Map<String, dynamic>> _vehicles = [];
  final List<Map<String, File?>> _vehicleImages = [];
  bool _isLoading = false;
  String? _errorMessage;
  final picker = ImagePicker();
  static const int _maxVehicleImageSizeBytes = 1024 * 1024;

  List<Map<String, String>> _serializeVehicleImagePaths() {
    return _vehicleImages
        .map(
          (imgs) => {
            'photo_front': imgs['photo_front']?.path ?? '',
            'photo_back': imgs['photo_back']?.path ?? '',
            'documents_image': imgs['documents_image']?.path ?? '',
          },
        )
        .toList();
  }

  Future<void> _restoreVehicleImagesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final imagesData = prefs.getString('signup_vehicle_images');
    if (imagesData == null) return;

    final List<dynamic> decoded = jsonDecode(imagesData);
    final restored = decoded
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    for (int i = 0; i < _vehicleImages.length && i < restored.length; i++) {
      final m = restored[i];
      final frontPath = (m['photo_front'] ?? '').toString();
      final backPath = (m['photo_back'] ?? '').toString();
      final docPath = (m['documents_image'] ?? '').toString();

      if (frontPath.isNotEmpty) {
        final f = File(frontPath);
        if (await f.exists()) _vehicleImages[i]['photo_front'] = f;
      }
      if (backPath.isNotEmpty) {
        final f = File(backPath);
        if (await f.exists()) _vehicleImages[i]['photo_back'] = f;
      }
      if (docPath.isNotEmpty) {
        final f = File(docPath);
        if (await f.exists()) _vehicleImages[i]['documents_image'] = f;
      }
    }
  }

  Future<bool> _handleBack() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return false;
    final step = prefs.getString('signup_step');
    debugPrint('[SignupVehicle] back pressed. canPop=${Navigator.of(context).canPop()} signup_step=$step');
    await prefs.setString('signup_step', 'cnic');
    if (!mounted) return false;
    debugPrint('[SignupVehicle] redirecting back to /signup_cnic');
    Navigator.pushReplacementNamed(context, '/signup_cnic');
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedVehicles();
  }

  Future<void> _loadSavedVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('signup_locked') == true) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/otp_verification');
      return;
    }
    final vehiclesData = prefs.getString('signup_vehicles');
    if (vehiclesData != null) {
      final list = List<Map<String, dynamic>>.from(jsonDecode(vehiclesData));
      setState(() {
        _vehicles.clear();
        _vehicles.addAll(list);

        _vehicleImages.clear();
        for (int i = 0; i < _vehicles.length; i++) {
          _vehicleImages.add({
            'photo_front': null,
            'photo_back': null,
            'documents_image': null,
          });
        }
      });
      await _restoreVehicleImagesFromPrefs();
      if (!mounted) return;
      setState(() {});
    }
    // Optionally, load images as well if you store their paths
  }

  void _addVehicle() {
    setState(() {
      _vehicles.add({
        'model_number': '',
        'variant': '',
        'company_name': '',
        'plate_number': '',
        'vehicle_type': 'TW', // default
        'color': '',
        'seats': '2',  // Initialize with 2 seats for Two Wheeler
        'engine_number': '',
        'chassis_number': '',
        'fuel_type': 'Petrol', // default
        'registration_date': '',
        'insurance_expiry': '',
      });
      _vehicleImages.add({
        'photo_front': null,
        'photo_back': null,
        'documents_image': null,
      });
    });
  }

  void _removeVehicle(int index) {
    setState(() {
      _vehicles.removeAt(index);
      _vehicleImages.removeAt(index);
    });
  }

  Future<void> _pickImage(int vehicleIndex, String key) async {
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final int sizeInBytes = await file.length();
      if (sizeInBytes > _maxVehicleImageSizeBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Selected image is too large. Please choose an image under '
                '${(_maxVehicleImageSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB.',
              ),
            ),
          );
        }
        return;
      }
      setState(() {
        _vehicleImages[vehicleIndex][key] = file;
      });
    }
  }

  bool _validateVehicles() {
    for (int i = 0; i < _vehicles.length; i++) {
      final v = _vehicles[i];
      final imgs = _vehicleImages[i];
      if (v['model_number'].isEmpty ||
          v['company_name'].isEmpty ||
          v['plate_number'].isEmpty ||
          v['vehicle_type'].isEmpty ||
          imgs['photo_front'] == null ||
          imgs['photo_back'] == null ||
          imgs['documents_image'] == null) {
        setState(() => _errorMessage = 'Please complete all required fields and images for each vehicle.');
        return false;
      }
      if (v['vehicle_type'] == 'FW' && (v['seats'] == null || v['seats'].toString().isEmpty)) {
        setState(() => _errorMessage = 'Please specify number of seats for four wheelers.');
        return false;
      }
    }
    return true;
  }

  Future<void> _saveAndContinue() async {
    if (_vehicles.isNotEmpty && !_validateVehicles()) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final personalData = prefs.getString('signup_personal');
    final cnicData = prefs.getString('signup_cnic');
    final emergencyData = prefs.getString('signup_emergency');
    Map<String, dynamic> allFields = {};
    Map<String, File?> allImages = {};
    if (personalData != null) {
      allFields.addAll(Map<String, dynamic>.from(jsonDecode(personalData)));
    }
    if (emergencyData != null) {
      final em = Map<String, dynamic>.from(jsonDecode(emergencyData));
      final name = (em['name'] ?? '').toString().trim();
      final relation = (em['relation'] ?? '').toString().trim();
      final email = (em['email'] ?? '').toString().trim();
      final phone = (em['phone_no'] ?? '').toString().trim();
      if (name.isNotEmpty) allFields['emergency_name'] = name;
      if (relation.isNotEmpty) allFields['emergency_relation'] = relation;
      if (email.isNotEmpty) allFields['emergency_email'] = email;
      if (phone.isNotEmpty) allFields['emergency_phone_no'] = phone;
    }
    if (cnicData != null) {
      final cnicMap = Map<String, dynamic>.from(jsonDecode(cnicData));
      cnicMap.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          allImages[k] = File(v);
          allFields[k] = v; // <-- Ensure CNIC image paths are included in pending_signup
        }
      });
    }
    // Prepare vehicles data
    if (_vehicles.isNotEmpty) {
      allFields['vehicles'] = jsonEncode(_vehicles);
      for (int i = 0; i < _vehicles.length; i++) {
        final v = _vehicles[i];
        final imgs = _vehicleImages[i];
        if (imgs['photo_front'] != null) {
          allImages['photo_front_${v['plate_number']}'] = imgs['photo_front'];
          allFields['photo_front_${v['plate_number']}'] = imgs['photo_front']!.path;
        }
        if (imgs['photo_back'] != null) {
          allImages['photo_back_${v['plate_number']}'] = imgs['photo_back'];
          allFields['photo_back_${v['plate_number']}'] = imgs['photo_back']!.path;
        }
        if (imgs['documents_image'] != null) {
          allImages['documents_image_${v['plate_number']}'] = imgs['documents_image'];
          allFields['documents_image_${v['plate_number']}'] = imgs['documents_image']!.path;
        }
      }
    }
    await prefs.setString('signup_vehicles', jsonEncode(_vehicles));
    await prefs.setString('signup_vehicle_images', jsonEncode(_serializeVehicleImagePaths()));
    await prefs.setString('signup_step', 'vehicle');
    // Call backend to request OTPs and get expiry times
    final result = await SignupController.signup(
      allFields.map((k, v) => MapEntry(k, v.toString())),
      allImages,
    );
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      await prefs.setString('pending_signup', jsonEncode(allFields));
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
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Widget _buildPlateField(Map<String, dynamic> v) {
    return TextFormField(
      initialValue: v['plate_number'],
      decoration: const InputDecoration(labelText: 'Plate Number (ABC-1234)'),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9-]')),
        LengthLimitingTextInputFormatter(10),
      ],
      validator: (value) {
        if (value == null || !RegExp(r'^[A-Z]{2,5}-\d{1,4}(-[A-Z])?$').hasMatch(value)) {
          return 'Enter a valid plate number (e.g. ABC-1234)';
        }
        return null;
      },
      onChanged: (val) => v['plate_number'] = val,
    );
  }
  Widget _buildSeatsField(Map<String, dynamic> v) {
    if (v['vehicle_type'] == 'TW') {
      v['seats'] = '2';  // Ensure TW always has 2 seats
      return TextFormField(
        initialValue: '2',
        enabled: false,
        decoration: const InputDecoration(
          labelText: 'Number of Seats',
          helperText: 'Two wheeler seats fixed to 2'
        ),
      );
    }
    
    return TextFormField(
      initialValue: v['seats'],
      decoration: const InputDecoration(labelText: 'Number of Seats'),
      keyboardType: TextInputType.number,
      validator: (value) {
        if (value == null || int.tryParse(value) == null || int.parse(value) < 1) {
          return 'Enter a valid number of seats';
        }
        return null;
      },
      onChanged: (val) => v['seats'] = val,
    );
  }
  Widget _buildDateField(Map<String, dynamic> v, String field, String label) {
    final controller = TextEditingController(text: v[field]);
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: Icon(Icons.calendar_today),
      ),
      readOnly: true,
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now().add(Duration(days: 3650)),
        );
        if (picked != null) {
          setState(() {
            v[field] = DateFormat('yyyy-MM-dd').format(picked);
            controller.text = v[field];
          });
        }
      },
    );
  }

  Widget _buildVehicleForm(int index) {
    final v = _vehicles[index];
    final imgs = _vehicleImages[index];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vehicle ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeVehicle(index),
                ),
              ],
            ),
            TextFormField(
              initialValue: v['model_number'],
              decoration: const InputDecoration(labelText: 'Model Number'),
              onChanged: (val) => v['model_number'] = val,
            ),
            TextFormField(
              initialValue: v['variant'],
              decoration: const InputDecoration(labelText: 'Variant (optional)'),
              onChanged: (val) => v['variant'] = val,
            ),
            TextFormField(
              initialValue: v['company_name'],
              decoration: const InputDecoration(labelText: 'Company Name'),
              onChanged: (val) => v['company_name'] = val,
            ),
            _buildPlateField(v),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Vehicle Type'),
              initialValue: v['vehicle_type'] ?? 'TW',
              items: const [
                DropdownMenuItem(value: 'TW', child: Text('Two Wheeler')),
                DropdownMenuItem(value: 'FW', child: Text('Four Wheeler')),
              ],
              onChanged: (value) => setState(() => v['vehicle_type'] = value ?? 'TW'),
            ),
            TextFormField(
              initialValue: v['color'],
              decoration: const InputDecoration(labelText: 'Color (optional)'),
              onChanged: (val) => v['color'] = val,
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(index, 'photo_front'),
                  icon: const Icon(Icons.image),
                  label: Text(imgs['photo_front'] == null ? 'Upload Front' : 'Change Front'),
                ),
                const SizedBox(width: 10),
                if (imgs['photo_front'] != null)
                  const Icon(Icons.check_circle, color: Colors.green),
                if (imgs['photo_front'] == null)
                  const Icon(Icons.error, color: Colors.red),
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(index, 'photo_back'),
                  icon: const Icon(Icons.image),
                  label: Text(imgs['photo_back'] == null ? 'Upload Back' : 'Change Back'),
                ),
                const SizedBox(width: 10),
                if (imgs['photo_back'] != null)
                  const Icon(Icons.check_circle, color: Colors.green),
                if (imgs['photo_back'] == null)
                  const Icon(Icons.error, color: Colors.red),
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(index, 'documents_image'),
                  icon: const Icon(Icons.image),
                  label: Text(imgs['documents_image'] == null ? 'Upload Documents' : 'Change Documents'),
                ),
                const SizedBox(width: 10),
                if (imgs['documents_image'] != null)
                  const Icon(Icons.check_circle, color: Colors.green),
                if (imgs['documents_image'] == null)
                  const Icon(Icons.error, color: Colors.red),
              ],
            ),
            _buildSeatsField(v),
            TextFormField(
              initialValue: v['engine_number'],
              decoration: const InputDecoration(labelText: 'Engine Number (optional)'),
              onChanged: (val) => v['engine_number'] = val,
            ),
            TextFormField(
              initialValue: v['chassis_number'],
              decoration: const InputDecoration(labelText: 'Chassis Number (optional)'),
              onChanged: (val) => v['chassis_number'] = val,
            ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Fuel Type'),
              initialValue: v['fuel_type'] ?? 'Petrol',
              items: const [
                DropdownMenuItem(value: 'Petrol', child: Text('Petrol')),
                DropdownMenuItem(value: 'Diesel', child: Text('Diesel')),
                DropdownMenuItem(value: 'CNG', child: Text('CNG')),
                DropdownMenuItem(value: 'Electric', child: Text('Electric')),
                DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid')),
              ],
              onChanged: (value) => setState(() => v['fuel_type'] = value ?? 'Petrol'),
            ),
            _buildDateField(v, 'registration_date', 'Registration Date (optional)'),
            _buildDateField(v, 'insurance_expiry', 'Insurance Expiry (optional)'),
          ],
        ),
      ),
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
          title: const Text('Signup - Vehicle Details'),
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
                ..._vehicles.asMap().entries.map((entry) => _buildVehicleForm(entry.key)),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _addVehicle,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Vehicle'),
                ),
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
