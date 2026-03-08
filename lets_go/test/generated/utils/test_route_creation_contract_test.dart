import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/test_route_creation.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/test_route_creation.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RouteCreationUtils'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bcalculateDistance\s*\(').hasMatch(source), isTrue);
    });
  });
}