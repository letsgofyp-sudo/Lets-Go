import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

class ProfileBankInfoEditScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> initialUser;

  const ProfileBankInfoEditScreen({
    super.key,
    required this.userId,
    required this.initialUser,
  });

  @override
  State<ProfileBankInfoEditScreen> createState() => _ProfileBankInfoEditScreenState();
}

class _ProfileBankInfoEditScreenState extends State<ProfileBankInfoEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _accountNo = TextEditingController();
  final TextEditingController _bankName = TextEditingController();
  final TextEditingController _iban = TextEditingController();

  static const int _maxQrImageSizeBytes = 1024 * 1024;

  File? _pickedQr;
  bool _saving = false;

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
    _accountNo.text = (widget.initialUser['accountno'] ?? '').toString();
    _bankName.text = (widget.initialUser['bankname'] ?? '').toString();
    _iban.text = (widget.initialUser['iban'] ?? '').toString();
  }

  @override
  void dispose() {
    _accountNo.dispose();
    _bankName.dispose();
    _iban.dispose();
    super.dispose();
  }

  String? _currentQrUrl() {
    final v = (widget.initialUser['accountqr'] ?? widget.initialUser['accountqr_url'] ?? '').toString();
    return v.trim().isEmpty ? null : v.trim();
  }

  Future<void> _pickQr() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
      );
      if (x == null) return;

      final file = File(x.path);
      final size = await file.length();
      if (size > _maxQrImageSizeBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image too large. Max size is 1 MB.')),
        );
        return;
      }
      setState(() {
        _pickedQr = file;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final accTrim = _accountNo.text.trim();
    final ibanTrim = _iban.text.trim();
    final bankTrim = _bankName.text.trim();
    final initialAcc = (widget.initialUser['accountno'] ?? '').toString().trim();
    final initialIban = (widget.initialUser['iban'] ?? '').toString().trim();
    final initialBank = (widget.initialUser['bankname'] ?? '').toString().trim();

    final changedAcc = accTrim != initialAcc;
    final changedIban = ibanTrim != initialIban;
    final changedBank = bankTrim != initialBank;

    if (!changedAcc && !changedIban && !changedBank && _pickedQr == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to update.')));
      return;
    }

    setState(() => _saving = true);

    try {
      Map<String, dynamic>? updatedUser;

      final updates = <String, dynamic>{
        if (changedAcc && accTrim.isNotEmpty) 'accountno': accTrim,
        if (changedIban && ibanTrim.isNotEmpty) 'iban': ibanTrim,
        if (changedBank && bankTrim.isNotEmpty) 'bankname': bankTrim,
      };

      if (updates.isNotEmpty) {
        final profileRes = await ApiService.updateUserProfileWithVerification(
          widget.userId.toString(),
          updates,
        );

        if (profileRes['success'] == false) {
          final base = (profileRes['error'] ?? 'Failed to update bank info').toString();
          final fieldsMsg = _formatFields(profileRes['fields']);
          throw Exception(fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base);
        }

        if (profileRes['user'] is Map<String, dynamic>) {
          updatedUser = Map<String, dynamic>.from(profileRes['user'] as Map);
        }
      }

      if (_pickedQr != null) {
        final uploadRes = await ApiService.uploadUserAccountQr(
          widget.userId,
          file: _pickedQr!,
        );

        if (uploadRes['success'] != true) {
          throw Exception((uploadRes['error'] ?? 'Failed to upload QR').toString());
        }

        if (uploadRes['user'] is Map<String, dynamic>) {
          updatedUser = Map<String, dynamic>.from(uploadRes['user'] as Map);
        }
      }

      if (updatedUser != null) {
        await AuthSession.save(updatedUser);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bank info updated'), backgroundColor: Color(0xFF4CAF50)),
      );
      Navigator.of(context).pop(updatedUser);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingQr = _currentQrUrl();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Bank Info'),
        backgroundColor: const Color(0xFF00897B),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            tooltip: 'Save',
            icon: _saving
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
              const Text('Account Number', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _accountNo,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('IBAN (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _iban,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Bank Name', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _bankName,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Account QR', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: _pickedQr != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_pickedQr!, fit: BoxFit.cover),
                          )
                        : (existingQr != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  existingQr,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.qr_code, color: Colors.grey, size: 40),
                                ),
                              )
                            : const Icon(Icons.qr_code, color: Colors.grey, size: 40)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _pickQr,
                          icon: const Icon(Icons.image),
                          label: Text(_pickedQr != null ? 'Change Image' : 'Pick Image'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _pickedQr != null
                              ? 'New QR image selected'
                              : (existingQr != null ? 'Current QR on file' : 'No QR uploaded yet'),
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
