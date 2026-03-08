import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/services/places_service.dart';
  final source = File(sourcePath).readAsStringSync();

  group('services/places_service.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class Place'), isTrue);
      expect(source.contains('class PlacesService'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bgetAllPlaces\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetPlaceById\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetPlacesByType\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadPlaces\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsearchLocalPlaces\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\btoSearchResult\s*\(').hasMatch(source), isTrue);
    });
  });
}