import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/map_util.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/map_util.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class MapUtil'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bboundsFromPoints\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcalculateDistanceMeters\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcenterFromPoints\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgenerateInterpolatedRoute\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\broadPolylineOrFallback\s*\(').hasMatch(source), isTrue);
    });
  });
}