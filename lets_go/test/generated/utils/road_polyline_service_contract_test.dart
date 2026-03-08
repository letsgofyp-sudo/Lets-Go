import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/utils/road_polyline_service.dart';
  final source = File(sourcePath).readAsStringSync();

  group('utils/road_polyline_service.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class RoadPolylineService'), isTrue);
    });
  });
}