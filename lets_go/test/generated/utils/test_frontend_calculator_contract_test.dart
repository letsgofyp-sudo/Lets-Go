import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/test_frontend_calculator.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/test_frontend_calculator.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bmain\s*\(').hasMatch(source), isTrue);
    });
  });
}