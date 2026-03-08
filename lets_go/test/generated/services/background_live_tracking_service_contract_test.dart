import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/background_live_tracking_service.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/background_live_tracking_service.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class BackgroundLiveTrackingService'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bclearSendEnabled\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdisableSendingAndStop\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bflushQueue\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitialize\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bisSendEnabled\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\breadSession\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsendOnce\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetSendEnabled\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstart\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstartStreamIfNeeded\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstop\s*\(').hasMatch(source), isTrue);
    });
  });
}