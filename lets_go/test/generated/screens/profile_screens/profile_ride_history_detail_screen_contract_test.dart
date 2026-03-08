import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/screens/profile_screens/profile_ride_history_detail_screen.dart';
  final source = File(sourcePath).readAsStringSync();

  group('screens/profile_screens/profile_ride_history_detail_screen.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class ProfileRideHistoryDetailScreen'), isTrue);
      expect(source.contains('class _ProfileRideHistoryDetailScreenState'), isTrue);
    });
  });
}