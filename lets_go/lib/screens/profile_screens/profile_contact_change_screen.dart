import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../controllers/profile/profile_contact_change_controller.dart';

class ProfileContactChangeScreen extends StatefulWidget {
  final int userId;
  final ContactChangeWhich which;
  final String? currentValue;

  const ProfileContactChangeScreen({
    super.key,
    required this.userId,
    required this.which,
    this.currentValue,
  });

  @override
  State<ProfileContactChangeScreen> createState() => _ProfileContactChangeScreenState();
}

class _ProfileContactChangeScreenState extends State<ProfileContactChangeScreen> {
  late ProfileContactChangeController _controller;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _value;
  late TextEditingController _otp;

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

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(text: widget.currentValue ?? '');
    if (widget.which == ContactChangeWhich.phone) {
      _applyFullPhoneToUi(widget.currentValue ?? '');
    }
    _otp = TextEditingController(text: '');

    _controller = ProfileContactChangeController(
      userId: widget.userId,
      which: widget.which,
      onStateChanged: () {
        if (!mounted) return;
        setState(() {});
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
  }

  @override
  void dispose() {
    _value.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _title => widget.which == ContactChangeWhich.email ? 'Change Email' : 'Change Phone';
  String get _valueLabel => widget.which == ContactChangeWhich.email ? 'New Email' : 'New Phone';

  void _applyFullPhoneToUi(String full) {
    final phone = full.trim();
    if (phone.isEmpty) {
      _value.text = '';
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
        _value.text = phone.substring(best.length);
        return;
      }
    }

    _value.text = phone.replaceAll('+', '');
  }

  String _resolvedValueForApi() {
    final raw = _value.text.trim();
    if (widget.which == ContactChangeWhich.phone) {
      return _selectedCountryCode + raw;
    }
    return raw;
  }

  Future<void> _sendOtp({bool resend = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final res = await _controller.sendOtp(value: _resolvedValueForApi(), resend: resend);
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent')));
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_otp.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter OTP')));
      return;
    }
    final res = await _controller.verifyOtp(value: _resolvedValueForApi(), otp: _otp.text.trim());
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully')));
      Navigator.of(context).pop(_controller.updatedUser);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_valueLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _value,
                keyboardType: widget.which == ContactChangeWhich.phone ? TextInputType.phone : TextInputType.emailAddress,
                decoration: widget.which == ContactChangeWhich.phone
                    ? InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: '3001234567',
                        prefixIcon: DropdownButtonHideUnderline(
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
                              setState(() => _selectedCountryCode = val);
                            },
                          ),
                        ),
                      )
                    : const InputDecoration(border: OutlineInputBorder()),
                inputFormatters: widget.which == ContactChangeWhich.phone
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ]
                    : null,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  if (widget.which == ContactChangeWhich.email) {
                    if (!RegExp(r'^.+@.+\..+').hasMatch(s)) return 'Invalid email';
                    return null;
                  }
                  final full = _selectedCountryCode + s;
                  if (!RegExp(r'^\+\d{10,15}$').hasMatch(full)) {
                    return 'Phone must be in format +923001234567 (10-15 digits total).';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _controller.isSending ? null : () => _sendOtp(resend: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                      ),
                      child: _controller.isSending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Send OTP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _controller.isSending ? null : () => _sendOtp(resend: true),
                      child: const Text('Resend'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('OTP', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _controller.isVerifying ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _controller.isVerifying
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Verify & Update'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
