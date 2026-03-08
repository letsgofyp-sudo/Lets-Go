import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

typedef OnStateChanged = void Function();
typedef OnError = void Function(String message);

enum ContactChangeWhich { email, phone }

class ProfileContactChangeController {
  final int userId;
  final ContactChangeWhich which;
  final OnStateChanged? onStateChanged;
  final OnError? onError;

  bool isSending = false;
  bool isVerifying = false;

  int? expiry;
  Map<String, dynamic>? updatedUser;

  String _formatFields(dynamic fields) {
    if (fields is Map) {
      final parts = <String>[];
      fields.forEach((k, v) {
        final key = k?.toString() ?? '';
        if (key.trim().isEmpty) return;
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

  ProfileContactChangeController({
    required this.userId,
    required this.which,
    this.onStateChanged,
    this.onError,
  });

  String whichKey() => which == ContactChangeWhich.email ? 'email' : 'phone';

  Future<Map<String, dynamic>> sendOtp({required String value, bool resend = false}) async {
    isSending = true;
    onStateChanged?.call();
    try {
      final res = await ApiService.sendProfileContactChangeOtp(
        userId,
        which: whichKey(),
        value: value,
        resend: resend,
      );
      if (res['success'] == true) {
        final ex = res['expiry'];
        expiry = (ex is int) ? ex : int.tryParse(ex?.toString() ?? '');
      } else {
        final base = res['error']?.toString() ?? 'Failed to send OTP';
        final fieldsMsg = _formatFields(res['fields']);
        onError?.call(fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base);
      }
      return res;
    } catch (e) {
      onError?.call(e.toString());
      return {'success': false, 'error': e.toString()};
    } finally {
      isSending = false;
      onStateChanged?.call();
    }
  }

  Future<Map<String, dynamic>> verifyOtp({required String value, required String otp}) async {
    isVerifying = true;
    onStateChanged?.call();
    try {
      final res = await ApiService.verifyProfileContactChangeOtp(
        userId,
        which: whichKey(),
        value: value,
        otp: otp,
      );
      if (res['success'] == true) {
        final user = res['user'];
        if (user is Map<String, dynamic>) {
          updatedUser = user;
          await AuthSession.save(user);
        }
      } else {
        final base = res['error']?.toString() ?? 'Failed to verify OTP';
        final fieldsMsg = _formatFields(res['fields']);
        onError?.call(fieldsMsg.isNotEmpty ? '$base\n$fieldsMsg' : base);
      }
      return res;
    } catch (e) {
      onError?.call(e.toString());
      return {'success': false, 'error': e.toString()};
    } finally {
      isVerifying = false;
      onStateChanged?.call();
    }
  }
}
