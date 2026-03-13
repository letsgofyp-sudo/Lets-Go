import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../controllers/profile/vehicle_form_controller.dart';
import '../../services/api_service.dart';

class VehicleFormScreen extends StatefulWidget {
  final int userId;
  final int? vehicleId;
  final Map<String, dynamic>? initialVehicle;

  const VehicleFormScreen({
    super.key,
    required this.userId,
    this.vehicleId,
    this.initialVehicle,
  });

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _formKey = GlobalKey<FormState>();

  static const int _maxVehicleImageSizeBytes = 1024 * 1024;

  late VehicleFormController _controller;

  late TextEditingController _companyName;
  late TextEditingController _modelNumber;
  late TextEditingController _variant;
  late TextEditingController _plateNumber;
  late TextEditingController _color;
  late TextEditingController _seats;
  late TextEditingController _engineNumber;
  late TextEditingController _chassisNumber;
  late TextEditingController _registrationDate;
  late TextEditingController _insuranceExpiry;

  File? _photoFront;
  File? _photoBack;
  File? _documentsImage;

  String _vehicleType = 'TW';
  String _fuelType = 'Petrol';

  bool get _isEdit => widget.vehicleId != null;

  String _safeText(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.trim().isEmpty) return '';
    if (s.trim().toLowerCase() == 'null') return '';
    return s;
  }

  @override
  void initState() {
    super.initState();

    final v = widget.initialVehicle ?? {};

    _companyName = TextEditingController(text: _safeText(v['company_name'] ?? v['make']));
    _modelNumber = TextEditingController(text: _safeText(v['model_number'] ?? v['model']));
    _variant = TextEditingController(text: _safeText(v['variant']));
    _plateNumber = TextEditingController(text: _safeText(v['plate_number'] ?? v['registration_no']));
    _color = TextEditingController(text: _safeText(v['color']));
    _seats = TextEditingController(text: _safeText(v['seats']));
    _engineNumber = TextEditingController(text: _safeText(v['engine_number']));
    _chassisNumber = TextEditingController(text: _safeText(v['chassis_number']));
    _registrationDate = TextEditingController(text: _safeText(v['registration_date']));
    _insuranceExpiry = TextEditingController(text: _safeText(v['insurance_expiry']));

    final vt = (v['vehicle_type'] ?? 'TW').toString();
    _vehicleType = (vt == 'FW' || vt == 'TW') ? vt : 'TW';

    final ft = (v['fuel_type'] ?? 'Petrol').toString();
    _fuelType = _normalizeFuelType(ft);

    // Enforce TW seats behavior like signup flow
    if (_vehicleType == 'TW') {
      _seats.text = '2';
    }

    _controller = VehicleFormController(
      mode: _isEdit ? VehicleFormMode.edit : VehicleFormMode.create,
      userId: widget.userId,
      vehicleId: widget.vehicleId,
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
    _companyName.dispose();
    _modelNumber.dispose();
    _variant.dispose();
    _plateNumber.dispose();
    _color.dispose();
    _seats.dispose();
    _engineNumber.dispose();
    _chassisNumber.dispose();
    _registrationDate.dispose();
    _insuranceExpiry.dispose();
    super.dispose();
  }

  String _normalizeFuelType(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return 'Petrol';
    if (v == 'petrol' || v == 'gasoline') return 'Petrol';
    if (v == 'diesel') return 'Diesel';
    if (v == 'cng' || v == 'compressed natural gas') return 'CNG';
    if (v == 'electric' || v == 'ev') return 'Electric';
    if (v == 'hybrid') return 'Hybrid';
    // Unknown values can cause backend model Choice validation errors.
    return 'Petrol';
  }

  String? _validatePlate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Required';
    if (!RegExp(r'^[A-Z]{2,5}-\d{1,4}(-[A-Z])?$').hasMatch(v)) {
      return 'Enter a valid plate number (e.g. ABC-1234)';
    }
    return null;
  }

  Future<void> _pickDate(TextEditingController controller) async {
    try {
      DateTime initial = DateTime.now();
      final current = controller.text.trim();
      if (current.isNotEmpty) {
        final parsed = DateTime.tryParse(current);
        if (parsed != null) initial = parsed;
      }
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1900),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
      );
      if (picked != null) {
        setState(() {
          controller.text = DateFormat('yyyy-MM-dd').format(picked);
        });
      }
    } catch (_) {
      // ignore
    }
  }

  int? _parseSeats(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.toLowerCase() == 'null') return null;
    return int.tryParse(t);
  }

  void _enforceSeatsForType() {
    if (_vehicleType == 'TW') {
      // Two wheeler seats are fixed.
      _seats.text = '2';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    _enforceSeatsForType();

    final plate = _plateNumber.text.trim().toUpperCase();
    if (plate.isEmpty) return;

    if (_plateNumber.text != plate) {
      _plateNumber.text = plate;
    }

    final payload = <String, dynamic>{
      'company_name': _companyName.text.trim(),
      'model_number': _modelNumber.text.trim(),
      'plate_number': plate,
      'vehicle_type': _vehicleType,
      'registration_date': _registrationDate.text.trim().isEmpty ? null : _registrationDate.text.trim(),
      'insurance_expiry': _insuranceExpiry.text.trim().isEmpty ? null : _insuranceExpiry.text.trim(),
    };

    final variant = _variant.text.trim();
    if (variant.isNotEmpty) payload['variant'] = variant;
    final color = _color.text.trim();
    if (color.isNotEmpty) payload['color'] = color;
    final engine = _engineNumber.text.trim();
    if (engine.isNotEmpty) payload['engine_number'] = engine;
    final chassis = _chassisNumber.text.trim();
    if (chassis.isNotEmpty) payload['chassis_number'] = chassis;

    final fuel = _fuelType.trim();
    if (fuel.isNotEmpty) payload['fuel_type'] = fuel;

    if (_vehicleType == 'FW') {
      payload['seats'] = _parseSeats(_seats.text);
    }

    // Upload images first and include URLs in the same payload.
    // If we submit vehicle changes first, backend may create a PENDING ChangeRequest and then
    // block a second PATCH for images (403 CHANGE_REQUEST_PENDING), causing images to never show.
    if (_photoFront != null || _photoBack != null || _documentsImage != null) {
      final uploadRes = await ApiService.uploadVehicleImages(
        widget.userId,
        plateNumber: plate,
        photoFront: _photoFront,
        photoBack: _photoBack,
        documentsImage: _documentsImage,
      );
      if (!mounted) return;
      if (uploadRes['success'] == true) {
        final frontUrl = (uploadRes['photo_front_url'] ?? '').toString().trim();
        final backUrl = (uploadRes['photo_back_url'] ?? '').toString().trim();
        final docsUrl = (uploadRes['documents_image_url'] ?? '').toString().trim();
        if (frontUrl.isNotEmpty) payload['photo_front_url'] = frontUrl;
        if (backUrl.isNotEmpty) payload['photo_back_url'] = backUrl;
        if (docsUrl.isNotEmpty) payload['documents_image_url'] = docsUrl;
      } else {
        final err = (uploadRes['error'] ?? 'Failed to upload vehicle images').toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }
    }

    final res = await _controller.submit(payload);
    if (!mounted) return;

    if (res['success'] == true) {
      final isCreate = !_isEdit;
      if (isCreate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle submitted for admin verification (PENDING).')),
        );
      } else {
        final pending = res['pending_updates'];
        if (pending is Map && pending.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Some changes are pending admin verification.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vehicle updated.')),
          );
        }
      }
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _pickImage(String which) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
      if (x == null) return;

      final file = File(x.path);
      final size = await file.length();
      if (size > _maxVehicleImageSizeBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image too large. Max size is 1 MB.')),
        );
        return;
      }
      setState(() {
        if (which == 'front') _photoFront = file;
        if (which == 'back') _photoBack = file;
        if (which == 'docs') _documentsImage = file;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  String? _resolveVehicleImageUrl(String key) {
    final v = widget.initialVehicle;
    if (v == null) return null;
    final raw = (v[key] ?? v['${key}_url'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    // Some APIs return *_url for the same image; try both common shapes
    final altRaw = (v['${key}_url'] ?? v['${key}Url'] ?? '').toString().trim();
    return altRaw.isEmpty ? null : altRaw;
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Edit Vehicle' : 'Add Vehicle';

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _controller.isSaving ? null : _submit,
            icon: const Icon(Icons.check),
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
              _fieldLabel('Company Name'),
              TextFormField(
                controller: _companyName,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              _fieldLabel('Model Number'),
              TextFormField(
                controller: _modelNumber,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              _fieldLabel('Variant'),
              TextFormField(
                controller: _variant,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              _fieldLabel('Plate Number (e.g. ABC-1234)'),
              TextFormField(
                controller: _plateNumber,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: _validatePlate,
              ),
              const SizedBox(height: 12),

              _fieldLabel('Vehicle Type'),
              DropdownButtonFormField<String>(
                initialValue: _vehicleType,
                items: const [
                  DropdownMenuItem(value: 'TW', child: Text('Two Wheeler (TW)')),
                  DropdownMenuItem(value: 'FW', child: Text('Four Wheeler (FW)')),
                ],
                onChanged: _controller.isSaving
                    ? null
                    : (v) {
                        final next = v ?? 'TW';
                        setState(() {
                          _vehicleType = next;
                          _enforceSeatsForType();
                        });
                      },
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              _fieldLabel('Color'),
              TextFormField(
                controller: _color,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              if (_vehicleType != 'TW') ...[
                _fieldLabel('Seats (only for FW)'),
                TextFormField(
                  controller: _seats,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Required';
                    final n = int.tryParse(s);
                    if (n == null || n < 1) return 'Enter a valid number of seats';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],

              _fieldLabel('Fuel Type'),
              DropdownButtonFormField<String>(
                initialValue: _fuelType,
                items: const [
                  DropdownMenuItem(value: 'Petrol', child: Text('Petrol')),
                  DropdownMenuItem(value: 'Diesel', child: Text('Diesel')),
                  DropdownMenuItem(value: 'CNG', child: Text('CNG')),
                  DropdownMenuItem(value: 'Electric', child: Text('Electric')),
                  DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid')),
                ],
                onChanged: _controller.isSaving ? null : (v) => setState(() => _fuelType = v ?? 'Petrol'),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              _fieldLabel('Engine Number'),
              TextFormField(
                controller: _engineNumber,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              _fieldLabel('Chassis Number'),
              TextFormField(
                controller: _chassisNumber,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              _fieldLabel('Registration Date (YYYY-MM-DD)'),
              TextFormField(
                controller: _registrationDate,
                readOnly: true,
                onTap: _controller.isSaving ? null : () => _pickDate(_registrationDate),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 12),

              _fieldLabel('Insurance Expiry (YYYY-MM-DD)'),
              TextFormField(
                controller: _insuranceExpiry,
                readOnly: true,
                onTap: _controller.isSaving ? null : () => _pickDate(_insuranceExpiry),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 12),

              _fieldLabel('Vehicle Images'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _imagePickerTile(
                    label: 'Front',
                    file: _photoFront,
                    existingUrl: _resolveVehicleImageUrl('photo_front'),
                    onPick: _controller.isSaving ? null : () => _pickImage('front'),
                  ),
                  const SizedBox(width: 12),
                  _imagePickerTile(
                    label: 'Back',
                    file: _photoBack,
                    existingUrl: _resolveVehicleImageUrl('photo_back'),
                    onPick: _controller.isSaving ? null : () => _pickImage('back'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _imagePickerTile(
                label: 'Documents',
                file: _documentsImage,
                existingUrl: _resolveVehicleImageUrl('documents_image'),
                onPick: _controller.isSaving ? null : () => _pickImage('docs'),
                fullWidth: true,
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _controller.isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _controller.isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isEdit ? 'Submit Changes' : 'Submit Vehicle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _imagePickerTile({
    required String label,
    required File? file,
    required String? existingUrl,
    required VoidCallback? onPick,
    bool fullWidth = false,
  }) {
    final tile = SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            width: fullWidth ? double.infinity : null,
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

    if (fullWidth) return tile;
    return Expanded(child: tile);
  }
}
