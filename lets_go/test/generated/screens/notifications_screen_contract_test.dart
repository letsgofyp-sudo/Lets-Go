import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/notifications_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/notifications_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });

    test('declares expected classes', () {
      expect(source.contains('class NotificationsScreen'), isTrue);
      expect(source.contains('class _NotificationsScreenState'), isTrue);
    });

    test('contains expected callable symbols', () {
      expect(RegExp(r'\b_load\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\b_markAllRead\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\b_dismiss\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\b_handleTap\s*\(').hasMatch(source), isTrue);
    });

    test('uses notifications ApiService methods', () {
      expect(source.contains('ApiService.listNotifications'), isTrue);
      expect(source.contains('ApiService.dismissNotification'), isTrue);
      expect(source.contains('ApiService.markAllNotificationsRead'), isTrue);
      expect(source.contains('ApiService.markNotificationRead'), isTrue);
    });
  });
}
