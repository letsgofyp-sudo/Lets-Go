import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../constants.dart';
import '../../utils/pk_bank_list.dart';

class SignupPersonalScreen extends StatefulWidget {
  const SignupPersonalScreen({super.key});

  @override
  State<SignupPersonalScreen> createState() => _SignupPersonalScreenState();
}

class _SignupPersonalScreenState extends State<SignupPersonalScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, String> _fields = {};
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _drivingLicenseController = TextEditingController();
  final TextEditingController _accountNoController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  String? _selectedBank;
  bool _isUsernameVerified = false;
  bool _isVerifyingUsername = false;
  String? _lastReservedUsername;
  String? _verifiedUsername;
  String _selectedCountryCode = '+92';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _usernameErrorMessage;
  String? _gender;

  // Add a comprehensive list of country codes
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

  static const String _lrm = '\u200E';

  String _normalizeUsername(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '')
        .trim();
    return cleaned;
  }

  String _usernameDisplayText(String input) {
    final cleaned = _normalizeUsername(input);
    if (cleaned.isEmpty) return '';
    return '$_lrm$cleaned';
  }

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
    debugPrint('[SignupPersonal] back pressed. canPop=${Navigator.of(context).canPop()} signup_step=$step');
    await prefs.setString('signup_step', 'personal');
    if (!mounted) return false;
    Navigator.pushReplacementNamed(context, '/login');
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _addressController.dispose();
    _cnicController.dispose();
    _phoneController.dispose();
    _drivingLicenseController.dispose();
    _accountNoController.dispose();
    _bankNameController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('signup_locked') == true) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/otp_verification');
      return;
    }

    _lastReservedUsername = prefs.getString('signup_last_reserved_username');
    _verifiedUsername = prefs.getString('signup_verified_username');
    final wasVerified = prefs.getBool('signup_username_verified') ?? false;

    final data = prefs.getString('signup_personal');
    if (data != null) {
      final map = Map<String, dynamic>.from(jsonDecode(data));
      setState(() {
        _fields.addAll(map.map((k, v) => MapEntry(k, v.toString())));
        _nameController.text = _fields['name'] ?? '';
        _usernameController.text = _usernameDisplayText(_fields['username'] ?? '');
        _emailController.text = _fields['email'] ?? '';
        _passwordController.text = _fields['password'] ?? '';
        _confirmPasswordController.text = _fields['confirm_password'] ?? '';
        _addressController.text = _fields['address'] ?? '';
        _cnicController.text = _fields['cnic_no'] ?? '';
        _applySavedPhoneToUi(_fields['phone_no'] ?? '');
        _drivingLicenseController.text = _fields['driving_license_no'] ?? '';
        _accountNoController.text = _fields['accountno'] ?? '';
        _bankNameController.text = _fields['bankname'] ?? '';
        _ibanController.text = _fields['iban'] ?? '';
        _gender = _fields['gender'];

        final existingBank = _bankNameController.text.trim();
        const legacyMap = <String, String>{
          'HBL': 'Habib Bank Limited (HBL)',
          'UBL': 'United Bank Limited (UBL)',
          'MCB': 'MCB Bank Limited',
          'Allied Bank': 'Allied Bank Limited',
          'Bank Alfalah': 'Bank Alfalah Limited',
          'Meezan Bank': 'Meezan Bank Limited',
          'Faysal Bank': 'Faysal Bank Limited',
          'Standard Chartered': 'Standard Chartered Bank (Pakistan) Limited',
          'NBP': 'National Bank of Pakistan (NBP)',
        };
        final normalizedExisting = legacyMap[existingBank] ?? existingBank;
        if (normalizedExisting.isNotEmpty && pkBankOptions.contains(normalizedExisting)) {
          _selectedBank = normalizedExisting;
          _bankNameController.text = normalizedExisting;
        } else if (normalizedExisting.isNotEmpty) {
          _selectedBank = 'Other';
        } else {
          _selectedBank = null;
        }

        final currentUsername = _normalizeUsername(_fields['username'] ?? '');
        if (wasVerified && _verifiedUsername != null && currentUsername == _verifiedUsername) {
          _isUsernameVerified = true;
          _lastReservedUsername ??= _verifiedUsername;
        } else {
          _isUsernameVerified = false;
        }
      });
    }
  }

  Future<void> _saveAndContinue() async {
    if (_formKey.currentState!.validate()) {
      _fields['username'] = _normalizeUsername(_usernameController.text);
      if (!_isUsernameVerified) {
        setState(() {
          _usernameErrorMessage = 'Please verify your username before continuing.';
        });
        return;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        setState(() => _errorMessage = 'Passwords do not match.');
        return;
      }
      _formKey.currentState!.save();
      setState(() => _isLoading = true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('signup_personal', jsonEncode(_fields));
      await prefs.setString('signup_step', 'emergency');
      setState(() => _isLoading = false);
      if (!mounted) return;
      Navigator.pushNamed(context, '/signup_emergency');
    }
  }

  Future<void> _verifyUsername() async {
    final username = _normalizeUsername(_usernameController.text);
    debugPrint('[SignupPersonal] _verifyUsername: username="$username" lastReserved="$_lastReservedUsername"');
    if (username.isEmpty) {
      setState(() {
        _usernameErrorMessage = 'Username is required before verification.';
      });
      return;
    }

    if (!RegExp(r'^(?=.*[A-Za-z])[A-Za-z0-9._]{3,32}$').hasMatch(username)) {
      setState(() {
        _usernameErrorMessage =
            "Username must be 3-32 chars, contain at least one letter, and only use letters, numbers, '.' or '_'.";
        _isUsernameVerified = false;
      });
      return;
    }

    setState(() {
      _isVerifyingUsername = true;
      _usernameErrorMessage = null;
    });

    try {
      final uri = Uri.parse('$url/lets_go/check_username/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': username,
          if (_lastReservedUsername != null && _lastReservedUsername!.isNotEmpty)
            'previous_username': _lastReservedUsername!,
        },
      );
      debugPrint('[SignupPersonal] _verifyUsername: POST body={username: $username, previous_username: $_lastReservedUsername}');

      if (!mounted) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[SignupPersonal] _verifyUsername: response=$data');
      final available = data['available'] == true;

      setState(() {
        _isUsernameVerified = available;
        _isVerifyingUsername = false;
        if (available) {
          _lastReservedUsername = username;
          _verifiedUsername = username;
        }
        if (!available) {
          _usernameErrorMessage = (data['error'] as String?) ?? 'Username already taken.';
        } else {
          _usernameErrorMessage = null;
        }
      });

      if (available) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('signup_username_verified', true);
        await prefs.setString('signup_verified_username', username);
        await prefs.setString('signup_last_reserved_username', username);
      }

      if (!mounted) return;

      if (available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username is available and verified.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifyingUsername = false;
        _isUsernameVerified = false;
        _usernameErrorMessage = 'Failed to verify username. Please try again.';
      });
    }
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
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Widget _buildGenderField() {
    return RadioGroup<String>(
      groupValue: _gender,
      onChanged: (val) {
        setState(() {
          _gender = val!;
          _fields['gender'] = val;
        });
      },
      child: Row(
        children: [
          Expanded(
            child: RadioListTile<String>(
              title: const Text('Male'),
              value: 'male',
            ),
          ),
          Expanded(
            child: RadioListTile<String>(
              title: const Text('Female'),
              value: 'female',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput(
    String label,
    String fieldName, {
    bool obscure = false,
    TextEditingController? controller,
    bool optional = false,
  }) {
    bool isPassword = fieldName == 'password';
    bool isConfirmPassword = fieldName == 'confirm_password';
    bool isCnic = fieldName == 'cnic_no';
    bool isPhone = fieldName == 'phone_no';
    bool isUsername = fieldName == 'username';
    bool isDrivingLicense = fieldName == 'driving_license_no';
    final effectiveController = controller ??
        (isUsername
            ? _usernameController
            : (isCnic
                ? _cnicController
                : (isPhone ? _phoneController : null)));
    Widget field = TextFormField(
      textDirection: fieldName == 'username' ? TextDirection.ltr : null,
      textAlign: fieldName == 'username' ? TextAlign.left : TextAlign.start,
      controller: effectiveController,
      initialValue: effectiveController == null ? (_fields[fieldName] ?? '') : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: isPhone
            ? DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCountryCode,
                  items: _countryCodes
                      .map((code) => DropdownMenuItem(
                            value: code,
                            child: Text(code),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedCountryCode = val!;
                    });
                  },
                ),
              )
            : null,
        suffixIcon: (isPassword || isConfirmPassword)
            ? IconButton(
                icon: Icon(
                  (isPassword ? _obscurePassword : _obscureConfirmPassword)
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    if (isPassword) {
                      _obscurePassword = !_obscurePassword;
                    } else {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    }
                  });
                },
              )
            : null,
      ),
      obscureText: (isPassword
          ? _obscurePassword
          : isConfirmPassword
              ? _obscureConfirmPassword
              : obscure),
      keyboardType: isPhone
          ? TextInputType.phone
          : isCnic
              ? TextInputType.number
              : isUsername
                  ? TextInputType.emailAddress
              : null,
      autocorrect: isUsername ? false : true,
      enableSuggestions: isUsername ? false : true,
      textCapitalization: isUsername ? TextCapitalization.none : TextCapitalization.sentences,
      inputFormatters: isCnic
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(15),
              TextInputFormatter.withFunction((oldValue, newValue) {
                String text = newValue.text.replaceAll('-', '');
                String formatted = '';
                for (int i = 0; i < text.length && i < 13; i++) {
                  formatted += text[i];
                  if (i == 4 || i == 11) formatted += '-';
                }
                return TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              })
            ]
          : isPhone
              ? [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ]
          : isDrivingLicense
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/]')),
                  LengthLimitingTextInputFormatter(20),
                ]
          : fieldName == 'accountno'
              ? [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(20),
                ]
          : fieldName == 'iban'
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                  LengthLimitingTextInputFormatter(34),
                ]
          : isUsername
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._]')),
                  LengthLimitingTextInputFormatter(32),
                  _UsernameLtrFormatter(_lrm),
                ]
              : null,
      validator: (value) {
        if (!optional && (value == null || value.isEmpty)) return 'Required';
        if (isUsername) {
          final normalized = _normalizeUsername(value ?? '');
          if (normalized.isEmpty) return 'Required';
          if (!RegExp(r'^(?=.*[A-Za-z])[A-Za-z0-9._]{3,32}$').hasMatch(normalized)) {
            return "Username must be 3-32 chars, contain at least one letter, and only use letters, numbers, '.' or '_'.";
          }
        }
        if (fieldName == 'email' && value != null) {
          final v = value.trim();
          final ok = RegExp(
            r'^[^@\s]+@([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.[A-Za-z]{2,24}$',
          ).hasMatch(v);
          if (!ok) return 'Enter a valid email with a valid domain';
        }
        if (isCnic && value != null && !RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(value)) {
          return 'Enter CNIC in format 36603-0269853-9';
        }
        if (isPhone && value != null) {
          // Backend expects full number in format +1234567890 (10-15 digits total after '+')
          final fullNumber = _selectedCountryCode + value.trim();
          if (!RegExp(r'^\+\d{10,15}$').hasMatch(fullNumber)) {
            return 'Phone must be in format +923001234567 (10-15 digits total).';
          }
        }
        if (fieldName == 'driving_license_no') {
          final raw = (value ?? '').trim();
          if (raw.isNotEmpty) {
            final normalized = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
            if (!RegExp(r'^[A-Z0-9][A-Z0-9\-/]{4,19}$').hasMatch(normalized)) {
              return "Driving license number must be 5-20 characters and contain only letters, digits, '-' or '/'.";
            }
          }
        }
        if (fieldName == 'accountno') {
          final raw = (value ?? '').trim().replaceAll(' ', '');
          if (raw.isNotEmpty && !RegExp(r'^\d{10,20}$').hasMatch(raw)) {
            return 'Account number must be 10-20 digits.';
          }
        }
        if (fieldName == 'iban') {
          final raw = (value ?? '').trim();
          if (raw.isNotEmpty) {
            final normalized = raw.toUpperCase().replaceAll(' ', '');
            if (!RegExp(r'^PK\d{2}[A-Z]{4}\d{16}$').hasMatch(normalized)) {
              return 'Enter IBAN like PK12ABCD1234567890123456';
            }
          }
        }
        if (isPassword && value != null) {
          if (value.length < 8) return 'Min 8 characters';
          if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Must have uppercase';
          if (!RegExp(r'[a-z]').hasMatch(value)) return 'Must have lowercase';
          if (!RegExp(r'\d').hasMatch(value)) return 'Must have digit';
          if (!RegExp(r'''[!@#\$%\^&*()_+\-=\[\]{};':"\\|,.<>\/?]''').hasMatch(value)) {
            return 'Must have special char';
          }
        }
        if (isConfirmPassword && value != _passwordController.text) {
          return 'Passwords do not match.';
        }
        return null;
      },
      onSaved: (value) {
        if (isPhone) {
          _fields[fieldName] = _selectedCountryCode + (value ?? '');
        } else if (isUsername) {
          _fields[fieldName] = _normalizeUsername(value ?? '');
        } else if (isDrivingLicense) {
          final raw = (value ?? '').trim();
          _fields[fieldName] = raw.isEmpty ? '' : raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
        } else if (fieldName == 'accountno') {
          _fields[fieldName] = (value ?? '').trim().replaceAll(' ', '');
        } else if (fieldName == 'iban') {
          _fields[fieldName] = (value ?? '').trim().toUpperCase().replaceAll(' ', '');
        } else {
          _fields[fieldName] = value ?? '';
        }
      },
      onChanged: (value) {
        if (isPhone) {
          _fields[fieldName] = _selectedCountryCode + value;
        } else if (isUsername) {
          _fields[fieldName] = _normalizeUsername(value);
        } else if (isDrivingLicense) {
          final raw = value.trim();
          _fields[fieldName] = raw.isEmpty ? '' : raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
        } else if (fieldName == 'accountno') {
          _fields[fieldName] = value.trim().replaceAll(' ', '');
        } else if (fieldName == 'iban') {
          _fields[fieldName] = value.trim().toUpperCase().replaceAll(' ', '');
        } else {
          _fields[fieldName] = value;
        }
        if (fieldName == 'username') {
          if (_usernameErrorMessage != null) {
            setState(() {
              _usernameErrorMessage = null;
            });
          }
          final normalized = _normalizeUsername(value);
          final matchesVerified =
              _verifiedUsername != null && normalized == _verifiedUsername;
          if (matchesVerified && !_isUsernameVerified) {
            setState(() {
              _isUsernameVerified = true;
            });
            SharedPreferences.getInstance().then((prefs) {
              prefs.setBool('signup_username_verified', true);
              prefs.setString('signup_verified_username', _verifiedUsername!);
            });
          } else if (!matchesVerified && _isUsernameVerified) {
            setState(() {
              _isUsernameVerified = false;
            });
            SharedPreferences.getInstance().then((prefs) {
              prefs.setBool('signup_username_verified', false);
            });
          }
        }
      },
    );

    if (fieldName == 'username') {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: field,
      );
    }

    return field;
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
              'Signup - Personal Info',
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
                _buildTextInput('Name', 'name', controller: _nameController),
                _buildTextInput('Username', 'username', controller: _usernameController),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _isVerifyingUsername ? null : _verifyUsername,
                    child: _isVerifyingUsername
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isUsernameVerified
                                ? 'Username Verified'
                                : 'Verify Username',
                          ),
                  ),
                ),
                if (_usernameErrorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _usernameErrorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                _buildTextInput('Email', 'email', controller: _emailController),
                _buildTextInput(
                  'Password',
                  'password',
                  obscure: true,
                  controller: _passwordController,
                ),
                _buildTextInput(
                  'Confirm Password',
                  'confirm_password',
                  obscure: true,
                  controller: _confirmPasswordController,
                ),
                _buildTextInput('Address', 'address', controller: _addressController),
                _buildTextInput('Phone No', 'phone_no', controller: _phoneController),
                _buildTextInput('CNIC No', 'cnic_no', controller: _cnicController),
                _buildGenderField(),
                _buildTextInput(
                  'Driving License No (optional)',
                  'driving_license_no',
                  controller: _drivingLicenseController,
                  optional: true,
                ),
                _buildTextInput(
                  'Account No (optional)',
                  'accountno',
                  controller: _accountNoController,
                  optional: true,
                ),
                _buildTextInput(
                  'IBAN (optional)',
                  'iban',
                  controller: _ibanController,
                  optional: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedBank,
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('--')),
                    ...pkBankOptions.map((b) => DropdownMenuItem<String>(value: b, child: Text(b))),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Bank Name (optional)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _selectedBank = v;
                      if (v != null && v != 'Other') {
                        _bankNameController.text = v;
                        _fields['bankname'] = v;
                      } else if (v == null) {
                        _bankNameController.text = '';
                        _fields['bankname'] = '';
                      }
                    });
                  },
                  validator: (v) {
                    final acc = _accountNoController.text.trim().replaceAll(' ', '');
                    final iban = _ibanController.text.trim().toUpperCase().replaceAll(' ', '');
                    final any = acc.isNotEmpty || iban.isNotEmpty;
                    if (!any) return null;
                    if (v == null || v.trim().isEmpty) {
                      return 'Bank name is required when providing bank details';
                    }
                    return null;
                  },
                  onSaved: (v) {
                    final selected = (v ?? '').trim();
                    if (selected.isNotEmpty && selected != 'Other') {
                      _fields['bankname'] = selected;
                    } else {
                      _fields['bankname'] = _bankNameController.text.trim();
                    }
                  },
                ),
                if ((_selectedBank ?? '') == 'Other') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _bankNameController,
                    decoration: const InputDecoration(
                      labelText: 'Bank (if Other)',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z .&\-]")),
                      LengthLimitingTextInputFormatter(120),
                    ],
                    validator: (value) {
                      final s = (value ?? '').trim();
                      final acc = _accountNoController.text.trim().replaceAll(' ', '');
                      final iban = _ibanController.text.trim().toUpperCase().replaceAll(' ', '');
                      final any = acc.isNotEmpty || iban.isNotEmpty;
                      if (!any) return null;
                      if (s.isEmpty) return 'Bank name is required when providing bank details';
                      final ok = RegExp(r'^[A-Za-z][A-Za-z .&\-]{1,118}[A-Za-z.]$').hasMatch(s);
                      if (!ok) return 'Enter a valid bank name';
                      return null;
                    },
                    onSaved: (value) {
                      if ((_selectedBank ?? '') == 'Other') {
                        _fields['bankname'] = (value ?? '').trim();
                      }
                    },
                    onChanged: (value) {
                      if ((_selectedBank ?? '') == 'Other') {
                        _fields['bankname'] = value;
                      }
                    },
                  ),
                ],
                const SizedBox(height: 20),
                if (_errorMessage != null)
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveAndContinue,
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

class _UsernameLtrFormatter extends TextInputFormatter {
  final String lrm;
  const _UsernameLtrFormatter(this.lrm);

  String _stripDirectionMarks(String input) {
    return input.replaceAll(RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '');
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final baseText = _stripDirectionMarks(newValue.text);
    if (baseText.isEmpty) {
      return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    }

    final nextText = '$lrm$baseText';

    int clamp(int v) => v.clamp(0, nextText.length);

    final selStart = newValue.selection.start;
    final selEnd = newValue.selection.end;

    final hasValidSelection = selStart >= 0 && selEnd >= 0;
    final nextSelection = hasValidSelection
        ? TextSelection(
            baseOffset: clamp(selStart + 1),
            extentOffset: clamp(selEnd + 1),
          )
        : TextSelection.collapsed(offset: nextText.length);

    return TextEditingValue(
      text: nextText,
      selection: nextSelection,
      composing: TextRange.empty,
    );
  }
}
