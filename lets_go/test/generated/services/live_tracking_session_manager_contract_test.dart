import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/live_tracking_session_manager.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/live_tracking_session_manager.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class LiveTrackingSessionManager'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\breadPersistedSession\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\brestorePersistedSession\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bstopSession\s*\(').hasMatch(source), isTrue);
    });
  });
}