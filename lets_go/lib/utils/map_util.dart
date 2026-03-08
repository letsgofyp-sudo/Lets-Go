import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

import 'road_polyline_service.dart';

class MapUtil {
  static const LatLng defaultFallbackCenter = LatLng(31.5204, 74.3587);

  static double calculateDistanceMeters(LatLng a, LatLng b) {
    const double earthRadius = 6371000;
    final double lat1Rad = a.latitude * (3.14159 / 180);
    final double lat2Rad = b.latitude * (3.14159 / 180);
    final double deltaLatRad = (b.latitude - a.latitude) * (3.14159 / 180);
    final double deltaLonRad = (b.longitude - a.longitude) * (3.14159 / 180);

    final double h = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) * math.sin(deltaLonRad / 2) * math.sin(deltaLonRad / 2);
    final double c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadius * c;
  }

  static List<LatLng> generateInterpolatedRoute(List<LatLng> stops) {
    if (stops.length < 2) return stops;

    final List<LatLng> interpolatedRoute = <LatLng>[];

    for (int i = 0; i < stops.length - 1; i++) {
      final start = stops[i];
      final end = stops[i + 1];

      // Add the start point
      interpolatedRoute.add(start);

      // Calculate distance between stops
      final distance = calculateDistanceMeters(start, end);

      // If distance is significant, add intermediate points
      if (distance > 1000) {
        final numPoints = (distance / 500).round();
        for (int j = 1; j < numPoints; j++) {
          final ratio = j / numPoints;
          final lat = start.latitude + (end.latitude - start.latitude) * ratio;
          final lng = start.longitude + (end.longitude - start.longitude) * ratio;

          // Add slight curve to simulate road path
          final curveOffset = 0.0001 * math.sin(ratio * 3.14159);
          interpolatedRoute.add(LatLng(lat + curveOffset, lng));
        }
      }

      // Add the end point (will be added again as start of next segment)
      if (i == stops.length - 2) {
        interpolatedRoute.add(end);
      }
    }

    return interpolatedRoute;
  }

  static List<LatLng> densifyBetween(
    LatLng a,
    LatLng b, {
    double maxStepMeters = 25,
  }) {
    if (maxStepMeters <= 0) return <LatLng>[b];
    final d = calculateDistanceMeters(a, b);
    if (!d.isFinite || d <= maxStepMeters) return <LatLng>[b];

    final steps = (d / maxStepMeters).ceil();
    final out = <LatLng>[];

    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final lat = a.latitude + (b.latitude - a.latitude) * t;
      final lng = a.longitude + (b.longitude - a.longitude) * t;
      out.add(LatLng(lat, lng));
    }

    return out;
  }

  static List<LatLng> densifyPolyline(
    List<LatLng> points, {
    double maxStepMeters = 25,
  }) {
    if (points.length < 2) return points;
    final out = <LatLng>[points.first];

    for (int i = 1; i < points.length; i++) {
      out.addAll(
        densifyBetween(
          points[i - 1],
          points[i],
          maxStepMeters: maxStepMeters,
        ),
      );
    }

    return out;
  }

  static TileLayer buildDefaultTileLayer({
    String? userAgentPackageName,
  }) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: userAgentPackageName ?? 'com.example.lets_go',
    );
  }

  static LatLng centerFromPoints(List<LatLng> points, {LatLng? fallback}) {
    if (points.isEmpty) return fallback ?? defaultFallbackCenter;
    if (points.length == 1) return points.first;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  static LatLngBounds? boundsFromPoints(List<LatLng> points) {
    if (points.length < 2) return null;
    return LatLngBounds.fromPoints(points);
  }

  static void fitCameraToPoints(
    MapController mapController,
    List<LatLng> points, {
    EdgeInsets padding = const EdgeInsets.all(48),
    double singlePointZoom = 14,
  }) {
    if (points.isEmpty) return;

    if (points.length >= 2) {
      final bounds = LatLngBounds.fromPoints(points);
      mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: padding,
        ),
      );
    } else {
      mapController.move(points.first, singlePointZoom);
    }
  }

  static Future<List<LatLng>> roadPolylineOrFallback(List<LatLng> waypoints) async {
    final road = await RoadPolylineService.fetchRoadPolyline(waypoints);
    return road.length > 1 ? road : waypoints;
  }

  static PolylineLayer buildPolylineLayer({
    required List<LatLng> points,
    Color color = Colors.teal,
    double strokeWidth = 4,
  }) {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: points,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ],
    );
  }

  static Polyline polyline({
    required List<LatLng> points,
    required Color color,
    required double strokeWidth,
  }) {
    return Polyline(
      points: points,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  static PolylineLayer buildPolylineLayerFromPolylines({
    required List<Polyline> polylines,
  }) {
    return PolylineLayer(polylines: polylines);
  }
}
