import '../../services/api_service.dart';

typedef OnStateChanged = void Function();
typedef OnError = void Function(String message);

enum VehicleFormMode { create, edit }

class VehicleFormController {
  final VehicleFormMode mode;
  final int userId;
  final int? vehicleId;
  final OnStateChanged? onStateChanged;
  final OnError? onError;

  bool isSaving = false;
  Map<String, dynamic>? lastResult;

  VehicleFormController({
    required this.mode,
    required this.userId,
    this.vehicleId,
    this.onStateChanged,
    this.onError,
  });

  String _formatFields(dynamic fields) {
    if (fields is Map) {
      final parts = <String>[];
      fields.forEach((k, v) {
        final key = k?.toString() ?? '';
        if (key.isEmpty) return;
        if (v is List) {
          final msg = v.map((e) => e?.toString()).where((s) => s != null && s.trim().isNotEmpty).join(', ');
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

  Future<Map<String, dynamic>> submit(Map<String, dynamic> payload) async {
    isSaving = true;
    onStateChanged?.call();
    try {
      Map<String, dynamic> res;
      if (mode == VehicleFormMode.create) {
        res = await ApiService.createUserVehicle(userId, payload);
      } else {
        final id = vehicleId;
        if (id == null) throw Exception('Vehicle ID not found');
        res = await ApiService.updateVehicle(id, payload);
      }
      lastResult = res;
      if (res['success'] == false) {
        final base = res['error']?.toString() ?? 'Request failed';
        final fieldsMsg = _formatFields(res['fields']);
        onError?.call(fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base);
      }
      return res;
    } catch (e) {
      onError?.call(e.toString());
      return {'success': false, 'error': e.toString()};
    } finally {
      isSaving = false;
      onStateChanged?.call();
    }
  }

  Future<Map<String, dynamic>> deleteVehicle(int id) async {
    isSaving = true;
    onStateChanged?.call();
    try {
      final res = await ApiService.deleteVehicle(id);
      lastResult = res;
      if (res['success'] == false) {
        final msg = res['error']?.toString() ?? 'Failed to delete vehicle';
        onError?.call(msg);
      }
      return res;
    } catch (e) {
      onError?.call(e.toString());
      return {'success': false, 'error': e.toString()};
    } finally {
      isSaving = false;
      onStateChanged?.call();
    }
  }
}
