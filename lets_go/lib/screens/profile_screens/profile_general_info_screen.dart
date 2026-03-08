import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../utils/auth_session.dart';
import '../../controllers/profile/profile_general_info_controller.dart';
import '../../controllers/profile/profile_contact_change_controller.dart';
import 'profile_bank_info_edit_screen.dart';
import 'profile_cnic_edit_screen.dart';
import 'profile_contact_change_screen.dart';
import 'profile_edit_screen.dart';
import 'profile_emergency_contact_edit_screen.dart';
import 'profile_photos_edit_screen.dart';

class ProfileGeneralInfoScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final void Function(VoidCallback toggleEdit)? onRegisterActions; // parent can trigger edit/save

  const ProfileGeneralInfoScreen({
    super.key,
    required this.userData,
    this.onRegisterActions,
  });

  @override
  State<ProfileGeneralInfoScreen> createState() => _ProfileGeneralInfoScreenState();
}

class _ProfileGeneralInfoScreenState extends State<ProfileGeneralInfoScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _freshUser; // deprecated: hydration now in controller
  String? _profilePhotoUrl; // resolved profile photo URL
  late ProfileGeneralInfoController _controller;

  Map<String, dynamic>? _cnicChangeRequest;
  Map<String, dynamic>? _genderChangeRequest;

  final PageController _cnicPageController = PageController();
  int _cnicPageIndex = 0;

  final PageController _genderPageController = PageController();
  int _genderPageIndex = 0;

  String _crStatusLabel(String status) {
    final s = status.toUpperCase();
    if (s == 'APPROVED') return 'VERIFIED';
    return s;
  }

  Color _crStatusColor(String status) {
    final s = status.toUpperCase();
    if (s == 'APPROVED') return const Color(0xFF2E7D32);
    if (s == 'REJECTED') return const Color(0xFFC62828);
    if (s == 'PENDING') return const Color(0xFFEF6C00);
    return Colors.grey;
  }

  Widget _statusBadge(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget _versionedValueTile({
    required String title,
    required String value,
    required String badgeText,
    required Color badgeColor,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth - 80;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: tileWidth,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(value.isNotEmpty ? value : 'Not provided', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCnicVersionedGallery() {
    final cnicNo = _controller.resolveCnic().toString();
    final currentFront = (_controller.imageUrl('cnic_front_image') ?? '').toString();
    final currentBack = (_controller.imageUrl('cnic_back_image') ?? '').toString();

    final pages = <Map<String, dynamic>>[];

    if (cnicNo.trim().isNotEmpty || currentFront.trim().isNotEmpty || currentBack.trim().isNotEmpty) {
      pages.add({
        'badgeText': 'CURRENT',
        'badgeColor': const Color(0xFF2E7D32),
        'no': cnicNo,
        'front': currentFront,
        'back': currentBack,
      });
    }

    final cr = _cnicChangeRequest;
    if (cr != null) {
      final requested = cr['requested_changes'] is Map ? Map<String, dynamic>.from(cr['requested_changes'] as Map) : <String, dynamic>{};
      final status = (cr['status'] ?? '').toString().toUpperCase();
      final badgeText = _crStatusLabel(status);
      final badgeColor = _crStatusColor(status);

      final reqNo = (requested['cnic_no'] ?? requested['cnic'] ?? '').toString().trim();
      final reqFront = (requested['cnic_front_image_url'] ??
              requested['cnic_front_image'] ??
              requested['cnic_front'] ??
              '')
          .toString()
          .trim();
      final reqBack = (requested['cnic_back_image_url'] ??
              requested['cnic_back_image'] ??
              requested['cnic_back'] ??
              '')
          .toString()
          .trim();

      pages.add({
        'badgeText': badgeText,
        'badgeColor': badgeColor,
        'no': reqNo.isNotEmpty ? reqNo : cnicNo,
        'front': reqFront.isNotEmpty ? reqFront : currentFront,
        'back': reqBack.isNotEmpty ? reqBack : currentBack,
      });
    }

    final cleaned = pages.where((p) {
      final no = (p['no'] ?? '').toString().trim();
      final f = (p['front'] ?? '').toString().trim();
      final b = (p['back'] ?? '').toString().trim();
      return no.isNotEmpty || f.isNotEmpty || b.isNotEmpty;
    }).toList();

    if (cleaned.isEmpty) return const SizedBox.shrink();

    final active = _cnicPageIndex.clamp(0, cleaned.length - 1);

    Widget docImage(String label, String url) {
      return InkWell(
        onTap: url.trim().isEmpty ? null : () => _confirmAndShowSensitiveImage(url, title: label),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              color: Colors.grey[100],
            ),
            child: url.trim().isEmpty
                ? const Center(child: Icon(Icons.image, color: Colors.grey, size: 40))
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                  ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 460,
          child: PageView.builder(
            controller: _cnicPageController,
            onPageChanged: (i) {
              if (!mounted) return;
              setState(() {
                _cnicPageIndex = i;
              });
            },
            itemCount: cleaned.length,
            itemBuilder: (context, index) {
              final p = cleaned[index];
              final badgeText = (p['badgeText'] ?? '').toString();
              final badgeColor = (p['badgeColor'] as Color?) ?? Colors.grey;
              final no = (p['no'] ?? '').toString();
              final front = (p['front'] ?? '').toString();
              final back = (p['back'] ?? '').toString();

              return Padding(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'CNIC: ${no.isNotEmpty ? no : 'Not provided'}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 6)),
                              ],
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      docImage('CNIC Front', front),
                      const SizedBox(height: 12),
                      docImage('CNIC Back', back),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (cleaned.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(cleaned.length, (i) {
              final isActive = i == active;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 7,
                width: isActive ? 18 : 7,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF00897B) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildGenderVersionedScroller(String currentGender) {
    final cr = _genderChangeRequest;
    if (cr == null) return const SizedBox.shrink();

    final original = cr['original_data'] is Map ? Map<String, dynamic>.from(cr['original_data'] as Map) : <String, dynamic>{};
    final requested = cr['requested_changes'] is Map ? Map<String, dynamic>.from(cr['requested_changes'] as Map) : <String, dynamic>{};
    final status = (cr['status'] ?? '').toString().toUpperCase();

    final oldGender = (original['gender'] ?? currentGender).toString();
    final newGender = (requested['gender'] ?? '').toString();

    final tiles = <Widget>[
      _versionedValueTile(
        title: 'Gender',
        value: oldGender,
        badgeText: 'CURRENT',
        badgeColor: const Color(0xFF2E7D32),
      ),
    ];

    if (newGender.trim().isNotEmpty) {
      tiles.add(
        _versionedValueTile(
          title: 'Gender',
          value: newGender,
          badgeText: _crStatusLabel(status),
          badgeColor: _crStatusColor(status),
        ),
      );
    }

    final active = _genderPageIndex.clamp(0, tiles.length - 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 110,
          child: PageView.builder(
            controller: _genderPageController,
            onPageChanged: (i) {
              if (!mounted) return;
              setState(() {
                _genderPageIndex = i;
              });
            },
            itemCount: tiles.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(child: tiles[index]),
              );
            },
          ),
        ),
        if (tiles.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(tiles.length, (i) {
              final isActive = i == active;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 7,
                width: isActive ? 18 : 7,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF00897B) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _cnicStatusBadgeOrEmpty() {
    final cr = _cnicChangeRequest;
    if (cr == null) return const SizedBox.shrink();
    final status = (cr['status'] ?? '').toString().toUpperCase();
    if (status != 'PENDING' && status != 'REJECTED') return const SizedBox.shrink();
    return _statusBadge(_crStatusLabel(status), color: _crStatusColor(status));
  }

  String _maskSensitiveNumber(String value, {int keepStart = 3, int keepEnd = 2}) {
    final v = value.trim();
    if (v.isEmpty) return v;
    if (v.length <= keepStart + keepEnd) return v;
    final start = v.substring(0, keepStart);
    final end = v.substring(v.length - keepEnd);
    return '$start${'*' * (v.length - keepStart - keepEnd)}$end';
  }

  @override
  void initState() {
    super.initState();
    _profilePhotoUrl = widget.userData['profile_photo']?.toString();
    // Initialize controller and hydrate profile via controller
    _controller = ProfileGeneralInfoController(
      initialUser: widget.userData,
      onStateChanged: () {
        if (!mounted) return;
        setState(() {});
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
    _initControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.hydrateProfile();
      _loadSensitiveChangeRequests();
    });
  }

  Future<void> _loadSensitiveChangeRequests() async {
    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    if (userId == null) return;
    try {
      final res = await ApiService.getUserChangeRequests(
        userId,
        entityType: 'USER_PROFILE',
        limit: 30,
      );
      if (res['success'] != true) return;
      final list = res['change_requests'];
      if (list is! List) return;
      Map<String, dynamic>? foundCnic;
      Map<String, dynamic>? foundGender;
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final requested = m['requested_changes'];
        if (requested is Map) {
          final keys = requested.keys.map((e) => e.toString()).toList();
          final hasCnic = keys.any((k) => k.startsWith('cnic_')) ||
              keys.any((k) => k.contains('cnic_front')) ||
              keys.any((k) => k.contains('cnic_back'));

          final hasGender = keys.any((k) => k == 'gender');

          final st = (m['status'] ?? '').toString().toUpperCase();
          if (st != 'PENDING' && st != 'REJECTED') {
            continue;
          }

          if (hasCnic) {
            if (st == 'PENDING') {
              foundCnic = m;
            }
            foundCnic ??= m;
          }

          if (hasGender) {
            if (st == 'PENDING') {
              foundGender = m;
            }
            foundGender ??= m;
          }

          if (foundCnic != null && foundGender != null) {
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _cnicChangeRequest = foundCnic;
        _genderChangeRequest = foundGender;
      });

      if (foundCnic != null) {
        final cnicCr = Map<String, dynamic>.from(foundCnic);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_cnicPageController.hasClients) return;
          final requested = cnicCr['requested_changes'];
          final hasRequested = requested is Map && requested.isNotEmpty;
          if (!hasRequested) return;

          final cnicNo = _controller.resolveCnic().toString();
          final currentFront = (_controller.imageUrl('cnic_front_image') ?? '').toString();
          final currentBack = (_controller.imageUrl('cnic_back_image') ?? '').toString();
          final hasCurrent = cnicNo.trim().isNotEmpty || currentFront.trim().isNotEmpty || currentBack.trim().isNotEmpty;
          final targetPage = hasCurrent ? 1 : 0;
          try {
            _cnicPageController.animateToPage(
              targetPage,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
            setState(() {
              _cnicPageIndex = targetPage;
            });
          } catch (_) {
            // ignore
          }
        });
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _confirmAndShowSensitiveImage(String url, {required String title}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sensitive document'),
        content: const Text('This image contains sensitive information. Do you want to view it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('View')),
        ],
      ),
    );
    if (ok == true && mounted) {
      _showImagePreview(url, title: title);
    }
  }

  Future<void> _openPhotosEdit() async {
    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User ID not found')));
      return;
    }

    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProfilePhotosEditScreen(
          userId: userId,
          initialUser: Map<String, dynamic>.from(widget.userData),
        ),
      ),
    );

    if (updated != null) {
      await AuthSession.save(updated);
      if (!mounted) return;
      setState(() {
        widget.userData.addAll(updated);
      });
      await _refreshUserFromApi();
    }
  }

  Future<void> _refreshUserFromApi() async {
    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    if (userId == null) return;
    try {
      final fresh = await ApiService.getUserProfile(userId);
      await AuthSession.save(fresh);
      if (!mounted) return;
      setState(() {
        widget.userData.addAll(fresh);
      });
      _controller.hydrateProfile();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _openContactChange(ContactChangeWhich which) async {
    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User ID not found')));
      return;
    }
    final currentValue = which == ContactChangeWhich.email
        ? (widget.userData['email'] ?? '').toString()
        : _controller.resolvePhone();

    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProfileContactChangeScreen(
          userId: userId,
          which: which,
          currentValue: currentValue,
        ),
      ),
    );

    if (updated != null) {
      await AuthSession.save(updated);
      if (!mounted) return;
      setState(() {
        widget.userData.addAll(updated);
      });
      _controller.hydrateProfile();
    }
  }

  Future<void> _openCnicEdit() async {
    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User ID not found')));
      return;
    }

    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProfileCnicEditScreen(
          userId: userId,
          initialUser: Map<String, dynamic>.from(widget.userData),
        ),
      ),
    );

    if (updated != null) {
      setState(() {
        widget.userData.addAll(updated);
      });
      await _refreshUserFromApi();
      await _loadSensitiveChangeRequests();
    }
  }

  // --- Bank Info Section (QR + Account No + Bank Name) ---
  Widget _buildBankInfoSection() {
    final accountNo = _controller.resolveString(['accountno']);
    final bankName = _controller.resolveString(['bankname']);
    final iban = _controller.resolveString(['iban']);
    final qrUrl = (_controller.imageUrl('accountqr') ?? '');
    final qrUrlResolved = qrUrl.isNotEmpty ? qrUrl : null;

    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: Color(0xFF00897B)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Bank Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit),
                onPressed: userId == null
                    ? null
                    : () async {
                        final updated = await Navigator.of(context).push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (_) => ProfileBankInfoEditScreen(
                              userId: userId,
                              initialUser: Map<String, dynamic>.from(widget.userData),
                            ),
                          ),
                        );
                        if (updated != null) {
                          await AuthSession.save(updated);
                          if (!mounted) return;
                          setState(() {
                            widget.userData.addAll(updated);
                          });
                          await _refreshUserFromApi();
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // QR
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: qrUrlResolved != null
                    ? Stack(
                        children: [
                          InkWell(
                            onTap: () => _showImagePreview(qrUrlResolved, title: 'Account QR'),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                qrUrlResolved,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.qr_code, size: 36, color: Colors.grey),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: InkWell(
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: qrUrlResolved));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('QR URL copied')),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.copy, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(child: Icon(Icons.qr_code, size: 36, color: Colors.grey)),
              ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _labeledValue('Account Number', accountNo.isNotEmpty ? accountNo : 'Not provided'),
                        ),
                        if (accountNo.isNotEmpty)
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: accountNo));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Account number copied')),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _labeledValue('IBAN', iban.isNotEmpty ? iban : 'Not provided'),
                        ),
                        if (iban.isNotEmpty)
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: iban));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('IBAN copied')),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _labeledValue('Bank Name', bankName.isNotEmpty ? bankName : 'Not provided'),
                        ),
                        if (bankName.isNotEmpty)
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: bankName));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Bank name copied')),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContactSection() {
    // Prefer hydrated emergency_contact from controller/user, fall back to initial props
    Map<String, dynamic>? ec;
    final fromUser = _controller.user['emergency_contact'];
    if (fromUser is Map) {
      ec = Map<String, dynamic>.from(fromUser);
    } else if (widget.userData['emergency_contact'] is Map) {
      ec = Map<String, dynamic>.from(widget.userData['emergency_contact'] as Map);
    }

    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.contact_emergency,
                    color: Color(0xFF00897B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Emergency Contact',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E2E2E),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit),
                  onPressed: userId == null
                      ? null
                      : () async {
                          final updated = await Navigator.of(context).push<Map<String, dynamic>>(
                            MaterialPageRoute(
                              builder: (_) => ProfileEmergencyContactEditScreen(
                                userId: userId,
                                initialEmergencyContact: ec,
                              ),
                            ),
                          );
                          if (updated != null) {
                            await AuthSession.save(updated);
                            if (!mounted) return;
                            setState(() {
                              widget.userData.addAll(updated);
                            });
                            await _refreshUserFromApi();
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (ec == null || ec.isEmpty) ...[
              const Text(
                'No emergency contact added.',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              _labeledValue('Name', (ec['name'] ?? '').toString().isNotEmpty
                  ? (ec['name'] ?? '').toString()
                  : 'Not provided'),
              const SizedBox(height: 12),
              _labeledValue('Relation', (ec['relation'] ?? '').toString().isNotEmpty
                  ? (ec['relation'] ?? '').toString()
                  : 'Not provided'),
              const SizedBox(height: 12),
              _labeledValue('Email', (ec['email'] ?? '').toString().isNotEmpty
                  ? (ec['email'] ?? '').toString()
                  : 'Not provided'),
              const SizedBox(height: 12),
              _labeledValue('Phone', (ec['phone_no'] ?? '').toString().isNotEmpty
                  ? (ec['phone_no'] ?? '').toString()
                  : 'Not provided'),
            ],
          ],
        ),
      ),
    );
  }

  // --- Ratings Section: show both driver and passenger ratings ---
  Widget _buildRatingsSection() {
    final driverRating = double.tryParse((widget.userData['driver_rating'] ?? _freshUser?['driver_rating'] ?? '').toString());
    final passengerRating = double.tryParse((widget.userData['passenger_rating'] ?? _freshUser?['passenger_rating'] ?? '').toString());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ratingTile(
              label: 'Driver Rating',
              value: driverRating,
              icon: Icons.directions_car,
              color: Colors.blue,
            ),
          ),
          Container(width: 1, height: 40, color: Colors.grey[200]),
          Expanded(
            child: _ratingTile(
              label: 'Passenger Rating',
              value: passengerRating,
              icon: Icons.person,
              color: const Color(0xFF26A69A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingTile({required String label, required double? value, required IconData icon, required Color color}) {
    final text = value != null ? value.toStringAsFixed(1) : 'N/A';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star, size: 16, color: Colors.amber),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2E2E2E))),
          ],
        ),
      ],
    );
  }

  // --- Documents Section (Horizontal) ---
  Widget _buildDocumentsSection() {
    final cnicItems = _controller.getCnicImages();
    final cnicNo = _controller.resolveCnic().toString();
    final cnicDisplay = cnicNo.isNotEmpty ? _maskSensitiveNumber(cnicNo) : 'Not provided';

    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');

    if (cnicItems.isEmpty && _cnicChangeRequest == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open, color: Color(0xFF00897B)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                _cnicStatusBadgeOrEmpty(),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit, color: Color(0xFF00897B)),
                  onPressed: userId == null ? null : _openCnicEdit,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildModernInfoRow('CNIC Number', cnicDisplay, Icons.credit_card),
            const SizedBox(height: 10),
            const Text(
              'CNIC and driving license are sensitive documents and require manual admin verification.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text('No CNIC images uploaded.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open, color: Color(0xFF00897B)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              _cnicStatusBadgeOrEmpty(),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit, color: Color(0xFF00897B)),
                onPressed: userId == null ? null : _openCnicEdit,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'CNIC and driving license are sensitive documents and require manual admin verification.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _buildCnicVersionedGallery(),
          if ((_cnicChangeRequest?['status'] ?? '').toString().toUpperCase() == 'REJECTED' &&
              ((_cnicChangeRequest?['review_notes'] ?? '').toString().trim().isNotEmpty)) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC62828).withValues(alpha: 0.25)),
              ),
              child: Text(
                'Rejected reason: ${(_cnicChangeRequest?['review_notes'] ?? '').toString().trim()}',
                style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _labeledValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _showImagePreview(String url, {String? title}) {
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              Container(
                constraints: const BoxConstraints(maxHeight: 480, maxWidth: 360),
                margin: const EdgeInsets.all(16),
                child: Image.network(url, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('Failed to load image'),
                        )),
              ),
            ],
          ),
        );
      },
    );
  }

  // Resolve image URLs from hydrated or initial data
  // Removed: image/string resolvers now handled by controller

  void _initControllers() {
    // No-op: legacy inline-edit controllers removed as part of card-based edit flow.
  }

  @override
  void dispose() {
    _cnicPageController.dispose();
    _genderPageController.dispose();
    super.dispose();
  }

  // Network image verification moved out (no longer needed); controller provides URLs

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF00897B).withValues(alpha: 0.1),
            Colors.grey[50]!,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHeader(),
              const SizedBox(height: 16),
              _buildRatingsSection(),
              const SizedBox(height: 16),
              _buildStatsCards(),
              const SizedBox(height: 24),
              _buildPersonalInfoSection(),
              const SizedBox(height: 24),
              _buildEmergencyContactSection(),
              const SizedBox(height: 24),
              _buildBankInfoSection(),
              const SizedBox(height: 24),
              _buildDocumentsSection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final userName = (widget.userData['name'] ?? _controller.user['name'] ?? 'User');
    final usernameRaw = (widget.userData['username'] ?? _controller.user['username'] ?? '').toString().trim();
    final userUsername = usernameRaw.isNotEmpty ? usernameRaw : null;
    final userEmail = widget.userData['email'] ?? 'No email';
    final userPhone = _controller.resolvePhone();
    final isDriver = _controller.isDriver;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF00897B), const Color(0xFF4DB6AC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 8,
            top: 8,
            child: PopupMenuButton<ContactChangeWhich>(
              icon: Icon(Icons.edit, color: Colors.white.withValues(alpha: 0.95)),
              onSelected: (which) => _openContactChange(which),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: ContactChangeWhich.email,
                  child: Text('Change Email'),
                ),
                PopupMenuItem(
                  value: ContactChangeWhich.phone,
                  child: Text('Change Phone'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: (((_controller.profilePhotoUrl() ?? _profilePhotoUrl) != null) && ((_controller.profilePhotoUrl() ?? _profilePhotoUrl)!.isNotEmpty))
                                ? Image.network(
                                    (_controller.profilePhotoUrl() ?? _profilePhotoUrl)!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: const Color(0xFF00897B),
                                        alignment: Alignment.center,
                                        child: Text(
                                          userName.toString().isNotEmpty ? userName.toString()[0].toUpperCase() : 'U',
                                          style: const TextStyle(fontSize: 32, color: Colors.white),
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: const Color(0xFF00897B),
                                    alignment: Alignment.center,
                                    child: Text(
                                      userName.toString().isNotEmpty ? userName.toString()[0].toUpperCase() : 'U',
                                      style: const TextStyle(fontSize: 32, color: Colors.white),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          onTap: _openPhotosEdit,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white70),
                            ),
                            child: const Icon(Icons.photo_camera, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName.toString(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (userUsername != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          userUsername.startsWith('@') ? userUsername : '@$userUsername',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isDriver ? 'Driver' : 'Passenger',
                          style: const TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Icon(Icons.email, color: Colors.white, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              userEmail.length > 20 ? '${userEmail.substring(0, 20)}...' : userEmail,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const Icon(Icons.phone, color: Colors.white, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              userPhone,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    final isDriver = _controller.isDriver;
    final status = widget.userData['status'] ?? 'Unknown';
    final joinDate = widget.userData['created_at'] != null
        ? DateTime.parse(widget.userData['created_at']).year.toString()
        : 'N/A';
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.verified_user,
            title: 'Status',
            value: status.toString().toUpperCase(),
            color: status.toString().toLowerCase() == 'verified'
                ? Colors.green
                : status.toString().toLowerCase() == 'pending'
                    ? Colors.orange
                    : Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.calendar_today,
            title: 'Member Since',
            value: joinDate,
            color: const Color(0xFF00897B),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: isDriver ? Icons.directions_car : Icons.person,
            title: 'Account Type',
            value: isDriver ? 'Driver' : 'Passenger',
            color: isDriver ? Colors.blue : const Color(0xFF26A69A),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    final gender = (_controller.user['gender'] ?? widget.userData['gender'] ?? 'Not provided').toString();
    final address = (_controller.user['address'] ?? widget.userData['address'] ?? 'Not provided').toString();

    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: Color(0xFF00897B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Personal Information',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E2E2E),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit),
                  onPressed: userId == null
                      ? null
                      : () async {
                          final result = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => ProfileEditScreen(userData: Map<String, dynamic>.from(widget.userData)),
                            ),
                          );
                          if (result == true) {
                            await _refreshUserFromApi();
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_genderChangeRequest != null) ...[
              _buildGenderVersionedScroller(gender),
              if ((_genderChangeRequest?['status'] ?? '').toString().toUpperCase() == 'REJECTED' &&
                  ((_genderChangeRequest?['review_notes'] ?? '').toString().trim().isNotEmpty)) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC62828).withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Rejected reason: ${(_genderChangeRequest?['review_notes'] ?? '').toString().trim()}',
                    style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w600),
                  ),
                ),
              ]
            ] else ...[
              _buildModernInfoRow('Gender', gender.isNotEmpty ? gender : 'Not provided', Icons.person),
            ],
            const SizedBox(height: 14),
            _buildModernInfoRow('Address', address.isNotEmpty ? address : 'Not provided', Icons.location_on),
          ],
        ),
      ),
    );
  }

  Widget _buildModernInfoRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF00897B), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E2E2E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Removed: driver check now provided by controller

  // Helpers moved to controller
}