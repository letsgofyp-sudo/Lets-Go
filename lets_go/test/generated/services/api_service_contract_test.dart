import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/api_service.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/api_service.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ApiService'), isTrue);
      expect(source.contains('class BookingService'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcancelRide\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bclearFareMatrixCache\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdeleteTrip\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdeleteVehicle\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetAvailableSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetCachedFareMatrix\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetEmergencyContact\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetLiveLocation\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetRideDetails\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetRouteStatistics\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripDetails\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripDetailsById\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetUserBookings\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetUserProfile\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetUserRides\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetUserVehicles\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetVehicleDetails\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetVerificationGateStatus\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\blogout\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bresolveTripShareTokenToTripId\s*\(').hasMatch(source), isTrue);
    });
  });
}