import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_posting_controllers/ride_view_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_posting_controllers/ride_view_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideViewController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcancelRide\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bfetchRoutePoints\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetCurrentLocation\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitializeWithRideData\s*\(').hasMatch(source), isTrue);
    });
  });
}