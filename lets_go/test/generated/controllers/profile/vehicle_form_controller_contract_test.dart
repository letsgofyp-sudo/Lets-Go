import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/profile/vehicle_form_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/profile/vehicle_form_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class VehicleFormController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bdeleteVehicle\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsubmit\s*\(').hasMatch(source), isTrue);
    });
  });
}