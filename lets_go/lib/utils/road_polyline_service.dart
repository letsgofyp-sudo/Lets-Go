import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';

class RoadPolylineService {
  static Future<List<LatLng>> _fetchOsrmRoadPolyline(
    List<LatLng> waypoints, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (waypoints.length < 2) return waypoints;
    try {
      final coordStr = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordStr?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = (data is Map) ? data['routes'] : null;
        if (routes is List && routes.isNotEmpty) {
          final first = routes.first;
          final geom = (first is Map) ? first['geometry'] : null;
          final coords = (geom is Map) ? geom['coordinates'] : null;
          if (coords is List && coords.isNotEmpty) {
            final pts = coords
                .whereType<List>()
                .where((c) => c.length >= 2 && c[0] is num && c[1] is num)
                .map<LatLng>(
                  (c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ),
                )
                .toList();
            if (pts.length >= 2) return pts;
          }
        }
      }
    } catch (_) {}

    return waypoints;
  }

  static Future<List<LatLng>> fetchRoadPolyline(
    List<LatLng> waypoints, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (waypoints.length < 2) return waypoints;

    final apiKey = orsApiKey.toString().trim();
    if (apiKey.isEmpty) {
      return _fetchOsrmRoadPolyline(waypoints, timeout: timeout);
    }

    try {
      final coords = waypoints.map((p) => [p.longitude, p.latitude]).toList();
      final url = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/driving-car/geojson',
      );

      final response = await http
          .post(
            url,
            headers: {
              'Authorization': apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'coordinates': coords}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['features'] is List && (data['features'] as List).isNotEmpty) {
          final first = (data['features'] as List).first;
          final geom = (first is Map) ? first['geometry'] : null;
          final routeCoords = (geom is Map) ? geom['coordinates'] : null;

          if (routeCoords is List && routeCoords.isNotEmpty) {
            final pts = routeCoords
                .whereType<List>()
                .where((c) => c.length >= 2 && c[0] is num && c[1] is num)
                .map<LatLng>(
                  (c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ),
                )
                .toList();

            if (pts.length >= 2) return pts;
          }
        }
      }
    } catch (_) {}

    return _fetchOsrmRoadPolyline(waypoints, timeout: timeout);
  }
}
