import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/profile_screens/vehicle_detail_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/profile_screens/vehicle_detail_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class VehicleDetailScreen'), isTrue);
      expect(source.contains('class _VehicleDetailScreenState'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bhasMeaningfulData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binfoRow\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstatusColor\s*\(').hasMatch(source), isTrue);
    });
  });
}