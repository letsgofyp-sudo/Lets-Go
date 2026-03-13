import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class ProfileChangePasswordScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProfileChangePasswordScreen({
    super.key,
    required this.userData,
  });

  @override
  State<ProfileChangePasswordScreen> createState() => _ProfileChangePasswordScreenState();
}

class _ProfileChangePasswordScreenState extends State<ProfileChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

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

  int? get _userId {
    final v = widget.userData['id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateRequired(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  String? _validateNew(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Required';
    if (s.length < 8) return 'Must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(s)) return 'Must have uppercase';
    if (!RegExp(r'[a-z]').hasMatch(s)) return 'Must have lowercase';
    if (!RegExp(r'\d').hasMatch(s)) return 'Must have digit';
    if (!RegExp(r'''[!@#\$%\^&*()_+\-=\[\]{};':"\\|,.<>\/?]''').hasMatch(s)) {
      return 'Must have special char';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Required';
    if (s != _newCtrl.text.trim()) return 'Does not match new password';
    return null;
  }

  Future<void> _submit() async {
    final userId = _userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User ID not found')));
      return;
    }

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() {
      _saving = true;
    });

    final res = await ApiService.changePassword(
      userId: userId,
      currentPassword: _currentCtrl.text,
      newPassword: _newCtrl.text,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
    });

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed')));
      Navigator.of(context).pop(true);
      return;
    }

    final base = (res['error'] ?? 'Failed to change password').toString();
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
            'Change Password',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _currentCtrl,
                obscureText: !_showCurrent,
                validator: _validateRequired,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showCurrent = !_showCurrent),
                    icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCtrl,
                obscureText: !_showNew,
                validator: _validateNew,
                decoration: InputDecoration(
                  labelText: 'New password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showNew = !_showNew),
                    icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                validator: _validateConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showConfirm = !_showConfirm),
                    icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_reset, color: Colors.white),
                  label: const Text('Update Password'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
