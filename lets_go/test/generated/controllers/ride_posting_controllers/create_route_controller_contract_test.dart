import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sourcePath = 'lib/controllers/ride_posting_controllers/create_route_controller.dart';
  final source = File(sourcePath).readAsStringSync();

  group('controllers/ride_posting_controllers/create_route_controller.dart contract', () {
    test('source file is non-empty', () {
      expect(source.trim().isNotEmpty, isTrue);
    });
    test('declares expected classes', () {
      expect(source.contains('class CreateRouteController'), isTrue);
    });
    test('contains expected callable symbols', () {
      expect(RegExp(r'\bTimer\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\baddPointToRoute\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bbuildFullLabel\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcalculateDistance\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcalculateDistanceFromCurrent\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcalculateRouteMetrics\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bclearRoute\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bclearSearch\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bcreateRoute\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdeleteStop\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bdispose\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\beditStopName\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bfetchRoute\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bfindNearbyPlaceName\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetCurrentLocation\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetPlaceNameFromCoordinates\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bgetRouteData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bhandleMapTap\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadExistingRouteData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bloadPlacesData\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bpoiPriorityScore\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bremoveDuplicatesAndSort\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bsearchPlaces\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bselectSearchResult\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateRoute\s*\(').hasMatch(source), isTrue);
      expect(RegExp(r'\bupdateStopName\s*\(').hasMatch(source), isTrue);
    });
  });
}