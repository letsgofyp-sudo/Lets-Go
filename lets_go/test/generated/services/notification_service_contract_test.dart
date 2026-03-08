import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/notification_service.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/notification_service.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class NotificationService'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bfirebaseMessagingBackgroundHandler\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bhandleFcmBackgroundMessage\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bhandleNotificationResponse\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitialize\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bnotificationTapBackground\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bonUserLogout\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bparsePkr\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetNavigatorKey\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btrySyncGuestFcmTokenNow\s*\(').hasMatch(source), isTrue);
    });
  });
}