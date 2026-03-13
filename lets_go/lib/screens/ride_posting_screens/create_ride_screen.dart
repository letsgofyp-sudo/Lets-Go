import 'package:flutter/material.dart';
import 'create_route_screen.dart';
import '../../controllers/ride_posting_controllers/create_ride_controller.dart';
import '../../services/api_service.dart';

class CreateRideScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const CreateRideScreen({
    super.key,
    required this.userData,
  });

  @override
  State<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends State<CreateRideScreen> {
  late CreateRideController _controller;

  bool _checking = true;
  String? _blockedMessage;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _controller = CreateRideController(
      onStateChanged: () {
        setState(() {});
      },
      onError: (message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
      onSuccess: (message) {
        // Navigate to CreateRouteScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CreateRouteScreen(
              userData: widget.userData,
            ),
          ),
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runGateAndNavigate();
    });
  }

  int _extractUserId() {
    return int.tryParse(widget.userData['id']?.toString() ?? '') ??
        int.tryParse(widget.userData['user_id']?.toString() ?? '') ??
        0;
  }

  Future<void> _runGateAndNavigate() async {
    final userId = _extractUserId();
    if (userId <= 0) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _blockedMessage = 'Missing user id.';
      });
      return;
    }

    try {
      final vehicles = await ApiService.getUserVehicles(userId);
      final verified = vehicles.where((v) {
        final st = (v['status'] ?? '').toString().trim().toUpperCase();
        return st == 'VERIFIED';
      }).toList();

      if (verified.isEmpty) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _blockedMessage = 'At least one verified vehicle is required to create a ride.';
        });
        return;
      }

      final vehicleId = int.tryParse(verified.first['id']?.toString() ?? '') ?? 0;
      if (vehicleId <= 0) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _blockedMessage = 'Unable to determine a verified vehicle.';
        });
        return;
      }

      final gate = await ApiService.getRideCreateGateStatus(
        userId: userId,
        vehicleId: vehicleId,
      );
      if (!mounted) return;
      if (gate['blocked'] == true) {
        setState(() {
          _checking = false;
          _blockedMessage = (gate['message'] ?? 'You are not eligible to create rides.').toString();
        });
        return;
      }

      setState(() {
        _checking = false;
        _blockedMessage = null;
      });
      _controller.navigateToRouteCreation(context, widget.userData);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _blockedMessage = 'Unable to check eligibility: ${e.toString()}';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_blockedMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Create Ride',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _blockedMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}