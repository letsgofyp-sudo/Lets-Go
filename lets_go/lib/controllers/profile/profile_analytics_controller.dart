import '../../services/api_service.dart';

typedef OnStateChanged = void Function();
typedef OnError = void Function(String message);

class ProfileAnalyticsController {
  final Map<String, dynamic> initialUser;
  final OnStateChanged? onStateChanged;
  final OnError? onError;

  bool isLoading = false;
  String? errorMessage;
  Map<String, dynamic> analytics = <String, dynamic>{};

  int? windowDays;

  void setWindowDays(int? days) {
    if (windowDays == days) return;
    windowDays = days;
    load();
  }

  ProfileAnalyticsController({
    required this.initialUser,
    this.onStateChanged,
    this.onError,
  });

  int _userId() {
    final raw = initialUser['id'] ?? initialUser['user_id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  bool get isDriver {
    String? dl = initialUser['driving_license_no']?.toString();
    dl ??= initialUser['driving_license_number']?.toString();
    dl ??= initialUser['license_no']?.toString();
    dl ??= initialUser['driving_license']?.toString();
    return dl != null && dl.isNotEmpty;
  }

  Future<void> load() async {
    final userId = _userId();
    if (userId <= 0) {
      isLoading = false;
      errorMessage = 'User ID not found';
      onStateChanged?.call();
      return;
    }

    isLoading = true;
    errorMessage = null;
    analytics = <String, dynamic>{};
    onStateChanged?.call();

    try {
      final backend = await ApiService.getUserAnalytics(userId: userId, windowDays: windowDays);
      if (backend['success'] == true) {
        final payload = backend['analytics'];
        if (payload is Map) {
          analytics = Map<String, dynamic>.from(payload);
          return;
        }
      }

      final msg = (backend['error'] ?? 'Analytics service unavailable').toString();
      errorMessage = msg;
      onError?.call(msg);
    } catch (e) {
      errorMessage = 'Failed to load analytics: $e';
      onError?.call(errorMessage!);
    } finally {
      isLoading = false;
      onStateChanged?.call();
    }
  }
}
