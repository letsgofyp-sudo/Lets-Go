import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/signup_login_controllers/signup_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/signup_login_controllers/signup_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class SignupController'), isTrue);
    });
  });
}