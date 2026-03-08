import 'package:flutter/material.dart';
import 'create_route_screen.dart';
import '../../controllers/ride_posting_controllers/create_ride_controller.dart';

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

    // Trigger navigation through controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.navigateToRouteCreation(context, widget.userData);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}