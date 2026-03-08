import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/post_bookings_controller/passenger_live_tracking_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/post_bookings_controller/passenger_live_tracking_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class PassengerLiveTrackingController'), isTrue);
    });
  });
}