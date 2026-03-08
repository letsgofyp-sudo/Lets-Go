import 'package:flutter/material.dart';
import '../../controllers/profile/profile_general_info_controller.dart';

class ProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const ProfileEditScreen({super.key, required this.userData});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late ProfileGeneralInfoController _controller;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _address;
  late String _gender; // male, female

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

  @override
  void initState() {
    super.initState();
    _controller = ProfileGeneralInfoController(
      initialUser: widget.userData,
      onStateChanged: () {
        if (!mounted) return;
        setState(() {});
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
    final name = widget.userData['name']?.toString() ?? '';
    final address = widget.userData['address']?.toString() ?? '';
    _name = TextEditingController(text: name);
    _address = TextEditingController(text: address);
    // Normalize gender from backend (could be lowercase)
    final rawGender = widget.userData['gender']?.toString() ?? 'Male';
    _gender = _normalizeGender(rawGender);
  }

  String _normalizeGender(String g) {
    final v = g.trim();
    if (v.isEmpty) return 'male';
    final low = v.toLowerCase();
    if (low.startsWith('m')) return 'male';
    if (low.startsWith('f')) return 'female';
    return 'male';
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final nameTrim = _name.text.trim();
    final addressTrim = _address.text.trim();
    final initialName = (widget.userData['name'] ?? '').toString().trim();
    final initialAddress = (widget.userData['address'] ?? '').toString().trim();
    final currentGender = _normalizeGender(widget.userData['gender']?.toString() ?? 'male');

    final changedName = nameTrim != initialName;
    final changedAddress = addressTrim != initialAddress;
    final changedGender = _gender != currentGender;

    if (!changedName && !changedAddress && !changedGender) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to update.')));
      return;
    }

    final updates = <String, dynamic>{
      if (changedName) 'name': nameTrim,
      if (changedAddress) 'address': addressTrim,
    };
    if (changedGender) {
      updates['gender'] = _gender;
    }
    await _controller.saveChanges(updates);
    if (!mounted) return;
    final res = _controller.lastSaveResult;

    if (res is Map<String, dynamic> && res['success'] == false) {
      final base = (res['error'] ?? 'Failed to update profile').toString();
      final fieldsMsg = _formatFields(res['fields']);
      final msg = fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    final pending = (res is Map<String, dynamic>) ? res['pending_updates'] : null;
    final hasPendingGender = pending is Map && pending.containsKey('gender');
    if (hasPendingGender) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gender change sent for admin verification.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated'), backgroundColor: Color(0xFF4CAF50)),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: const Color(0xFF00897B),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
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
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter your name'),
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
              const Text('Gender', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                ],
                onChanged: (val) => setState(() => _gender = val ?? 'male'),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Address', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter your address'),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Required';
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
