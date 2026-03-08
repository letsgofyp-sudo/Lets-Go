import '../../services/api_service.dart';

typedef Void = void Function();

typedef OnStateChanged = void Function();
typedef OnError = void Function(String message);

class ProfileGeneralInfoController {
  final Map<String, dynamic> initialUser;
  final OnStateChanged? onStateChanged;
  final OnError? onError;

  Map<String, dynamic> _user; // working copy
  Map<String, dynamic>? _freshUser;
  bool _isEditing = false;
  Map<String, dynamic>? lastSaveResult;

  ProfileGeneralInfoController({
    required this.initialUser,
    this.onStateChanged,
    this.onError,
  }) : _user = Map<String, dynamic>.from(initialUser);

  Map<String, dynamic> get user => _user;
  bool get isEditing => _isEditing;

  void toggleEdit() {
    _isEditing = !_isEditing;
    onStateChanged?.call();
  }

  void setEditing(bool editing) {
    _isEditing = editing;
    onStateChanged?.call();
  }

  Future<void> hydrateProfile() async {
    try {
      final id = _user['id'];
      if (id == null) return;
      final fresh = await ApiService.getUserProfile(int.parse(id.toString()));
      _freshUser = fresh;
      // Merge some common display fields without overwriting user's local edits
      for (final k in ['profile_photo', 'live_photo', 'phone_no', 'phone_number', 'cnic_no', 'cnic']) {
        final freshVal = fresh[k];
        if (freshVal != null && (freshVal.toString().isNotEmpty)) {
          _user[k] = freshVal;
        }
      }
      // Also hydrate emergency_contact map so profile screen can render it
      if (fresh['emergency_contact'] is Map<String, dynamic>) {
        _user['emergency_contact'] = Map<String, dynamic>.from(fresh['emergency_contact'] as Map);
      }
      onStateChanged?.call();
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  String? imageUrl(String key) {
    final v = (_freshUser?[key] ?? _user[key])?.toString();
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  String resolveString(List<String> keys, {String fallback = 'Not provided'}) {
    for (final k in keys) {
      final v = (_freshUser?[k] ?? _user[k])?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    return fallback;
  }

  String resolvePhone() {
    final v = resolveString(['phone_no', 'phone_number'], fallback: 'No phone');
    return v;
  }

  String resolveCnic() {
    final v = resolveString(['cnic_no', 'cnic'], fallback: 'Not provided');
    return v;
  }

  String? profilePhotoUrl() => imageUrl('profile_photo');

  bool get isDriver {
    String? dl = (_freshUser?['driving_license_no'] ?? _user['driving_license_no'])?.toString();
    dl ??= (_freshUser?['driving_license_number'] ?? _user['driving_license_number'])?.toString();
    dl ??= (_freshUser?['license_no'] ?? _user['license_no'])?.toString();
    dl ??= (_freshUser?['driving_license'] ?? _user['driving_license'])?.toString();
    return dl != null && dl.isNotEmpty;
  }

  List<Map<String, String>> getCnicImages() {
    final front = imageUrl('cnic_front_image');
    final back = imageUrl('cnic_back_image');
    final items = <Map<String, String>>[];
    if (front != null) items.add({'label': 'CNIC Front', 'url': front});
    if (back != null) items.add({'label': 'CNIC Back', 'url': back});
    return items;
  }

  Future<void> saveChanges(Map<String, dynamic> updates) async {
    try {
      final id = _user['id'] ?? initialUser['id'];
      if (id == null) throw Exception('User ID not found');
      final result = await ApiService.updateUserProfileWithVerification(id.toString(), updates);
      lastSaveResult = result;

      final returnedUser = result['user'];
      if (returnedUser is Map<String, dynamic>) {
        _user = Map<String, dynamic>.from(returnedUser);
      } else {
        _user.addAll(updates);
      }
      _isEditing = false;
      onStateChanged?.call();
    } catch (e) {
      lastSaveResult = {'success': false, 'error': e.toString()};
      onError?.call(e.toString());
      onStateChanged?.call();
    }
  }
}
