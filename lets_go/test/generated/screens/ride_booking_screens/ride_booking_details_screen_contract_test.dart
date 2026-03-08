import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/ride_booking_screens/ride_booking_details_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/ride_booking_screens/ride_booking_details_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideBookingDetailsScreen'), isTrue);
      expect(source.contains('class _RideBookingDetailsScreenState'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bBuilder\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
    });
  });
}