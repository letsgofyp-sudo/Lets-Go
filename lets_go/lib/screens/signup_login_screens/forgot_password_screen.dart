import 'package:flutter/material.dart';
import '../../controllers/signup_login_controllers/forgot_password_controller.dart';
import 'package:flutter/services.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late ForgotPasswordController _controller;
  String _selectedCountryCode = '+92';
  String? _inputError;

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

  @override
  void initState() {
    super.initState();
    _controller = ForgotPasswordController(onStateChanged: () {
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
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Forgot Password',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Select method to receive OTP:'),
            RadioGroup<String>(
              groupValue: _controller.method,
              onChanged: (v) {
                setState(() {
                  _controller.method = v!;
                  _inputError = null;
                });
              },
              child: Row(
                children: [
                  const Radio<String>(value: 'email'),
                  const Text('Email'),
                  const Radio<String>(value: 'phone'),
                  const Text('Phone'),
                ],
              ),
            ),
            if (_controller.method == 'phone')
              Row(
                children: [
                  DropdownButton<String>(
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
                  Expanded(
                    child: TextField(
                      controller: _controller.valueController,
                      decoration: InputDecoration(
                        labelText: 'Phone',
                        errorText: _inputError,
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]')), LengthLimitingTextInputFormatter(15)],
                    ),
                  ),
                ],
              )
            else
              TextField(
                controller: _controller.valueController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: _inputError,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            SizedBox(height: 24),
            if (_controller.errorMessage != null)
              Text(_controller.errorMessage!, style: TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _controller.isLoading
                  ? null
                  : () {
                      final value = _controller.valueController.text.trim();
                      if (_controller.method == 'email') {
                        final ok = RegExp(
                          r'^[^@\s]+@([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.[A-Za-z]{2,24}$',
                        ).hasMatch(value);
                        if (value.isEmpty || !ok) {
                          setState(() => _inputError = 'Enter a valid email with a valid domain');
                          return;
                        }
                      } else {
                        final full = (_selectedCountryCode + value).trim();
                        if (value.isEmpty || !RegExp(r'^\+\d{10,15}$').hasMatch(full)) {
                          setState(() => _inputError = 'Phone must be in format +923001234567 (10-15 digits total).');
                          return;
                        }
                      }
                      setState(() => _inputError = null);

                      final original = _controller.valueController.text;
                      if (_controller.method == 'phone') {
                        _controller.valueController.text = _selectedCountryCode + value;
                      }
                      _controller.sendOtp(context);
                      _controller.valueController.text = original;
                    },
              child: _controller.isLoading ? CircularProgressIndicator(color: Colors.white) : Text('Send OTP'),
            ),
          ],
        ),
      ),
    );
  }
} 