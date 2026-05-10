// lib/screens/register_pending_screen.dart
import 'package:flutter/material.dart';
import 'login_screen.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../utils/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../support_chat_screen.dart';
import 'dart:async';

class RegisterPendingScreen extends StatefulWidget {
  const RegisterPendingScreen({super.key});

  @override
  State<RegisterPendingScreen> createState() => _RegisterPendingScreenState();
}

class _RegisterPendingScreenState extends State<RegisterPendingScreen> {
  Map<String, dynamic>? _userData;
  bool _loading = true;
  int _notificationUnreadCount = 0;
  Timer? _notificationTimer;
  bool _notificationPollingStarted = false;

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  Future<void> _loadUnreadCount({bool silent = false}) async {
    final userData = _userData;
    final uid = _toInt(userData?['id']);
    if (uid <= 0) return;
    try {
      final count = await ApiService.getNotificationUnreadCount(userId: uid);
      if (!mounted) return;
      if (silent && count == _notificationUnreadCount) return;
      setState(() => _notificationUnreadCount = count);
    } catch (_) {
      // ignore
    }
  }

  void _startUnreadPollingIfNeeded() {
    if (_notificationPollingStarted) return;
    _notificationPollingStarted = true;
    _loadUnreadCount();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _loadUnreadCount(silent: true),
    );
  }

  String? _existingUrlFromMap(Map<String, dynamic> map, String key) {
    final raw = (map[key] ?? map['${key}_url'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  Future<String?> _downloadUrlToTempFile(String url, String fileNameBase) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      final resp = await http.get(uri);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

      String ext = '.jpg';
      final path = uri.path;
      final dot = path.lastIndexOf('.');
      if (dot != -1 && dot < path.length - 1) {
        final maybeExt = path.substring(dot);
        if (maybeExt.length <= 5) {
          ext = maybeExt;
        }
      }

      final dir = await Directory.systemTemp.createTemp('letsgo_signup_');
      final file = File('${dir.path}/$fileNameBase$ext');
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _prefillSignupPrefsFromUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();

    final personal = <String, dynamic>{};
    void putPersonal(String key, dynamic value) {
      final v = (value ?? '').toString();
      if (v.isNotEmpty) personal[key] = v;
    }

    putPersonal('name', userData['name']);
    putPersonal('username', userData['username']);
    putPersonal('email', userData['email']);
    putPersonal('address', userData['address']);
    putPersonal('cnic_no', userData['cnic_no']);
    putPersonal('phone_no', userData['phone_no']);
    putPersonal('driving_license_no', userData['driving_license_no']);
    putPersonal('accountno', userData['accountno']);
    putPersonal('bankname', userData['bankname']);
    putPersonal('iban', userData['iban']);
    putPersonal('gender', userData['gender']);

    if (personal.isNotEmpty) {
      await prefs.setString('signup_personal', jsonEncode(personal));
    }

    final emergencyRaw = userData['emergency_contact'];
    if (emergencyRaw is Map) {
      final ec = Map<String, dynamic>.from(emergencyRaw);
      final emergency = <String, dynamic>{};
      void putEmergency(String key, dynamic value) {
        final v = (value ?? '').toString();
        if (v.isNotEmpty) emergency[key] = v;
      }

      putEmergency('name', ec['name']);
      putEmergency('relation', ec['relation']);
      putEmergency('email', ec['email']);
      final rawPhone = (ec['phone_no'] ?? '').toString();
      final digitsPhone = rawPhone.replaceAll(RegExp(r'\D'), '');
      if (digitsPhone.isNotEmpty) {
        emergency['phone_no'] = digitsPhone;
      }

      if (emergency.isNotEmpty) {
        await prefs.setString('signup_emergency', jsonEncode(emergency));
      }
    }

    final vehiclesRaw = userData['vehicles'];
    if (vehiclesRaw is List) {
      final allowedKeys = <String>{
        'model_number',
        'variant',
        'company_name',
        'plate_number',
        'vehicle_type',
        'color',
        'seats',
        'engine_number',
        'chassis_number',
        'fuel_type',
        'registration_date',
        'insurance_expiry',
      };
      final vehicles = <Map<String, dynamic>>[];
      for (final v in vehiclesRaw) {
        if (v is! Map) continue;
        final vm = Map<String, dynamic>.from(v);
        final out = <String, dynamic>{};
        for (final k in allowedKeys) {
          final val = (vm[k] ?? '').toString();
          out[k] = val;
        }
        vehicles.add(out);
      }
      if (vehicles.isNotEmpty) {
        await prefs.setString('signup_vehicles', jsonEncode(vehicles));
      }

      final vehicleImages = <Map<String, String>>[];
      for (int i = 0; i < vehiclesRaw.length; i++) {
        final item = vehiclesRaw[i];
        if (item is! Map) {
          vehicleImages.add({'photo_front': '', 'photo_back': '', 'documents_image': ''});
          continue;
        }
        final vm = Map<String, dynamic>.from(item);
        final frontUrl = _existingUrlFromMap(vm, 'photo_front');
        final backUrl = _existingUrlFromMap(vm, 'photo_back');
        final docUrl = _existingUrlFromMap(vm, 'documents_image');

        final frontPath = (frontUrl != null)
            ? await _downloadUrlToTempFile(frontUrl, 'vehicle_${i + 1}_front_${DateTime.now().millisecondsSinceEpoch}')
            : null;
        final backPath = (backUrl != null)
            ? await _downloadUrlToTempFile(backUrl, 'vehicle_${i + 1}_back_${DateTime.now().millisecondsSinceEpoch}')
            : null;
        final docPath = (docUrl != null)
            ? await _downloadUrlToTempFile(docUrl, 'vehicle_${i + 1}_doc_${DateTime.now().millisecondsSinceEpoch}')
            : null;

        vehicleImages.add({
          'photo_front': frontPath ?? '',
          'photo_back': backPath ?? '',
          'documents_image': docPath ?? '',
        });
      }

      if (vehicleImages.isNotEmpty) {
        await prefs.setString('signup_vehicle_images', jsonEncode(vehicleImages));
      }
    }

    final cnicKeys = <String>[
      'profile_photo',
      'live_photo',
      'cnic_front_image',
      'cnic_back_image',
      'driving_license_front',
      'driving_license_back',
      'accountqr',
    ];
    final cnicPaths = <String, String>{};
    for (final k in cnicKeys) {
      final url = _existingUrlFromMap(userData, k);
      if (url == null) continue;
      final downloaded = await _downloadUrlToTempFile(url, '${k}_${DateTime.now().millisecondsSinceEpoch}');
      if (downloaded != null && downloaded.isNotEmpty) {
        cnicPaths[k] = downloaded;
      }
    }
    if (cnicPaths.isNotEmpty) {
      await prefs.setString('signup_cnic', jsonEncode(cnicPaths));
    }

    await prefs.remove('pending_signup');
    await prefs.remove('pending_signup_status');
    await prefs.remove('signup_locked');
    await prefs.remove('signup_username_verified');
    await prefs.remove('signup_verified_username');
    await prefs.remove('signup_last_reserved_username');
    await prefs.setString('signup_step', 'personal');
  }

  Future<void> _clearSignupPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_signup');
    await prefs.remove('pending_signup_status');
    await prefs.remove('signup_personal');
    await prefs.remove('signup_emergency');
    await prefs.remove('signup_cnic');
    await prefs.remove('signup_vehicles');
    await prefs.remove('signup_vehicle_images');
    await prefs.remove('signup_step');
    await prefs.remove('signup_locked');
    await prefs.remove('signup_username_verified');
    await prefs.remove('signup_verified_username');
    await prefs.remove('signup_last_reserved_username');
  }

  Future<void> _restartSignupAsFreshUser() async {
    final userData = _userData;
    if (userData == null) return;

    final Map<String, dynamic> dataToUse = Map<String, dynamic>.from(userData);
    final idRaw = dataToUse['id'];
    final id = idRaw != null ? int.tryParse(idRaw.toString()) : null;
    if (id != null) {
      try {
        final profile = await ApiService.getUserProfile(id);
        dataToUse.addAll(profile);
      } catch (_) {}
    }

    final email = (dataToUse['email'] ?? '').toString();
    final phoneNo = (dataToUse['phone_no'] ?? '').toString();
    final username = (dataToUse['username'] ?? '').toString();

    final resp = await ApiService.resetRejectedUser(
      email: email.isNotEmpty ? email : null,
      phoneNo: phoneNo.isNotEmpty ? phoneNo : null,
      username: username.isNotEmpty ? username : null,
    );

    if (resp['success'] == true) {
      // Clear notifications and local session
      try {
        await NotificationService.onUserLogout();
      } catch (_) {}
      await AuthSession.clear();
      await _clearSignupPrefs();
      await _prefillSignupPrefsFromUserData(dataToUse);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/signup_personal',
        (route) => false,
      );
    } else {
      if (!mounted) return;
      final msg = (resp['error'] ?? resp['message'] ?? 'Failed to reset account.').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize once when the route is first built
    if (_userData == null) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _userData = args != null ? Map<String, dynamic>.from(args) : null;
      _loadFullProfileIfPossible();
      _startUnreadPollingIfNeeded();
    }
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFullProfileIfPossible() async {
    final idRaw = _userData?['id'];
    if (idRaw == null) {
      setState(() => _loading = false);
      return;
    }
    final id = int.tryParse(idRaw.toString());
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final profile = await ApiService.getUserProfile(id);
      setState(() {
        // Prefer full profile data but keep any extra keys from original args
        _userData = {
          ...?_userData,
          ...profile,
        };
        _loading = false;
      });
    } catch (_) {
      // If profile load fails, fall back to whatever we already have
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userData = _userData;
    final accountNo = (userData?['accountno'] ?? '').toString();
    final bankName = (userData?['bankname'] ?? '').toString();
    final iban = (userData?['iban'] ?? '').toString();
    final status = (userData?['status'] ?? '').toString().toUpperCase();
    final statusLower = status.toLowerCase();
    final rejectionReason = (userData?['rejection_reason'] ?? '').toString();

    IconData headerIcon = Icons.pending;
    Color headerColor = Colors.orange;
    String headerTitle = 'Registration Pending';
    String headerMessage = 'We are currently reviewing your details. You will be notified once approved.';
    bool showRejectedReason = false;
    bool showFixButton = false;

    if (statusLower == 'rejected') {
      headerIcon = Icons.cancel;
      headerColor = Colors.red;
      headerTitle = 'Account Rejected';
      headerMessage = 'Your account was rejected by admin.';
      showRejectedReason = true;
      showFixButton = true;
    } else if (statusLower == 'banned' || statusLower == 'baned') {
      headerIcon = Icons.block;
      headerColor = Colors.red;
      headerTitle = 'Account Banned';
      headerMessage = 'Your account has been banned by admin.';
    } else if (statusLower == 'suspended') {
      headerIcon = Icons.pause_circle_filled;
      headerColor = Colors.red;
      headerTitle = 'Account Suspended';
      headerMessage = 'Your account has been suspended by admin.';
    } else if (statusLower == 'under_review') {
      headerIcon = Icons.pending;
      headerColor = Colors.orange;
      headerTitle = 'Under Review';
      headerMessage = 'We are currently reviewing your details. You will be notified once approved.';
    } else {
      headerIcon = Icons.pending;
      headerColor = Colors.orange;
      headerTitle = 'Registration Pending';
      headerMessage = 'We are currently reviewing your details. You will be notified once approved.';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        heroTag: 'support_fab_pending',
        onPressed: () async {
          final data = _userData;
          if (data == null) return;
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SupportChatScreen(userData: data),
            ),
          );
        },
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        child: const Icon(Icons.support_agent),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            headerTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              final data = _userData;
              if (data == null) return;
              Navigator.pushNamed(context, '/notifications', arguments: data).then((_) {
                _loadUnreadCount(silent: true);
              });
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none),
                if (_notificationUnreadCount > 0)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              // First, call backend logout (best effort)
              await ApiService.logout();

              // Mirror main profile logout: clear notifications and local session
              try {
                await NotificationService.onUserLogout();
              } catch (_) {}
              await AuthSession.clear();

              if (!context.mounted) return;
              // Always send the user back to the LoginScreen and clear
              // the entire navigation stack so they cannot navigate back
              // into a logged-in area from the pending screen.
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_loading)
                  const CircularProgressIndicator()
                else
                  Icon(headerIcon, size: 80, color: headerColor),
                if (!_loading) ...[
                  const SizedBox(height: 20),
                  Text(
                    headerTitle,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: headerColor),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    headerMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (!_loading && showRejectedReason) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Reason:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      rejectionReason.isNotEmpty ? rejectionReason : 'No reason provided.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                if (!_loading && showFixButton) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _restartSignupAsFreshUser,
                    child: const Text('Fix & Continue Signup'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_loading && userData != null && userData.isNotEmpty) ...[
                  SizedBox(height: 24),
                  Text('Your Submitted Data:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  SizedBox(height: 8),
                  if (accountNo.isNotEmpty || iban.isNotEmpty || bankName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Bank Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    const SizedBox(height: 6),
                    if (accountNo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ACCOUNT NO: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text(accountNo)),
                          ],
                        ),
                      ),
                    if (iban.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('IBAN: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text(iban)),
                          ],
                        ),
                      ),
                    if (bankName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BANK NAME: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text(bankName)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  // Generic key/value information, excluding complex nested structures
                  ...userData.entries
                      .where(
                        (entry) =>
                            entry.key != 'vehicles' &&
                            entry.key != 'password' &&
                            entry.key != 'emergency_contact' &&
                            entry.key != 'accountno' &&
                            entry.key != 'bankname' &&
                            entry.key != 'iban',
                      )
                      .map((entry) {
                    final key = entry.key;
                    final value = entry.value;
                    // Show images for known image fields (as URLs)
                    if ([
                      'profile_photo',
                      'live_photo',
                      'cnic_front_image',
                      'cnic_back_image',
                      'driving_license_front',
                      'driving_license_back',
                      'accountqr',
                    ].contains(key) && value != null && value.toString().isNotEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${key.replaceAll('_', ' ').toUpperCase()}:', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            height: 360,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                value.toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Text('Image not found'),
                              ),
                            ),
                          ),
                          SizedBox(height: 12),
                        ],
                      );
                    } else if (value != null && value.toString().isNotEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${key.replaceAll('_', ' ').toUpperCase()}: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text(value.toString())),
                          ],
                        ),
                      );
                    } else {
                      return SizedBox.shrink();
                    }
                  }),
                  // Emergency contact details (if present)
                  if (userData['emergency_contact'] != null && userData['emergency_contact'] is Map) ...[
                    SizedBox(height: 24),
                    Text('Emergency Contact:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final ec = Map<String, dynamic>.from(userData['emergency_contact'] as Map);
                        final fields = [
                          'name',
                          'relation',
                          'email',
                          'phone_no',
                        ];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: fields.map((key) {
                            final value = ec[key];
                            if (value == null || value.toString().isEmpty) return SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${key.replaceAll('_', ' ').toUpperCase()}: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Expanded(child: Text(value.toString())),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                  // Vehicle details (if any)
                  if (userData['vehicles'] != null && userData['vehicles'] is List && (userData['vehicles'] as List).isNotEmpty) ...[
                    SizedBox(height: 24),
                    Text('Vehicle(s):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ...List<Map<String, dynamic>>.from(userData['vehicles']).asMap().entries.map((vehicleEntry) {
                      final idx = vehicleEntry.key + 1;
                      final vehicle = vehicleEntry.value;
                      return Card(
                        margin: EdgeInsets.symmetric(vertical: 8),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Vehicle #$idx', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ...vehicle.entries.where((e) => !['photo_front','photo_back','documents_image'].contains(e.key)).map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${e.key.replaceAll('_', ' ').toUpperCase()}: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Expanded(child: Text(e.value != null ? e.value.toString() : '')),
                                  ],
                                ),
                              )),
                              // Show vehicle images
                              ...['photo_front','photo_back','documents_image'].map((imgKey) {
                                final imgUrl = vehicle[imgKey];
                                if (imgUrl != null && imgUrl.toString().isNotEmpty) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(height: 6),
                                      Text('${imgKey.replaceAll('_', ' ').toUpperCase()}:', style: TextStyle(fontWeight: FontWeight.bold)),
                                      SizedBox(height: 4),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 260,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            imgUrl.toString(),
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => const Text('Image not found'),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  return SizedBox.shrink();
                                }
                              }),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
