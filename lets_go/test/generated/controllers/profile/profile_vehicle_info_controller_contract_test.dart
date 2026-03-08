import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/profile/profile_vehicle_info_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/profile/profile_vehicle_info_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ProfileVehicleInfoController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcomputeDriverByLicenseOnly\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bensureVehicleDetails\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetLicenseImages\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bhydrateUser\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\blicenseNumber\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadVehicles\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\buserImg\s*\(').hasMatch(source), isTrue);
    });
  });
}