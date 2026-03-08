import 'package:flutter/material.dart';
import 'profile_main_screen.dart';

class ProfileScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const ProfileScreen({
    super.key,
    required this.userData,
  });

  @override
  Widget build(BuildContext context) {
    return ProfileMainScreen(userData: userData);
  }
}