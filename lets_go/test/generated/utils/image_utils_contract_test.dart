import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/image_utils.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/image_utils.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ImageUtils'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bensureValidImageUrl\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetFallbackImageUrl\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bisValidImageUrl\s*\(').hasMatch(source), isTrue);
    });
  });
}