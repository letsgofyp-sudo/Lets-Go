import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/home_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/home_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class HomeScreen'), isTrue);
      expect(source.contains('class _HomeScreenState'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitOnce\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetModalState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsuggest\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btoDouble\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bvehicleThumbUrl\s*\(').hasMatch(source), isTrue);
    });
  });
}