import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/recreate_trip_mapper.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/recreate_trip_mapper.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RecreateTripMapper'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bnormalizeRideBookingDetail\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bparsePolylinePoints\s*\(').hasMatch(source), isTrue);
    });
  });
}