import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

class ProfileDrivingLicenseEditScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> initialUser;

  const ProfileDrivingLicenseEditScreen({
    super.key,
    required this.userId,
    required this.initialUser,
  });

  @override
  State<ProfileDrivingLicenseEditScreen> createState() => _ProfileDrivingLicenseEditScreenState();
}

class _ProfileDrivingLicenseEditScreenState extends State<ProfileDrivingLicenseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _licenseNo = TextEditingController();

  static const int _maxDocumentImageSizeBytes = 1024 * 1024;

  File? _front;
  File? _back;

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
    _licenseNo.text = (widget.initialUser['driving_license_no'] ?? widget.initialUser['driving_license_number'] ?? '').toString();
  }

  @override
  void dispose() {
    _licenseNo.dispose();
    super.dispose();
  }

  String? _existingUrl(String key) {
    final raw = (widget.initialUser[key] ?? widget.initialUser['${key}_url'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  Future<void> _pick(String which) async {
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
      if (size > _maxDocumentImageSizeBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image too large. Max size is 1 MB.')),
        );
        return;
      }
      setState(() {
        if (which == 'front') _front = file;
        if (which == 'back') _back = file;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final licenseNoTrim = _licenseNo.text.trim();
    final initialLicenseNo = (widget.initialUser['driving_license_no'] ?? widget.initialUser['driving_license_number'] ?? '').toString().trim();
    final effectiveLicenseNo = licenseNoTrim.isNotEmpty ? licenseNoTrim : initialLicenseNo;

    final existingFront = _existingUrl('driving_license_front');
    final existingBack = _existingUrl('driving_license_back');
    final hasFront = _front != null || (existingFront != null && existingFront.trim().isNotEmpty);
    final hasBack = _back != null || (existingBack != null && existingBack.trim().isNotEmpty);

    final isUploadingAnyImage = _front != null || _back != null;
    if (isUploadingAnyImage && effectiveLicenseNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your driving license number.')),
      );
      return;
    }

    // Model invariant: if a license number exists, both images must exist.
    if (effectiveLicenseNo.isNotEmpty && (!hasFront || !hasBack)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload both driving license front and back images.')),
      );
      return;
    }

    final licenseChanged = licenseNoTrim.isNotEmpty && licenseNoTrim != initialLicenseNo;
    if (_front == null && _back == null && !licenseChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to update.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await ApiService.uploadUserDrivingLicense(
        widget.userId,
        licenseNo: licenseChanged ? licenseNoTrim : null,
        front: _front,
        back: _back,
      );

      if (res['success'] != true) {
        final base = (res['error'] ?? 'Failed to update driving license').toString();
        final fieldsMsg = _formatFields(res['fields']);
        throw Exception(fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base);
      }

      final updatedUser = res['user'];
      if (updatedUser is Map<String, dynamic>) {
        await AuthSession.save(updatedUser);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update request submitted'), backgroundColor: Color(0xFF4CAF50)),
      );
      Navigator.of(context).pop(updatedUser is Map<String, dynamic> ? updatedUser : null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _imageTile({
    required String label,
    required File? file,
    required String? existingUrl,
    required VoidCallback? onPick,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : (existingUrl != null
                      ? Image.network(
                          existingUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.image, color: Colors.grey, size: 40),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.image, color: Colors.grey, size: 40),
                        )),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.image, size: 18),
                label: Text(file != null ? 'Change' : 'Pick'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingFront = _existingUrl('driving_license_front');
    final existingBack = _existingUrl('driving_license_back');

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Edit Driving License',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
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
              const Text('License Number', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _licenseNo,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Enter license number'),
              ),
              const SizedBox(height: 16),
              const Text('License Images', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _imageTile(
                    label: 'Front',
                    file: _front,
                    existingUrl: existingFront,
                    onPick: _saving ? null : () => _pick('front'),
                  ),
                  const SizedBox(width: 12),
                  _imageTile(
                    label: 'Back',
                    file: _back,
                    existingUrl: existingBack,
                    onPick: _saving ? null : () => _pick('back'),
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
