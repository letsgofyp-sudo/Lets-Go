import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'vehicle_detail_screen.dart';
import 'vehicle_form_screen.dart';
import '../../controllers/profile/profile_vehicle_info_controller.dart';
import 'profile_driving_license_edit_screen.dart';

class ProfileVehicleInfoScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProfileVehicleInfoScreen({
    super.key,
    required this.userData,
  });

  @override
  State<ProfileVehicleInfoScreen> createState() => _ProfileVehicleInfoScreenState();
}

class _ProfileVehicleInfoScreenState extends State<ProfileVehicleInfoScreen> with AutomaticKeepAliveClientMixin {
  // State now comes from controller
  bool isDriver = false;
  bool isLoading = true;
  List<Map<String, dynamic>> vehicles = [];
  String? errorMessage;
  late ProfileVehicleInfoController _controller;

  Map<String, dynamic>? _licenseChangeRequest;

  final PageController _licensePageController = PageController();
  int _licensePageIndex = 0;

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
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 420, maxWidth: 360),
                margin: const EdgeInsets.all(16),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = ProfileVehicleInfoController(
      initialUser: widget.userData,
      onStateChanged: () {
        if (!mounted) return;
        setState(() {
          // mirror controller state for convenience
          isDriver = _controller.isDriver;
          isLoading = _controller.isLoading;
          vehicles = _controller.vehicles;
          errorMessage = _controller.errorMessage;
        });
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
    _controller.computeDriverByLicenseOnly();
    _loadVehicles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.hydrateUser();
      _loadLicenseChangeRequest();
    });
  }

  Future<void> _loadLicenseChangeRequest() async {
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

      Map<String, dynamic>? found;
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final requested = m['requested_changes'];
        if (requested is Map) {
          final keys = requested.keys.map((e) => e.toString()).toList();
          final hasDl = keys.any((k) => k.startsWith('driving_license_'));
          if (hasDl) {
            final st = (m['status'] ?? '').toString().toUpperCase();
            if (st == 'PENDING' || st == 'REJECTED') {
              if (st == 'PENDING') {
                found = m;
                break;
              }
              found ??= m;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _licenseChangeRequest = found;
      });

      if (found != null) {
        final dlCr = Map<String, dynamic>.from(found);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_licensePageController.hasClients) return;
          final requested = dlCr['requested_changes'];
          final hasRequested = requested is Map && requested.isNotEmpty;
          if (!hasRequested) return;

          final currentNo = _controller.licenseNumber();
          final currentFront = (_controller.userImg('driving_license_front') ?? '').toString();
          final currentBack = (_controller.userImg('driving_license_back') ?? '').toString();
          final hasCurrent = currentNo.trim().isNotEmpty || currentFront.trim().isNotEmpty || currentBack.trim().isNotEmpty;
          final targetPage = hasCurrent ? 1 : 0;
          try {
            _licensePageController.animateToPage(
              targetPage,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
            setState(() {
              _licensePageIndex = targetPage;
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

  Widget _buildLicenseVersionedGallery({
    required String currentNo,
  }) {
    final currentFront = (_controller.userImg('driving_license_front') ?? '').toString();
    final currentBack = (_controller.userImg('driving_license_back') ?? '').toString();

    final pages = <Map<String, dynamic>>[];

    if (currentNo.trim().isNotEmpty || currentFront.trim().isNotEmpty || currentBack.trim().isNotEmpty) {
      pages.add({
        'badgeText': 'CURRENT',
        'badgeColor': const Color(0xFF2E7D32),
        'no': currentNo,
        'front': currentFront,
        'back': currentBack,
      });
    }

    final cr = _licenseChangeRequest;
    if (cr != null) {
      final requested = cr['requested_changes'] is Map ? Map<String, dynamic>.from(cr['requested_changes'] as Map) : <String, dynamic>{};
      final status = (cr['status'] ?? '').toString().toUpperCase();
      final badgeText = _crStatusLabel(status);
      final badgeColor = _crStatusColor(status);

      final reqNo = (requested['driving_license_no'] ?? '').toString().trim();
      final reqFront = (requested['driving_license_front_url'] ??
              requested['driving_license_front'] ??
              '')
          .toString()
          .trim();
      final reqBack = (requested['driving_license_back_url'] ??
              requested['driving_license_back'] ??
              '')
          .toString()
          .trim();

      pages.add({
        'badgeText': badgeText,
        'badgeColor': badgeColor,
        'no': reqNo.isNotEmpty ? reqNo : currentNo,
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

    final active = _licensePageIndex.clamp(0, cleaned.length - 1);

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
            controller: _licensePageController,
            onPageChanged: (i) {
              if (!mounted) return;
              setState(() {
                _licensePageIndex = i;
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
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'License: ${no.isNotEmpty ? no : 'Not provided'}',
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
                      docImage('License Front', front),
                      const SizedBox(height: 12),
                      docImage('License Back', back),
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

  @override
  void dispose() {
    _licensePageController.dispose();
    super.dispose();
  }

  Future<void> _openDrivingLicenseEdit() async {
    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User ID not found')));
      return;
    }

    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ProfileDrivingLicenseEditScreen(
          userId: userId,
          initialUser: Map<String, dynamic>.from(widget.userData),
        ),
      ),
    );

    if (updated != null) {
      if (!mounted) return;
      setState(() {
        widget.userData.addAll(updated);
      });
      await _controller.hydrateUser();
      await _loadLicenseChangeRequest();
    }
  }

  Widget _buildLicenseOnlySection() {
    final licenseNo = _controller.licenseNumber();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDriverHeader(),
          const SizedBox(height: 24),
          _buildStatsCards(),
          const SizedBox(height: 24),
          _buildLicenseSection(licenseNo),
          const SizedBox(height: 24),
          // Empty vehicles hint
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.directions_car, color: Color(0xFF00897B)),
                    SizedBox(width: 8),
                    Text('No vehicles registered', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your vehicle to complete your driver profile and start offering rides.',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _openAddVehicle,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Add Vehicle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddVehicle() async {
    final uid = widget.userData['id'];
    final userId = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User ID not found')));
      return;
    }

    if (!_controller.hasLicenseImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload driving license front & back images before adding a vehicle.')),
      );
      return;
    }

    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VehicleFormScreen(userId: userId),
      ),
    );
    if (ok == true) {
      await _controller.loadVehicles();
    }
  }

  Future<void> _ensureVehicleDetails(int vehicleId) => _controller.ensureVehicleDetails(vehicleId);

  // Driver computation now in controller
  
  Future<void> _loadVehicles() => _controller.loadVehicles();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
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
      child: RefreshIndicator(
        onRefresh: _loadVehicles,
        child: _controller.isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
            : _controller.errorMessage != null && !_controller.hasLicense
                ? _buildErrorState()
                : (_controller.vehicles.isNotEmpty)
                    ? _buildDriverVehicleInfo()
                    : (_controller.hasLicense)
                        ? _buildLicenseOnlySection()
                        : _buildBecomeDriverSection(),
      ),
    );
  }

  Widget _buildDriverVehicleInfo() {
    final licenseNo = widget.userData['driving_license_no'] ?? 'Not provided';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDriverHeader(),
          const SizedBox(height: 24),
          _buildStatsCards(),
          const SizedBox(height: 24),
          _buildLicenseSection(licenseNo),
          const SizedBox(height: 24),
          _buildVehiclesSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(dynamic vehicle) {
    final companyName = (vehicle['company_name'] ?? 'Unknown').toString();
    final modelNumber = (vehicle['model_number'] ?? 'Unknown').toString();
    final plateNumber = (vehicle['plate_number'] ?? vehicle['plate'] ?? 'Unknown').toString();
    final photoFrontUrl = (vehicle['photo_front_url'] ?? vehicle['photo_front'])?.toString();
    final status = (vehicle['status'] ?? '').toString().toUpperCase();
    final isVerified = status == 'VERIFIED' || status == 'APPROVED';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                color: const Color(0xFF00897B).withValues(alpha: 0.06),
              ),
              child: (photoFrontUrl != null && photoFrontUrl.trim().isNotEmpty)
                  ? Image.network(
                      photoFrontUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _frontPlaceholder(),
                    )
                  : _frontPlaceholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$companyName $modelNumber',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  plateNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isVerified ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isVerified ? 'VERIFIED' : (status.isNotEmpty ? status : 'PENDING'),
                    style: TextStyle(
                      color: isVerified ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _frontPlaceholder() {
    return Container(
      color: const Color(0xFF00897B).withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.directions_car, size: 28, color: Color(0xFF00897B)),
      ),
    );
  }

  Widget _buildBecomeDriverSection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF00897B), const Color(0xFF4DB6AC)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00897B).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_car,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Become a Driver',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2E2E2E),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Register your vehicle and driving license to start offering rides to others and earn money.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF00897B), const Color(0xFF4DB6AC)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00897B).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: GestureDetector(
                onLongPress: _navigateToDriverRegistration,
                child: ElevatedButton.icon(
                  onPressed: _openAddVehicle,
                  icon: const Icon(Icons.app_registration, color: Colors.white),
                  label: const Text(
                    'Register as Driver',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDriverRegistration() {
    // TODO: Implement navigation to driver registration
    // For now, just show a dialog explaining the process
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Driver Registration'),
        content: const Text(
          'To become a driver, you need to provide:\n\n'  
          '1. Your driving license information\n'  
          '2. Vehicle details (make, model, year, color, registration)\n'  
          '3. Vehicle photos\n\n'  
          'This feature will be available soon!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverHeader() {
    final userName = widget.userData['name'] ?? 'Driver';
    final driverRating = widget.userData['driver_rating'] ?? 0.0;
    
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: CircleAvatar(
                radius: 35,
                backgroundColor: Colors.white,
                child: const Icon(
                  Icons.directions_car,
                  size: 40,
                  color: Color(0xFF00897B),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🚗 Verified Driver',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        double.tryParse(driverRating.toString())?.toStringAsFixed(1) ?? '0.0',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.directions_car,
            title: 'Vehicles',
            value: vehicles.length.toString(),
            color: const Color(0xFF00897B),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.verified_user,
            title: 'License',
            value: 'Valid',
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.local_taxi,
            title: 'Status',
            value: 'Active',
            color: Colors.blue,
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

  Widget _buildLicenseSection(String licenseNo) {
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
                    Icons.credit_card,
                    color: Color(0xFF00897B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Driving License',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E2E2E),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit, color: Color(0xFF00897B)),
                  onPressed: _openDrivingLicenseEdit,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
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
                    child: const Icon(Icons.confirmation_number, color: Color(0xFF00897B), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'License Number',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          licenseNo.toString(),
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
            ),
            const SizedBox(height: 10),
            const Text(
              'Driving license images require manual admin verification.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _buildLicenseVersionedGallery(currentNo: licenseNo.toString()),
            if ((_licenseChangeRequest?['status'] ?? '').toString().toUpperCase() == 'REJECTED' &&
                ((_licenseChangeRequest?['review_notes'] ?? '').toString().trim().isNotEmpty)) ...[
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
                  'Rejected reason: ${(_licenseChangeRequest?['review_notes'] ?? '').toString().trim()}',
                  style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclesSection() {
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        Icons.directions_car,
                        color: Color(0xFF00897B),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'My Vehicles',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E2E2E),
                      ),
                    ),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: _openAddVehicle,
                    icon: const Icon(Icons.add, color: Color(0xFF00897B)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (vehicles.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.directions_car_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No vehicles registered',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your first vehicle to start offering rides',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else ...[
              // Compact list of vehicles
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: vehicles.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final v = vehicles[index];
                  return InkWell(
                    onTap: () async {
                      final vid = (v['id'] as int?) ?? int.tryParse(v['id']?.toString() ?? '');
                      if (vid == null) return;
                      await _ensureVehicleDetails(vid);
                      if (!context.mounted) return;
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => VehicleDetailScreen(vehicleId: vid, base: v, user: widget.userData),
                        ),
                      );
                      if (changed == true) {
                        await _loadVehicles();
                      }
                    },
                    child: _buildVehicleCard(v),
                  );
                },
              ),
              // Separate detail screen, no inline expansion
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _controller.errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _controller.loadVehicles,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Try Again',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}