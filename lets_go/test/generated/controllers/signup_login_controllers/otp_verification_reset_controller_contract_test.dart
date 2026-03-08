import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/signup_login_controllers/otp_verification_reset_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/signup_login_controllers/otp_verification_reset_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class OTPVerificationResetController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitExpiryFromArgs\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bresendOtp\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateExpiryTimer\s*\(').hasMatch(source), isTrue);
    });
  });
}