import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_booking_controllers/ride_booking_details_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_booking_controllers/ride_booking_details_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideBookingDetailsController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcalculateTotalFare\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bclearError\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdriverPhotoUrl\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetAvailableStops\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetBookingInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetDriverInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetEstimatedDuration\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFareInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFormattedDepartureTime\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFormattedTripDate\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFromStopOptions\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetGenderPreferenceText\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetMaxSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetMinSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetPassengersInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetPricePerSeat\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetSelectedRouteDistance\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetSelectedRouteSummary\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetStopBreakdown\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetToStopOptions\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripStatusColor\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTripStatusText\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetVehicleInfo\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bisRideBookable\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadRideDetails\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bplateNumber\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetError\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetLoading\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateFromStop\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateSpecialRequests\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateToStop\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bvehicleColor\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bvehicleCompanyModel\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bvehicleFrontPhotoUrl\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bvehicleType\s*\(').hasMatch(source), isTrue);
    });
  });
}