import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/signup_login_screens/reset_password_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/signup_login_screens/reset_password_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ResetPasswordScreen'), isTrue);
      expect(source.contains('class _ResetPasswordScreenState'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitState\s*\(').hasMatch(source), isTrue);
    });
  });
}