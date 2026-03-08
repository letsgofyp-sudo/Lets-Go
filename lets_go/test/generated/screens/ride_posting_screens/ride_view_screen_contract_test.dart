import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/ride_posting_screens/ride_view_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/ride_posting_screens/ride_view_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideViewScreen'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\basNum\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\basNumLocal\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bmk\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsumNum\s*\(').hasMatch(source), isTrue);
    });
  });
}