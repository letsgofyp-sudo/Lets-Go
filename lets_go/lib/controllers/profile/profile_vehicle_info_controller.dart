import '../../services/api_service.dart';
import '../../constants.dart';

typedef OnStateChanged = void Function();
typedef OnError = void Function(String message);

class ProfileVehicleInfoController {
  final Map<String, dynamic> initialUser;
  final OnStateChanged? onStateChanged;
  final OnError? onError;

  Map<String, dynamic>? _freshUser;

  // Screen state
  bool isDriver = false;
  bool isLoading = true;
  List<Map<String, dynamic>> vehicles = [];
  String? errorMessage;

  final Map<int, Map<String, dynamic>> detailsCache = {};
  final Set<int> loadingVehicleIds = {};

  ProfileVehicleInfoController({
    required this.initialUser,
    this.onStateChanged,
    this.onError,
  });

  // --- User helpers ---
  Future<void> hydrateUser() async {
    try {
      final id = initialUser['id'];
      if (id == null) return;
      final fresh = await ApiService.getUserProfile(int.parse(id.toString()));
      _freshUser = fresh;
      onStateChanged?.call();
    } catch (_) {
      // swallow errors for UI resilience
    }
  }

  String? userImg(String key) {
    final raw = (_freshUser?[key] ?? initialUser[key])?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    // fallback to guessed URL if field missing
    final id = initialUser['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return '$url/lets_go/user_image/$id/$key/';
  }

  List<Map<String, String>> getLicenseImages() {
    final front = userImg('driving_license_front');
    final back = userImg('driving_license_back');
    final items = <Map<String, String>>[];
    if (front != null && front.isNotEmpty) items.add({'label': 'License Front', 'url': front});
    if (back != null && back.isNotEmpty) items.add({'label': 'License Back', 'url': back});
    return items;
  }

  bool get hasLicenseImages {
    final front = userImg('driving_license_front');
    final back = userImg('driving_license_back');
    return (front != null && front.isNotEmpty) && (back != null && back.isNotEmpty);
  }

  bool get hasLicense {
    String? dl = (initialUser['driving_license_no'] ?? _freshUser?['driving_license_no'])?.toString();
    dl ??= (initialUser['driving_license_number'] ?? _freshUser?['driving_license_number'])?.toString();
    dl ??= (initialUser['license_no'] ?? _freshUser?['license_no'])?.toString();
    dl ??= (initialUser['driving_license'] ?? _freshUser?['driving_license'])?.toString();
    return dl != null && dl.isNotEmpty;
  }

  String licenseNumber() {
    String? dl = (initialUser['driving_license_no'] ?? _freshUser?['driving_license_no'])?.toString();
    dl ??= (initialUser['driving_license_number'] ?? _freshUser?['driving_license_number'])?.toString();
    dl ??= (initialUser['license_no'] ?? _freshUser?['license_no'])?.toString();
    dl ??= (initialUser['driving_license'] ?? _freshUser?['driving_license'])?.toString();
    return dl ?? 'Not provided';
  }

  // --- Driver/Vehicle logic ---
  void computeDriverByLicenseOnly() {
    final hasLicense = (initialUser['driving_license_no']?.toString().isNotEmpty ?? false) ||
        (initialUser['driving_license_number']?.toString().isNotEmpty ?? false) ||
        (initialUser['license_no']?.toString().isNotEmpty ?? false) ||
        (initialUser['driving_license']?.toString().isNotEmpty ?? false);
    isDriver = hasLicense;
    onStateChanged?.call();
  }

  Future<void> loadVehicles() async {
    try {
      isLoading = true;
      errorMessage = null;
      onStateChanged?.call();

      final uid = initialUser['id'];
      final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
      if (userId == null) {
        errorMessage = 'User ID not found';
        return;
      }
      final list = await ApiService.getUserVehicles(userId);
      vehicles = list;
      final hasLicense = (initialUser['driving_license_no']?.toString().isNotEmpty ?? false) ||
          (initialUser['driving_license_number']?.toString().isNotEmpty ?? false) ||
          (initialUser['license_no']?.toString().isNotEmpty ?? false) ||
          (initialUser['driving_license']?.toString().isNotEmpty ?? false);
      isDriver = hasLicense && vehicles.isNotEmpty;
    } catch (e) {
      errorMessage = 'Failed to load vehicles: $e';
      onError?.call(errorMessage!);
    } finally {
      isLoading = false;
      onStateChanged?.call();
    }
  }

  Future<void> ensureVehicleDetails(int vehicleId) async {
    if (detailsCache.containsKey(vehicleId) || loadingVehicleIds.contains(vehicleId)) return;
    loadingVehicleIds.add(vehicleId);
    onStateChanged?.call();
    try {
      final details = await ApiService.getVehicleDetails(vehicleId);
      detailsCache[vehicleId] = details;
    } catch (e) {
      onError?.call('Failed to load vehicle details: $e');
    } finally {
      loadingVehicleIds.remove(vehicleId);
      onStateChanged?.call();
    }
  }
}
