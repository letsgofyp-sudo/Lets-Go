import '../../services/api_service.dart';

typedef OnStateChanged = void Function();
typedef OnError = void Function(String message);

class ProfileMainController {
  Map<String, dynamic> user; // working copy for header and tabs
  final OnStateChanged? onStateChanged;
  final OnError? onError;

  bool isDriver = false;

  ProfileMainController({
    required this.user,
    this.onStateChanged,
    this.onError,
  }) {
    _computeIsDriver();
  }

  void _computeIsDriver() {
    String? dl = user['driving_license_no']?.toString();
    dl ??= user['driving_license_number']?.toString();
    dl ??= user['license_no']?.toString();
    dl ??= user['driving_license']?.toString();
    isDriver = (dl != null && dl.isNotEmpty);
  }

  Future<void> ensureLicenseIfMissing() async {
    String? dl = user['driving_license_no']?.toString();
    dl ??= user['driving_license_number']?.toString();
    dl ??= user['license_no']?.toString();
    dl ??= user['driving_license']?.toString();
    final idVal = user['id'];
    if ((dl == null || dl.isEmpty) && idVal != null) {
      try {
        final fresh = await ApiService.getUserProfile(int.parse(idVal.toString()));
        bool changed = false;
        for (final k in ['driving_license_no','driving_license_number','license_no','driving_license']) {
          if ((fresh[k] ?? '').toString().isNotEmpty && (user[k] ?? '').toString().isEmpty) {
            user[k] = fresh[k];
            changed = true;
          }
        }
        if (changed) {
          _computeIsDriver();
        }
      } catch (e) {
        onError?.call(e.toString());
      }
    }
  }
}
