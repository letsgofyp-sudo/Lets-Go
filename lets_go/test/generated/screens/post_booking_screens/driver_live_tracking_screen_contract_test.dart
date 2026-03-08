import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/post_booking_screens/driver_live_tracking_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/post_booking_screens/driver_live_tracking_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class DriverLiveTrackingScreen'), isTrue);
      expect(source.contains('class _DriverLiveTrackingScreenState'), isTrue);
      expect(source.contains('class _LegendRow'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
    });
  });
}