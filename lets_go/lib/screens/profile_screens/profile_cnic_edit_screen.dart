import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

class ProfileCnicEditScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> initialUser;

  const ProfileCnicEditScreen({
    super.key,
    required this.userId,
    required this.initialUser,
  });

  @override
  State<ProfileCnicEditScreen> createState() => _ProfileCnicEditScreenState();
}

class _ProfileCnicEditScreenState extends State<ProfileCnicEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cnicNo = TextEditingController();

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
    _cnicNo.text = (widget.initialUser['cnic_no'] ?? widget.initialUser['cnic'] ?? '').toString();
  }

  @override
  void dispose() {
    _cnicNo.dispose();
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

    final existingFront = _existingUrl('cnic_front_image');
    final existingBack = _existingUrl('cnic_back_image');
    final hasFront = _front != null || (existingFront != null && existingFront.trim().isNotEmpty);
    final hasBack = _back != null || (existingBack != null && existingBack.trim().isNotEmpty);
    if (!hasFront || !hasBack) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload both CNIC front and back images.')),
      );
      return;
    }

    final cnicTrim = _cnicNo.text.trim();
    final initialCnic = (widget.initialUser['cnic_no'] ?? widget.initialUser['cnic'] ?? '').toString().trim();
    final effectiveCnic = cnicTrim.isNotEmpty ? cnicTrim : initialCnic;
    final isUploadingAnyImage = _front != null || _back != null;

    // Backend can accept image-only updates, but model validation requires a CNIC if saving/validating.
    if (isUploadingAnyImage && effectiveCnic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your CNIC number.')),
      );
      return;
    }

    final cnicChanged = cnicTrim.isNotEmpty && cnicTrim != initialCnic;
    if (_front == null && _back == null && !cnicChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to update.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await ApiService.uploadUserCnic(
        widget.userId,
        cnicNo: cnicChanged ? cnicTrim : null,
        front: _front,
        back: _back,
      );

      if (res['success'] != true) {
        if (res['code'] == 'CHANGE_REQUEST_PENDING') {
          throw Exception(
            (res['error'] ?? 'You already have a pending verification request. Please wait for admin review.').toString(),
          );
        }
        final base = (res['error'] ?? 'Failed to update CNIC').toString();
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
    final existingFront = _existingUrl('cnic_front_image');
    final existingBack = _existingUrl('cnic_back_image');

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Edit CNIC',
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
              const Text('CNIC Number', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _cnicNo,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '36603-0269853-9',
                ),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(15),
                ],
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null;
                  if (!RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(s)) {
                    return 'CNIC must be in the format 36603-0269853-9';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text('CNIC Images', style: TextStyle(fontWeight: FontWeight.w600)),
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
