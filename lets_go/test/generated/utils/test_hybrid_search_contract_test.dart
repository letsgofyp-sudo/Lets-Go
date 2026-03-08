import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/test_hybrid_search.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/test_hybrid_search.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class HybridSearchTest'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\btestPlacesService\s*\(').hasMatch(source), isTrue);
    });
  });
}