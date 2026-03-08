import 'package:latlong2/latlong.dart';

import 'map_util.dart';

class RecreateTripMapper {
  static Map<String, dynamic> normalizeRideBookingDetail(Map<String, dynamic> detail) {
    Map<String, dynamic> trip;

    if (detail['success'] == true && detail['trip'] is Map) {
      trip = Map<String, dynamic>.from(detail['trip'] as Map);
      if (!trip.containsKey('route') && detail['route'] is Map) {
        trip['route'] = Map<String, dynamic>.from(detail['route'] as Map);
      }
      if (!trip.containsKey('vehicle') && detail['vehicle'] is Map) {
        trip['vehicle'] = Map<String, dynamic>.from(detail['vehicle'] as Map);
      }
      if (!trip.containsKey('actual_path') && detail['actual_path'] is List) {
        trip['actual_path'] = List.from(detail['actual_path'] as List);
      }
      if (!trip.containsKey('route_points') && detail['route_points'] is List) {
        trip['route_points'] = List.from(detail['route_points'] as List);
      }
      if (!trip.containsKey('has_actual_path') && detail.containsKey('has_actual_path')) {
        trip['has_actual_path'] = detail['has_actual_path'];
      }
      return trip;
    }

    if (detail['trip_id'] != null || detail['route'] != null) {
      return Map<String, dynamic>.from(detail);
    }

    return <String, dynamic>{};
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static List<LatLng> parsePolylinePoints(dynamic raw) {
    if (raw is! List) return <LatLng>[];
    final out = <LatLng>[];
    for (final p in raw) {
      if (p is! Map) continue;
      final lat = _toDouble(p['lat'] ?? p['latitude']);
      final lng = _toDouble(p['lng'] ?? p['longitude']);
      if (lat != null && lng != null) {
        out.add(LatLng(lat, lng));
      }
    }
    return out;
  }

  static Map<String, dynamic>? buildRouteDataFromNormalizedTrip(
    Map<String, dynamic> trip, {
    required bool preferActualPath,
  }) {
    if (trip.isEmpty) return null;

    final route = (trip['route'] is Map) ? Map<String, dynamic>.from(trip['route'] as Map) : <String, dynamic>{};
    final stops = (route['stops'] is List)
        ? List<Map<String, dynamic>>.from((route['stops'] as List).whereType<Map>())
        : <Map<String, dynamic>>[];

    final points = <LatLng>[];
    final locationNames = <String>[];

    for (final s in stops) {
      final lat = _toDouble(s['latitude'] ?? s['lat']);
      final lng = _toDouble(s['longitude'] ?? s['lng']);
      final name = (s['name'] ?? s['stop_name'] ?? 'Stop').toString();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
        locationNames.add(name);
      }
    }

    if (points.length < 2) return null;

    final routeId = (route['id'] ?? route['route_id'])?.toString();

    final plannedRaw = trip['route_points'] ?? route['route_points'];
    final planned = parsePolylinePoints(plannedRaw);

    final actualRaw = trip['actual_path'];
    final actual = parsePolylinePoints(actualRaw);
    final actualDensified = actual.length >= 2
        ? MapUtil.densifyPolyline(actual, maxStepMeters: 25)
        : actual;

    return <String, dynamic>{
      'points': points,
      'locationNames': locationNames,
      'routePoints': planned.length >= 2 ? planned : points,
      'routeId': routeId,
      'distance': trip['total_distance_km'],
      'duration': trip['total_duration_minutes'],
      'actualRoutePoints': actualDensified,
      'preferActualPath': preferActualPath,
    };
  }
}
