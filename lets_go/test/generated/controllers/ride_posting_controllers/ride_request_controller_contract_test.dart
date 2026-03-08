import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_posting_controllers/ride_request_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_posting_controllers/ride_request_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideRequestController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcalculateTotalFare\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcanAddFemaleSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcanAddMaleSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetBaseFare\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFinalPricePerSeat\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFormattedDepartureTime\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFormattedTripDate\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFromStopOptions\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetInterpolatedRoutePoints\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetIsPriceNegotiable\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetMaxPrice\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetMaxSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetMinPrice\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetOriginalPricePerSeat\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetRouteSummary\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetSavings\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetSelectedRouteSummary\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetToStopOptions\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetTotalSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitializeWithRideData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\brequestRideBooking\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateFemaleSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateFromStop\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateMaleSeats\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateProposedPrice\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateSpecialRequests\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateToStop\s*\(').hasMatch(source), isTrue);
    });
  });
}