import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/post_bookings_controller/live_tracking_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/post_bookings_controller/live_tracking_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class LiveTrackingController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bdetachUi\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgeneratePickupCode\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binit\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bpointForStopOrder\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\brefreshTripLayout\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetSelectedBookingId\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstartRide\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstopSendingLocation\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bverifyPickupCode\s*\(').hasMatch(source), isTrue);
    });
  });
}