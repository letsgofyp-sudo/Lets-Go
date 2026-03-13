import 'package:flutter/material.dart';
 
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../utils/auth_session.dart';
import '../../controllers/profile/profile_main_controller.dart';
import 'profile_general_info_screen.dart';
import 'profile_ride_history_screen.dart';
import 'profile_vehicle_info_screen.dart';
import 'profile_blocked_users_screen.dart';
import 'profile_change_password_screen.dart';

class ProfileMainScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProfileMainScreen({
    super.key,
    required this.userData,
  });

  @override
  State<ProfileMainScreen> createState() => _ProfileMainScreenState();
}

class _ProfileMainScreenState extends State<ProfileMainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isDriver = false;
  late Map<String, dynamic> _user; // local merged user data
  late ProfileMainController _controller;

  @override
  void initState() {
    super.initState();
    _user = Map<String, dynamic>.from(widget.userData);
    _controller = ProfileMainController(
      user: _user,
      onStateChanged: () {
        if (!mounted) return;
        setState(() {
          isDriver = _controller.isDriver;
        });
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
    isDriver = _controller.isDriver;
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.ensureLicenseIfMissing();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Driver and license ensuring logic moved into controller

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'My Profile',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Change Password',
            icon: const Icon(Icons.lock_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileChangePasswordScreen(userData: _user),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Blocked Users',
            icon: const Icon(Icons.block),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileBlockedUsersScreen(userData: _user),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await ApiService.logout();
              } catch (_) {}
              await NotificationService.onUserLogout();
              await AuthSession.clear();

              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
          tabs: [
            const Tab(text: 'General Info'),
            const Tab(text: 'Ride History'),
            const Tab(text: 'Vehicle Info'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ProfileGeneralInfoScreen(
            userData: _user,
          ),
          ProfileRideHistoryScreen(userData: _user),
          ProfileVehicleInfoScreen(userData: _user),
        ],
      ),
    );
  }
}