import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/auth_session.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/auth_session.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class AuthSession'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bclear\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bload\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsave\s*\(').hasMatch(source), isTrue);
    });
  });
}