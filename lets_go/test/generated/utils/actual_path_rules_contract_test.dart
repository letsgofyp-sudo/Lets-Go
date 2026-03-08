import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/actual_path_rules.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/actual_path_rules.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ActualPathRules'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bsameLatLng\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstartsWithStops\s*\(').hasMatch(source), isTrue);
    });
  });
}