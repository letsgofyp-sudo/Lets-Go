import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/chat_service.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/chat_service.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ChatService'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bpoll\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bunsubscribeFromMessages\s*\(').hasMatch(source), isTrue);
    });
  });
}