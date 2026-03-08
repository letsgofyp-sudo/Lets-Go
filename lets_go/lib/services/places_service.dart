import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class Place {
  final String id;
  final String name;
  final String displayName;
  final double lat;
  final double lon;
  final String type;
  final List<String> keywords;

  Place({
    required this.id,
    required this.name,
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.type,
    required this.keywords,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      displayName: json['display_name'] ?? '',
      lat: double.tryParse(json['lat'] ?? '') ?? 0.0,
      lon: double.tryParse(json['lon'] ?? '') ?? 0.0,
      type: json['type'] ?? '',
      keywords: List<String>.from(json['keywords'] ?? []),
    );
  }

  Map<String, dynamic> toSearchResult(LatLng? currentPosition) {
    double distance = double.infinity;
    if (currentPosition != null) {
      distance = _calculateDistance(currentPosition, LatLng(lat, lon));
    }

    return {
      'description': displayName,
      'placeId': 'local_$id',
      'mainText': name,
      'secondaryText': displayName,
      'name': name,
      'address': displayName,
      'lat': lat.toString(),
      'lon': lon.toString(),
      'distance': distance,
      'source': 'local',
      'type': type,
    };
  }

  // Calculate distance between two points using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double lat1Rad = point1.latitude * (pi / 180);
    final double lat2Rad = point2.latitude * (pi / 180);
    final double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    final double deltaLonRad = (point2.longitude - point1.longitude) * (pi / 180);

    final double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLonRad / 2) * sin(deltaLonRad / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }
}

class PlacesService {
  static List<Place> _places = [];
  static bool _isLoaded = false;

  // Load places from JSON file
  static Future<void> loadPlaces() async {
    if (_isLoaded) return;

    try {
      final String jsonString = await rootBundle.loadString('assets/data/pakistani_places.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final List<dynamic> placesList = jsonData['places'] ?? [];

      _places = placesList.map((json) => Place.fromJson(json)).toList();
      _isLoaded = true;
      
      debugPrint('Loaded ${_places.length} places from JSON file');
    } catch (e) {
      debugPrint('Error loading places from JSON: $e');
      _places = [];
    }
  }

  // Search places in local data
  static List<Map<String, dynamic>> searchLocalPlaces(String query, LatLng? currentPosition) {
    if (!_isLoaded) {
      debugPrint('Places not loaded yet');
      return [];
    }

    final queryLower = query.toLowerCase();
    final List<Map<String, dynamic>> results = [];

    for (final place in _places) {
      // Check if place matches query
      bool matches = false;
      
      // Check name
      if (place.name.toLowerCase().contains(queryLower)) {
        matches = true;
      }
      // Check display name
      else if (place.displayName.toLowerCase().contains(queryLower)) {
        matches = true;
      }
      // Check keywords
      else {
        for (final keyword in place.keywords) {
          if (keyword.toLowerCase().contains(queryLower)) {
            matches = true;
            break;
          }
        }
      }

      if (matches) {
        results.add(place.toSearchResult(currentPosition));
      }
    }

    // Sort by distance
    results.sort((a, b) {
      final aDistance = a['distance'] as double? ?? double.infinity;
      final bDistance = b['distance'] as double? ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });

    return results;
  }

  // Get all places (for debugging)
  static List<Place> getAllPlaces() {
    return List.from(_places);
  }

  // Get places by type
  static List<Place> getPlacesByType(String type) {
    return _places.where((place) => place.type == type).toList();
  }

  // Get place by ID
  static Place? getPlaceById(String id) {
    try {
      return _places.firstWhere((place) => place.id == id);
    } catch (e) {
      return null;
    }
  }
} 