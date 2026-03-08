import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:lets_go/controllers/ride_posting_controllers/create_ride_details_controller.dart';

void main() {
  group('RideDetailsController recreation toggle behavior', () {
    test('initializeRouteData uses planned routePoints by default', () {
      final c = RideDetailsController(enableRoadSnapping: false);

      final points = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];
      final planned = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.05, 73.05), const LatLng(33.1, 73.1)];
      final actual = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.02, 73.02), const LatLng(33.1, 73.1)];

      c.initializeRouteData({
        'points': points,
        'locationNames': ['A', 'B'],
        'routePoints': planned,
        'actualRoutePoints': actual,
        'preferActualPath': false,
      });

      expect(c.useActualPath, isFalse);
      expect(c.routePoints, planned);
      expect(c.plannedRoutePoints, planned);
      expect(c.actualRoutePoints, actual);
    });

    test('initializeRouteData uses actualRoutePoints when preferActualPath=true and actual is available', () {
      final c = RideDetailsController(enableRoadSnapping: false);

      final points = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];
      final planned = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];
      final actual = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.02, 73.02), const LatLng(33.1, 73.1)];

      c.initializeRouteData({
        'points': points,
        'locationNames': ['A', 'B'],
        'routePoints': planned,
        'actualRoutePoints': actual,
        'preferActualPath': true,
      });

      expect(c.useActualPath, isTrue);
      expect(c.routePoints, actual);
    });

    test('setUseActualPath(true) does not enable actual mode when actualRoutePoints are not available', () {
      final c = RideDetailsController(enableRoadSnapping: false);

      final points = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];
      final planned = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];

      c.initializeRouteData({
        'points': points,
        'locationNames': ['A', 'B'],
        'routePoints': planned,
        'actualRoutePoints': <LatLng>[],
        'preferActualPath': false,
      });

      c.setUseActualPath(true);

      expect(c.useActualPath, isFalse);
      expect(c.routePoints, planned);
    });
  });
}
