import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/signup_login_screens/register_pending_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/signup_login_screens/register_pending_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RegisterPendingScreen'), isTrue);
      expect(source.contains('class _RegisterPendingScreenState'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdidChangeDependencies\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bputEmergency\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bputPersonal\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
    });
  });
}