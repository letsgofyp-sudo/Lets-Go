import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class SignupEmergencyContactScreen extends StatefulWidget {
  const SignupEmergencyContactScreen({super.key});

  @override
  State<SignupEmergencyContactScreen> createState() => _SignupEmergencyContactScreenState();
}

class _SignupEmergencyContactScreenState extends State<SignupEmergencyContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, String> _fields = {};
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _selectedRelation;
  String _selectedCountryCode = '+92';

  static const List<String> _countryCodes = [
    '+1', '+7', '+20', '+27', '+30', '+31', '+32', '+33', '+34', '+36', '+39',
    '+40', '+41', '+43', '+44', '+45', '+46', '+47', '+48', '+49', '+51', '+52',
    '+53', '+54', '+55', '+56', '+57', '+58', '+60', '+61', '+62', '+63', '+64',
    '+65', '+66', '+81', '+82', '+84', '+86', '+90', '+91', '+92', '+93', '+94',
    '+95', '+98', '+211', '+212', '+213', '+216', '+218', '+220', '+221', '+222',
    '+223', '+224', '+225', '+226', '+227', '+228', '+229', '+230', '+231', '+232',
    '+233', '+234', '+235', '+236', '+237', '+238', '+239', '+240', '+241', '+242',
    '+243', '+244', '+245', '+246', '+247', '+248', '+249', '+250', '+251', '+252',
    '+253', '+254', '+255', '+256', '+257', '+258', '+260', '+261', '+262', '+263',
    '+264', '+265', '+266', '+267', '+268', '+269', '+290', '+291', '+297', '+298',
    '+299', '+350', '+351', '+352', '+353', '+354', '+355', '+356', '+357', '+358',
    '+359', '+370', '+371', '+372', '+373', '+374', '+375', '+376', '+377', '+378',
    '+379', '+380', '+381', '+382', '+383', '+385', '+386', '+387', '+389', '+420',
    '+421', '+423', '+500', '+501', '+502', '+503', '+504', '+505', '+506', '+507',
    '+508', '+509', '+590', '+591', '+592', '+593', '+594', '+595', '+596', '+597',
    '+598', '+599', '+670', '+672', '+673', '+674', '+675', '+676', '+677', '+678',
    '+679', '+680', '+681', '+682', '+683', '+685', '+686', '+687', '+688', '+689',
    '+690', '+691', '+692', '+850', '+852', '+853', '+855', '+856', '+870', '+871',
    '+872', '+873', '+874', '+878', '+880', '+881', '+882', '+883', '+886', '+888',
    '+960', '+961', '+962', '+963', '+964', '+965', '+966', '+967', '+968', '+970',
    '+971', '+972', '+973', '+974', '+975', '+976', '+977', '+992', '+993', '+994',
    '+995', '+996', '+998', '+1242', '+1246', '+1264', '+1268', '+1284', '+1340',
    '+1345', '+1441', '+1473', '+1649', '+1664', '+1670', '+1671', '+1684', '+1758',
    '+1767', '+1784', '+1787', '+1809', '+1868', '+1869', '+1876', '+1939'
  ];

  void _applySavedPhoneToUi(String full) {
    final phone = full.trim();
    if (phone.isEmpty) {
      _phoneController.text = '';
      return;
    }

    if (phone.startsWith('+')) {
      String? best;
      for (final code in _countryCodes) {
        if (phone.startsWith(code) && (best == null || code.length > best.length)) {
          best = code;
        }
      }
      if (best != null) {
        _selectedCountryCode = best;
        _phoneController.text = phone.substring(best.length);
        return;
      }
    }

    _phoneController.text = phone;
  }

  Future<bool> _handleBack() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return false;
    final step = prefs.getString('signup_step');
    debugPrint('[SignupEmergency] back pressed. canPop=${Navigator.of(context).canPop()} signup_step=$step');
    await prefs.setString('signup_step', 'personal');
    if (!mounted) return false;
    debugPrint('[SignupEmergency] redirecting back to /signup_personal');
    Navigator.pushReplacementNamed(context, '/signup_personal');
    return false;
  }

  static const List<String> _relations = [
    'Father',
    'Mother',
    'Brother',
    'Sister',
    'Husband',
    'Wife',
    'Son',
    'Daughter',
    'Uncle',
    'Aunty',
    'Friend',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('signup_locked') == true) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/otp_verification');
      return;
    }
    final data = prefs.getString('signup_emergency');
    if (data != null) {
      final map = Map<String, dynamic>.from(jsonDecode(data));
      setState(() {
        _fields.addAll(map.map((k, v) => MapEntry(k, v.toString())));
        _selectedRelation = _fields['relation'];
        _nameController.text = _fields['name'] ?? '';
        _emailController.text = _fields['email'] ?? '';
        _applySavedPhoneToUi(_fields['phone_no'] ?? '');
      });
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() => _errorMessage = null);
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phoneLocal = _phoneController.text.trim();
    final anyFilled = name.isNotEmpty || email.isNotEmpty || phoneLocal.isNotEmpty || ((_selectedRelation ?? '').trim().isNotEmpty);

    // Emergency contact is optional: if all are empty, skip validation and don't persist.
    if (!anyFilled) {
      _fields.remove('name');
      _fields.remove('email');
      _fields.remove('phone_no');
      _fields.remove('relation');
    } else {
      if (!_formKey.currentState!.validate()) return;
      _formKey.currentState!.save();
      if (_selectedRelation == null || _selectedRelation!.trim().isEmpty) {
        setState(() => _errorMessage = 'Please select relation.');
        return;
      }
      if (name.isEmpty || email.isEmpty || phoneLocal.isEmpty) {
        setState(() => _errorMessage = 'Please complete all emergency contact fields, or leave all empty to skip.');
        return;
      }
    }
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    if (anyFilled) {
      _fields['relation'] = _selectedRelation!;
    }
    await prefs.setString('signup_emergency', jsonEncode(_fields));
    await prefs.setString('signup_step', 'cnic');
    setState(() => _isLoading = false);
    if (!mounted) return;
    Navigator.pushNamed(context, '/signup_cnic');
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

  Widget _buildTextInput(
    String label,
    String fieldName, {
    TextInputType? keyboardType,
    TextEditingController? controller,
  }) {
    final isPhone = fieldName == 'phone_no';
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: isPhone
            ? DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCountryCode,
                  items: _countryCodes
                      .map(
                        (code) => DropdownMenuItem(
                          value: code,
                          child: Text(code),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selectedCountryCode = val;
                      _fields['phone_no'] = _selectedCountryCode + _phoneController.text.trim();
                    });
                  },
                ),
              )
            : null,
      ),
      keyboardType: keyboardType,
      inputFormatters: isPhone
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(15),
            ]
          : null,
      validator: (value) {
        final v = (value ?? '').trim();
        final name = _nameController.text.trim();
        final email = _emailController.text.trim();
        final phoneLocal = _phoneController.text.trim();
        final rel = (_selectedRelation ?? '').trim();
        final anyFilled = name.isNotEmpty || email.isNotEmpty || phoneLocal.isNotEmpty || rel.isNotEmpty;
        if (!anyFilled && v.isEmpty) return null;
        if (anyFilled && v.isEmpty) return 'Required';
        if (fieldName == 'name') {
          if (v.length < 3) return 'Name too short';
          if (!RegExp(r"^[a-zA-Z .'-]+$").hasMatch(v)) {
            return 'Only letters and basic punctuation allowed';
          }
        }
        if (fieldName == 'email' && !RegExp(r'^.+@.+\..+').hasMatch(v)) {
          return 'Enter a valid email';
        }
        if (isPhone) {
          final fullNumber = _selectedCountryCode + v;
          if (!RegExp(r'^\+\d{10,15}$').hasMatch(fullNumber)) {
            return 'Phone must be in format +923001234567 (10-15 digits total).';
          }
        }
        return null;
      },
      onSaved: (value) {
        if (isPhone) {
          final v = (value ?? '').trim();
          if (v.isEmpty) {
            _fields.remove(fieldName);
          } else {
            _fields[fieldName] = _selectedCountryCode + v;
          }
        } else {
          final v = (value ?? '').trim();
          if (v.isEmpty) {
            _fields.remove(fieldName);
          } else {
            _fields[fieldName] = v;
          }
        }
      },
      onChanged: (value) {
        if (isPhone) {
          final v = value.trim();
          if (v.isEmpty) {
            _fields.remove(fieldName);
          } else {
            _fields[fieldName] = _selectedCountryCode + v;
          }
        } else {
          final v = value.trim();
          if (v.isEmpty) {
            _fields.remove(fieldName);
          } else {
            _fields[fieldName] = v;
          }
        }
      },
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
              'Signup - Emergency Contact',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _handleBack();
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
                _buildTextInput(
                  'Emergency Contact Name',
                  'name',
                  controller: _nameController,
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Relation'),
                  initialValue: _selectedRelation,
                  items: _relations
                      .map((r) => DropdownMenuItem<String>(
                            value: r,
                            child: Text(r),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedRelation = val;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    return null;
                  },
                ),
                _buildTextInput(
                  'Emergency Contact Email',
                  'email',
                  keyboardType: TextInputType.emailAddress,
                  controller: _emailController,
                ),
                _buildTextInput(
                  'Emergency Contact Phone No',
                  'phone_no',
                  keyboardType: TextInputType.phone,
                  controller: _phoneController,
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
                  child: _isLoading
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
