import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/profile/profile_contact_change_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/profile/profile_contact_change_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ProfileContactChangeController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bsendOtp\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bverifyOtp\s*\(').hasMatch(source), isTrue);
    });
  });
}