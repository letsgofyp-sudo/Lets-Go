import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/debug_fare_calculator.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/debug_fare_calculator.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class DebugFareCalculator'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcompareWithBackend\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btestCalculationComponents\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btestFareConsistency\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btestFrontendCalculator\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btestHybridFareCalculation\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btestUserReportedIssue\s*\(').hasMatch(source), isTrue);
    });
  });
}