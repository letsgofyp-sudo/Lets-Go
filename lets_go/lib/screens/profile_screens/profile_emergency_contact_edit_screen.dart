import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

class ProfileEmergencyContactEditScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? initialEmergencyContact;

  const ProfileEmergencyContactEditScreen({
    super.key,
    required this.userId,
    this.initialEmergencyContact,
  });

  @override
  State<ProfileEmergencyContactEditScreen> createState() => _ProfileEmergencyContactEditScreenState();
}

class _ProfileEmergencyContactEditScreenState extends State<ProfileEmergencyContactEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phoneNo = TextEditingController();

  bool _loading = false;

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

  String _formatFields(dynamic fields) {
    if (fields is Map) {
      final parts = <String>[];
      fields.forEach((k, v) {
        final key = k?.toString() ?? '';
        if (key.trim().isEmpty) return;
        if (v is List) {
          final msg = v
              .map((e) => e?.toString())
              .where((s) => s != null && s.trim().isNotEmpty)
              .join(', ');
          if (msg.trim().isNotEmpty) parts.add('$key: $msg');
        } else {
          final msg = v?.toString() ?? '';
          if (msg.trim().isNotEmpty) parts.add('$key: $msg');
        }
      });
      return parts.join('\n');
    }
    return '';
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

  void _applyFullPhoneToUi(String full) {
    final phone = full.trim();
    if (phone.isEmpty) {
      _phoneNo.text = '';
      return;
    }

    // Emergency phone is stored as digits-only (no '+'), including country code digits.
    // Accept legacy values with '+' and normalize both.
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      _phoneNo.text = '';
      return;
    }

    String? bestDigits;
    String? bestCode;
    for (final code in _countryCodes) {
      final ccDigits = code.replaceAll(RegExp(r'\D'), '');
      if (ccDigits.isEmpty) continue;
      if (digits.startsWith(ccDigits) && (bestDigits == null || ccDigits.length > bestDigits.length)) {
        bestDigits = ccDigits;
        bestCode = code;
      }
    }

    if (bestDigits != null && bestCode != null) {
      _selectedCountryCode = bestCode;
      _phoneNo.text = digits.substring(bestDigits.length);
      return;
    }

    _phoneNo.text = digits;
  }

  @override
  void initState() {
    super.initState();
    _applyInitial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromApi();
    });
  }

  void _applyInitial() {
    final ec = widget.initialEmergencyContact;
    if (ec == null) return;
    _name.text = (ec['name'] ?? '').toString();
    _selectedRelation = (ec['relation'] ?? '').toString().trim().isEmpty
        ? null
        : (ec['relation'] ?? '').toString();
    _email.text = (ec['email'] ?? '').toString();
    _applyFullPhoneToUi((ec['phone_no'] ?? '').toString());
  }

  Future<void> _loadFromApi() async {
    try {
      final res = await ApiService.getEmergencyContact(widget.userId);
      if (!mounted) return;
      if (res['success'] == true && res['emergency_contact'] is Map) {
        final ec = Map<String, dynamic>.from(res['emergency_contact'] as Map);
        setState(() {
          _name.text = (ec['name'] ?? '').toString();
          _selectedRelation = (ec['relation'] ?? '').toString().trim().isEmpty
              ? null
              : (ec['relation'] ?? '').toString();
          _email.text = (ec['email'] ?? '').toString();
          _applyFullPhoneToUi((ec['phone_no'] ?? '').toString());
        });
      }
    } catch (_) {
      // ignore (screen remains editable)
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phoneNo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRelation == null || _selectedRelation!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select relation.')));
      return;
    }
    setState(() => _loading = true);

    final digitsPhone = _phoneNo.text.trim();
    final ccDigits = _selectedCountryCode.replaceAll(RegExp(r'\D'), '');
    final fullPhoneDigits = (ccDigits + digitsPhone).replaceAll(RegExp(r'\D'), '');

    final res = await ApiService.updateEmergencyContact(
      widget.userId,
      name: _name.text.trim(),
      relation: _selectedRelation!.trim(),
      email: _email.text.trim(),
      phoneNo: fullPhoneDigits,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      final updatedUser = res['user'];
      if (updatedUser is Map<String, dynamic>) {
        await AuthSession.save(updatedUser);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency contact updated'), backgroundColor: Color(0xFF4CAF50)),
      );
      Navigator.of(context).pop(updatedUser is Map<String, dynamic> ? updatedUser : null);
      return;
    }

    final base = (res['error'] ?? 'Failed to update emergency contact').toString();
    final fieldsMsg = _formatFields(res['fields']);
    final msg = fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Edit Emergency Contact',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        backgroundColor: const Color(0xFF00897B),
        actions: [
          IconButton(
            onPressed: _loading ? null : _save,
            tooltip: 'Save',
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Name', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  if (s.length < 3) return 'Name too short';
                  if (!RegExp(r"^[a-zA-Z .'-]+$").hasMatch(s)) {
                    return 'Only letters and basic punctuation allowed';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text('Relation', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                initialValue: _selectedRelation,
                items: _relations
                    .map((r) => DropdownMenuItem<String>(value: r, child: Text(r)))
                    .toList(),
                onChanged: _loading ? null : (val) => setState(() => _selectedRelation = val),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              const Text('Email', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  final ok = RegExp(
                    r'^[^@\s]+@([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.[A-Za-z]{2,24}$',
                  ).hasMatch(s);
                  if (!ok) return 'Enter a valid email with a valid domain';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text('Phone', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneNo,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCountryCode,
                      items: _countryCodes
                          .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                          .toList(),
                      onChanged: _loading
                          ? null
                          : (val) {
                              if (val == null) return;
                              setState(() => _selectedCountryCode = val);
                            },
                    ),
                  ),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
                  final ccDigits = _selectedCountryCode.replaceAll(RegExp(r'\D'), '');
                  final fullDigits = (ccDigits + s).replaceAll(RegExp(r'\D'), '');
                  if (!RegExp(r'^\d{10,15}$').hasMatch(fullDigits)) {
                    return 'Phone must be 10-15 digits (no +).';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
