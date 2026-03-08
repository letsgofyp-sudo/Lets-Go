import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

class ProfilePhotosEditScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> initialUser;

  const ProfilePhotosEditScreen({
    super.key,
    required this.userId,
    required this.initialUser,
  });

  @override
  State<ProfilePhotosEditScreen> createState() => _ProfilePhotosEditScreenState();
}

class _ProfilePhotosEditScreenState extends State<ProfilePhotosEditScreen> {
  static const int _maxProfileImageSizeBytes = 500 * 1024;

  File? _profile;
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
      if (size > _maxProfileImageSizeBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image too large. Max size is 500 KB.')),
        );
        return;
      }

      setState(() {
        if (which == 'profile') _profile = file;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<void> _save() async {
    if (_profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a profile photo.')));
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await ApiService.uploadUserPhotos(
        widget.userId,
        profilePhoto: _profile,
      );

      if (res['success'] != true) {
        final base = (res['error'] ?? 'Failed to update photos').toString();
        final fieldsMsg = _formatFields(res['fields']);
        throw Exception(fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base);
      }

      final updatedUser = res['user'];
      if (updatedUser is Map<String, dynamic>) {
        await AuthSession.save(updatedUser);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photos updated'), backgroundColor: Color(0xFF4CAF50)),
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
    required String title,
    required File? picked,
    required String? existingUrl,
    required VoidCallback onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: picked != null
                ? Image.file(picked, fit: BoxFit.cover)
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _saving ? null : onPick,
            icon: const Icon(Icons.photo_library),
            label: Text(picked != null ? 'Change' : 'Pick'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final existingProfile = _existingUrl('profile_photo');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Photos'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Profile Photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _imageTile(
              title: 'Profile Photo',
              picked: _profile,
              existingUrl: existingProfile,
              onPick: () => _pick('profile'),
            ),
          ],
        ),
      ),
    );
  }
}
