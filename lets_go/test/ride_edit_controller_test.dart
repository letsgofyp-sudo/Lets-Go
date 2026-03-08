import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:lets_go/controllers/ride_posting_controllers/ride_edit_controller.dart';

void main() {
  group('RideEditController.initializeWithRideData', () {
    test('parses actual_path into actualRoutePoints for overlay', () {
      final c = RideEditController();

      c.initializeWithRideData({
        'route': {
          'id': 1,
          'stops': [
            {'latitude': 33.0, 'longitude': 73.0, 'name': 'A'},
            {'latitude': 33.1, 'longitude': 73.1, 'name': 'B'},
          ],
        },
        'actual_path': [
          {'lat': 33.0, 'lng': 73.0},
          {'latitude': 33.1, 'longitude': 73.1},
        ],
        'notes': '',
      });

      expect(c.actualRoutePoints.length, 2);
      expect(c.actualRoutePoints.first, const LatLng(33.0, 73.0));
      expect(c.actualRoutePoints.last, const LatLng(33.1, 73.1));
    });

    test('keeps description empty when notes are empty (no stop-name auto-generation)', () {
      final c = RideEditController();

      c.initializeWithRideData({
        'route': {
          'id': 1,
          'stops': [
            {'latitude': 33.0, 'longitude': 73.0, 'name': 'A'},
            {'latitude': 33.1, 'longitude': 73.1, 'name': 'B'},
          ],
        },
        'notes': '',
      });

      expect(c.description, '');
    });
  });

  group('RideEditController.applyUpdatedRouteData', () {
    test('preserves actualRoutePoints when returned by route editor', () {
      final c = RideEditController();
      c.actualRoutePoints = [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];

      c.applyUpdatedRouteData({
        'points': [const LatLng(33.0, 73.0), const LatLng(33.2, 73.2)],
        'locationNames': ['A', 'C'],
        'routePoints': [const LatLng(33.0, 73.0), const LatLng(33.2, 73.2)],
        'actualRoutePoints': [const LatLng(30.0, 70.0), const LatLng(30.1, 70.1)],
        'routeId': '1',
        'distance': 1.0,
        'duration': 10,
      });

      expect(c.actualRoutePoints, [const LatLng(30.0, 70.0), const LatLng(30.1, 70.1)]);
    });

    test('does not wipe actualRoutePoints when route editor returns no actualRoutePoints', () {
      final c = RideEditController();
      c.actualRoutePoints = [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];

      c.applyUpdatedRouteData({
        'points': [const LatLng(33.0, 73.0), const LatLng(33.2, 73.2)],
        'locationNames': ['A', 'C'],
        'routePoints': [const LatLng(33.0, 73.0), const LatLng(33.2, 73.2)],
        'routeId': '1',
        'distance': 1.0,
        'duration': 10,
      });

      expect(c.actualRoutePoints, [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)]);
    });
  });
}
