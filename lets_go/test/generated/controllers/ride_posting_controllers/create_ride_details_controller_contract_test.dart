import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_posting_controllers/create_ride_details_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_posting_controllers/create_ride_details_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideDetailsController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcalculateDistance\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcalculateDynamicFare\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcreateRide\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcreateRoute\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bfetchPlannedRouteOnRoads\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetCurrentLocation\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetRideData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetRouteData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitializeRouteData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadUserVehicles\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bselectVehicle\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetMapLoading\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetUseActualPath\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btogglePriceNegotiation\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateDescription\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateGenderPreference\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateSelectedDate\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateSelectedTime\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateSelectedVehicle\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateStopPrice\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateTotalPrice\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateTotalSeats\s*\(').hasMatch(source), isTrue);
    });
  });
}