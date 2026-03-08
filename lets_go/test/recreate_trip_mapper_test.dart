import 'package:flutter_test/flutter_test.dart';

import 'package:lets_go/utils/recreate_trip_mapper.dart';

void main() {
  group('RecreateTripMapper.normalizeRideBookingDetail', () {
    test('merges top-level route/vehicle/actual_path/route_points into trip', () {
      final detail = {
        'success': true,
        'trip': {
          'trip_id': 'T1',
          'trip_date': '2026-01-01',
        },
        'route': {
          'id': 10,
          'stops': [
            {'latitude': 33.0, 'longitude': 73.0, 'name': 'A'},
            {'latitude': 33.1, 'longitude': 73.1, 'name': 'B'},
          ],
        },
        'vehicle': {'id': 5},
        'actual_path': [
          {'lat': 33.0, 'lng': 73.0},
          {'lat': 33.1, 'lng': 73.1},
        ],
        'route_points': [
          {'lat': 33.0, 'lng': 73.0},
          {'lat': 33.05, 'lng': 73.05},
          {'lat': 33.1, 'lng': 73.1},
        ],
        'has_actual_path': true,
      };

      final trip = RecreateTripMapper.normalizeRideBookingDetail(detail);
      expect(trip['trip_id'], 'T1');
      expect(trip['route'], isA<Map<String, dynamic>>());
      expect(trip['vehicle'], isA<Map<String, dynamic>>());
      expect(trip['actual_path'], isA<List>());
      expect(trip['route_points'], isA<List>());
      expect(trip['has_actual_path'], isTrue);
    });

    test('returns empty map when payload has no trip and no trip-like keys', () {
      final trip = RecreateTripMapper.normalizeRideBookingDetail({'success': false});
      expect(trip, isEmpty);
    });
  });

  group('RecreateTripMapper.buildRouteDataFromNormalizedTrip', () {
    test('builds routeData with planned polyline and densified actualRoutePoints', () {
      final trip = {
        'trip_id': 'T1',
        'route': {
          'id': 10,
          'stops': [
            {'latitude': 33.0, 'longitude': 73.0, 'name': 'A'},
            {'latitude': 33.1, 'longitude': 73.1, 'name': 'B'},
          ],
        },
        'route_points': [
          {'lat': 33.0, 'lng': 73.0},
          {'lat': 33.1, 'lng': 73.1},
        ],
        'actual_path': [
          {'lat': 33.0, 'lng': 73.0},
          {'lat': 33.1, 'lng': 73.1},
        ],
      };

      final routeData = RecreateTripMapper.buildRouteDataFromNormalizedTrip(
        trip,
        preferActualPath: true,
      );

      expect(routeData, isNotNull);
      expect(routeData!['points'], isA<List>());
      expect((routeData['points'] as List).length, 2);
      expect(routeData['locationNames'], ['A', 'B']);
      expect(routeData['routePoints'], isA<List>());
      expect((routeData['routePoints'] as List).length, greaterThanOrEqualTo(2));
      expect(routeData['actualRoutePoints'], isA<List>());
      expect((routeData['actualRoutePoints'] as List).length, greaterThanOrEqualTo(2));
      expect(routeData['preferActualPath'], isTrue);
      expect(routeData['routeId'].toString(), '10');
    });

    test('returns null when stops are missing/invalid', () {
      final trip = {
        'trip_id': 'T1',
        'route': {'id': 10, 'stops': []},
      };

      final routeData = RecreateTripMapper.buildRouteDataFromNormalizedTrip(
        trip,
        preferActualPath: false,
      );

      expect(routeData, isNull);
    });
  });
}
