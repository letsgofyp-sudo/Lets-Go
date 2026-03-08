import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/offline_location_queue.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/offline_location_queue.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class OfflineLocationQueue'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bclearAll\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcount\s*\(').hasMatch(source), isTrue);
    });
  });
}