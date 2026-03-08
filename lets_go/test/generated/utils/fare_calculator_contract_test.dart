import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/fare_calculator.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/fare_calculator.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class FareCalculator'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bformatFare\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFareBreakdownText\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFareSummary\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFuelEfficiency\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFuelPrices\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateFuelPrices\s*\(').hasMatch(source), isTrue);
    });
  });
}