import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:lets_go/controllers/ride_posting_controllers/create_route_controller.dart';

void main() {
  group('CreateRouteController.loadExistingRouteData', () {
    test('loads planned points, names, routePoints, and route metadata', () {
      final c = CreateRouteController();

      final points = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];
      final routePoints = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.05, 73.05), const LatLng(33.1, 73.1)];

      c.loadExistingRouteData({
        'points': points,
        'locationNames': ['A', 'B'],
        'routePoints': routePoints,
        'routeId': 'R1',
        'distance': 12.3,
        'duration': 25,
      });

      expect(c.points, points);
      expect(c.locationNames, ['A', 'B']);
      expect(c.routePoints, routePoints);
      expect(c.createdRouteId, 'R1');
      expect(c.routeDistance, 12.3);
      expect(c.routeDuration, 25);
    });

    test('loads actualRoutePoints overlay and preferActualPath flag', () {
      final c = CreateRouteController();

      final actual = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];

      c.loadExistingRouteData({
        'points': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'locationNames': ['A', 'B'],
        'routePoints': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'actualRoutePoints': actual,
        'preferActualPath': true,
      });

      expect(c.actualRoutePoints, actual);
      expect(c.preferActualPath, isTrue);
    });
  });

  group('CreateRouteController overlay is read-only during planned-route edits', () {
    test('adding/deleting/renaming stops does not mutate actualRoutePoints', () {
      final c = CreateRouteController();

      final actual = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];

      c.loadExistingRouteData({
        'points': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'locationNames': ['A', 'B'],
        'routePoints': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'actualRoutePoints': actual,
        'preferActualPath': true,
      });

      // Planned stop edits
      c.addPointToRoute(const LatLng(33.2, 73.2), 'C');
      c.updateStopName(0, 'A1');
      c.deleteStop(1);

      expect(c.actualRoutePoints, actual);
      expect(c.actualRoutePoints.length, 2);
    });
  });

  group('CreateRouteController.getRouteData', () {
    test('returns actualRoutePoints and preferActualPath to callers', () {
      final c = CreateRouteController();
      final actual = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];

      c.loadExistingRouteData({
        'points': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'locationNames': ['A', 'B'],
        'routePoints': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'actualRoutePoints': actual,
        'preferActualPath': true,
        'routeId': 'R1',
      });

      final data = c.getRouteData();
      expect(data['actualRoutePoints'], actual);
      expect(data['preferActualPath'], isTrue);
      expect(data['routeId'], 'R1');
    });
  });
}
