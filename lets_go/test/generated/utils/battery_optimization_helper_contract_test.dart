import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/battery_optimization_helper.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/battery_optimization_helper.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class BatteryOptimizationHelper'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\brequestIgnoreOptimizations\s*\(').hasMatch(source), isTrue);
    });
  });
}