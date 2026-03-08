import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/chat_screens/driver_chat_members_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/chat_screens/driver_chat_members_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class DriverChatMembersScreen'), isTrue);
      expect(source.contains('class _DriverChatMembersScreenState'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bbuild\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\binitState\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(source), isTrue);
    });
  });
}