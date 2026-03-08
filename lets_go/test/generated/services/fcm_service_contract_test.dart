import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/fcm_service.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/fcm_service.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class FCMService'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bfirebaseMessagingBackgroundHandler\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetDeviceToken\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitialize\s*\(').hasMatch(source), isTrue);
    });
  });
}