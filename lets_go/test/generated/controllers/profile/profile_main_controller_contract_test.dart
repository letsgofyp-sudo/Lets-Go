import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/profile/profile_main_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/profile/profile_main_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ProfileMainController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bensureLicenseIfMissing\s*\(').hasMatch(source), isTrue);
    });
  });
}