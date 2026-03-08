import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_posting_controllers/my_rides_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_posting_controllers/my_rides_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class MyRidesController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcancelBooking\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcancelRide\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdeleteRide\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadUserRides\s*\(').hasMatch(source), isTrue);
    });
  });
}