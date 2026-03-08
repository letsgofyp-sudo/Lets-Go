import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/signup_login_controllers/reset_password_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/signup_login_controllers/reset_password_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ResetPasswordController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btoggleObscureConfirmPassword\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btoggleObscurePassword\s*\(').hasMatch(source), isTrue);
    });
  });
}