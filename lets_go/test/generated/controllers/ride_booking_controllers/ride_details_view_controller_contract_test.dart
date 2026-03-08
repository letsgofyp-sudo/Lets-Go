import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_booking_controllers/ride_details_view_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_booking_controllers/ride_details_view_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideDetailsViewController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetDriverInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFormattedDepartureTime\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFormattedTripDate\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetGenderPreferenceText\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetInterpolatedRoutePoints\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetPassengersInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripStatusColor\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripStatusText\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetVehicleInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bisRideBookable\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadRideDetails\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
    });
  });
}