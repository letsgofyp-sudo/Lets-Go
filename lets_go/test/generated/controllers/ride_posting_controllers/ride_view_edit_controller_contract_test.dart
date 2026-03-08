import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_posting_controllers/ride_view_edit_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_posting_controllers/ride_view_edit_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RideViewEditController'), isTrue);
      expect(source.contains('class scope'), isTrue);
    });
  });
}