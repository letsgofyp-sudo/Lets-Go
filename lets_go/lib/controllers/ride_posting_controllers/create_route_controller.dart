import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../services/places_service.dart';
import '../../utils/road_polyline_service.dart';
import '../../utils/map_util.dart';

class CreateRouteController {
  // State variables
  final List<LatLng> points = [];
  final List<String> locationNames = [];
  List<LatLng> routePoints = [];
  // Optional overlay for recreate-mode: actual traveled path.
  // This is for visualization only; edits operate on stops + planned routePoints.
  List<LatLng> actualRoutePoints = [];
  bool preferActualPath = false;
  LatLng? currentPosition;
  bool isLoading = true;
  bool isSearchingPlace = false;
  bool isSearching = false;
  List<Map<String, dynamic>> searchResults = [];
  bool showSearchResults = false;
  
  // Route data
  String? createdRouteId;
  double? routeDistance;
  int? routeDuration;
  
  // Temporary highlight for selected location
  LatLng? tempHighlightPoint;
  String? tempHighlightName;
  
  // Debounce timer for search
  Timer? debounceTimer;
  
  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  Function(String)? onError;
  Function(String)? onSuccess;
  
  CreateRouteController({
    this.onStateChanged,
    this.onError,
    this.onSuccess,
  });

  void dispose() {
    debounceTimer?.cancel();
  }

  // Load existing route data
  void loadExistingRouteData(Map<String, dynamic>? existingRouteData) {
    if (existingRouteData != null) {
      final data = existingRouteData;
      
      // Load existing points
      if (data['points'] != null) {
        points.addAll(List<LatLng>.from(data['points']));
      }
      
      // Load existing location names
      if (data['locationNames'] != null) {
        locationNames.addAll(List<String>.from(data['locationNames']));
      }
      
      // Load existing route points
      if (data['routePoints'] != null) {
        routePoints.addAll(List<LatLng>.from(data['routePoints']));
      }

      // Optional: load actual traveled path overlay for recreate mode.
      final ap = data['actualRoutePoints'];
      if (ap is List) {
        try {
          actualRoutePoints = List<LatLng>.from(ap);
        } catch (_) {
          actualRoutePoints = [];
        }
      }
      preferActualPath = data['preferActualPath'] == true;

      // Load existing route data
      createdRouteId = data['routeId'];
      routeDistance = data['distance'];
      routeDuration = data['duration'];
      
      // Calculate distance and duration if not provided
      if (routeDistance == null || routeDuration == null) {
        calculateRouteMetrics();
      }
    }
  }

  // Load places data from JSON
  Future<void> loadPlacesData() async {
    await PlacesService.loadPlaces();
  }

  // Calculate route metrics
  void calculateRouteMetrics() {
    if (routePoints.isNotEmpty) {
      // Calculate distance from route points
      double totalDistance = 0.0;
      for (int i = 1; i < routePoints.length; i++) {
        totalDistance += calculateDistance(routePoints[i-1], routePoints[i]);
      }
      totalDistance = totalDistance / 1000; // Convert to kilometers
      
      // Estimate duration (assuming average speed of 50 km/h)
      int totalDuration = (totalDistance / 50 * 60).round(); // Convert to minutes
      
      routeDistance = totalDistance;
      routeDuration = totalDuration;
      onStateChanged?.call();
    }
  }

  // Calculate distance between two points in meters
  double calculateDistance(LatLng point1, LatLng point2) {
    return MapUtil.calculateDistanceMeters(point1, point2);
  }

  // Calculate distance from current position
  double calculateDistanceFromCurrent(double lat, double lon) {
    if (currentPosition == null) return double.infinity;
    try {
      return calculateDistance(currentPosition!, LatLng(lat, lon));
    } catch (e) {
      debugPrint('Error calculating distance: $e');
      return double.infinity;
    }
  }

  // Get current location
  Future<void> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        onError?.call('Location services are disabled');
        currentPosition = const LatLng(31.5204, 74.3587); // Default position (Lahore)
        isLoading = false;
        onStateChanged?.call();
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          onError?.call('Location permissions are denied');
          currentPosition = const LatLng(31.5204, 74.3587); // Default position
          isLoading = false;
          onStateChanged?.call();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        onError?.call('Location permissions are permanently denied');
        currentPosition = const LatLng(31.5204, 74.3587); // Default position
        isLoading = false;
        onStateChanged?.call();
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition();
      currentPosition = LatLng(position.latitude, position.longitude);
      isLoading = false;
      onStateChanged?.call();
    } catch (e) {
      onError?.call('Error getting location: $e');
      currentPosition = const LatLng(31.5204, 74.3587); // Default position
      isLoading = false;
      onStateChanged?.call();
    }
  }

  // Fetch road-following polyline from OpenRouteService
  Future<void> fetchRoute() async {
    if (points.length < 2) return;
    
    try {
      routePoints = await RoadPolylineService.fetchRoadPolyline(points);

      if (routePoints.length < 2) {
        routePoints = List<LatLng>.from(points);
      }

      // Calculate distance and duration after route is fetched
      calculateRouteMetrics();

      onStateChanged?.call();
    } catch (e) {
      routePoints = List<LatLng>.from(points);
      calculateRouteMetrics();
      onError?.call('Error fetching route: $e');
      onStateChanged?.call();
    }
  }

  // Update route after any changes
  void updateRoute() {
    debugPrint('updateRoute called with ${points.length} points');
    // Update route if we have at least 2 points
    if (points.length >= 2) {
      debugPrint('Calling fetchRoute()');
      fetchRoute();
    } else {
      debugPrint('Not enough points for route (need 2, have ${points.length})');
    }
  }

  // Add point to route
  void addPointToRoute(LatLng point, String locationName) {
    points.add(point);
    locationNames.add(locationName);
    onStateChanged?.call();
    
    // Auto-update route after adding new stop
    updateRoute();
  }

  // Delete stop from route
  void deleteStop(int index) {
    points.removeAt(index);
    if (index < locationNames.length) {
      locationNames.removeAt(index);
    }
    onStateChanged?.call();
    
    // Auto-update route after deletion
    updateRoute();
  }

  // Update stop name
  void updateStopName(int index, String newName) {
    if (locationNames.length <= index) {
      locationNames.addAll(List.filled(index - locationNames.length + 1, ''));
    }
    locationNames[index] = newName;
    onStateChanged?.call();
    
    // Auto-update route after editing
    updateRoute();
  }

  // Search places using hybrid approach
  Future<void> searchPlaces(String query) async {
    if (query.isEmpty) {
      searchResults.clear();
      showSearchResults = false;
      onStateChanged?.call();
      return;
    }

    isSearching = true;
    onStateChanged?.call();

    try {
      debugPrint('Searching for: $query');
      
      List<Map<String, dynamic>> results = [];
      
      // Strategy 1: Check local JSON data first (instant results)
      final localResults = PlacesService.searchLocalPlaces(query, currentPosition);
      if (localResults.isNotEmpty) {
        debugPrint('Found ${localResults.length} local results from JSON');
        results.addAll(localResults);
      }
      
      // Strategy 2: If no local results or few results, search internet
      if (localResults.isEmpty || localResults.length < 3) {
        debugPrint('Searching internet for: $query');
        
        // Try OpenStreetMap Nominatim (Free)
        try {
          final response = await http.get(
            Uri.parse(
              'https://nominatim.openstreetmap.org/search'
              '?q=${Uri.encodeComponent(query)}'
              '&format=json'
              '&limit=10'
              '&countrycodes=pk'
              '&addressdetails=1'
            ),
            headers: {
              'User-Agent': 'LetsGo/1.0 (https://github.com/your-app)',
              'Accept': 'application/json',
            },
          ).timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final data = json.decode(response.body) as List;
            debugPrint('Internet results: ${data.length} items found');
            
            final internetResults = data.map((item) {
              final lat = double.tryParse(item['lat'] ?? '') ?? 0.0;
              final lon = double.tryParse(item['lon'] ?? '') ?? 0.0;
              
              return {
                'description': item['display_name'] ?? '',
                'placeId': item['place_id']?.toString() ?? '',
                'mainText': item['name'] ?? item['display_name'] ?? '',
                'secondaryText': item['display_name'] ?? '',
                'name': item['name'] ?? item['display_name'] ?? '',
                'address': item['display_name'] ?? '',
                'lat': item['lat'] ?? '',
                'lon': item['lon'] ?? '',
                'distance': calculateDistanceFromCurrent(lat, lon),
                'source': 'internet',
              };
            }).toList();
            
            // Add internet results to existing local results
            results.addAll(internetResults);
          } else {
            debugPrint('Internet search failed with status: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('Internet search error: $e');
        }
        
        // Strategy 3: If still no results, try global search (without country restriction)
        if (results.isEmpty) {
          try {
            final response = await http.get(
              Uri.parse(
                'https://nominatim.openstreetmap.org/search'
                '?q=${Uri.encodeComponent(query)}'
                '&format=json'
                '&limit=10'
                '&addressdetails=1'
              ),
              headers: {
                'User-Agent': 'LetsGo/1.0 (https://github.com/your-app)',
                'Accept': 'application/json',
              },
            ).timeout(const Duration(seconds: 8));

            if (response.statusCode == 200) {
              final data = json.decode(response.body) as List;
              debugPrint('Global internet results: ${data.length} items found');
              
              final globalResults = data.map((item) {
                final lat = double.tryParse(item['lat'] ?? '') ?? 0.0;
                final lon = double.tryParse(item['lon'] ?? '') ?? 0.0;
                
                return {
                  'description': item['display_name'] ?? '',
                  'placeId': item['place_id']?.toString() ?? '',
                  'mainText': item['name'] ?? item['display_name'] ?? '',
                  'secondaryText': item['display_name'] ?? '',
                  'name': item['name'] ?? item['display_name'] ?? '',
                  'address': item['display_name'] ?? '',
                  'lat': item['lat'] ?? '',
                  'lon': item['lon'] ?? '',
                  'distance': calculateDistanceFromCurrent(lat, lon),
                  'source': 'internet_global',
                };
              }).toList();
              
              results.addAll(globalResults);
            }
          } catch (e) {
            debugPrint('Global internet search error: $e');
          }
        }
      }
      
      // Strategy 4: No generic suggestions - only return validated results
      if (results.isEmpty) {
        debugPrint('No valid results found for: $query');
      }

      // Remove duplicates and sort by distance and relevance
      results = removeDuplicatesAndSort(results);

      searchResults = results;
      showSearchResults = true;
      onStateChanged?.call();
      
      debugPrint('Final hybrid results: ${results.length} items');
      
    } catch (e) {
      debugPrint('Error in hybrid search: $e');
      // Fallback to local data only
      final fallbackResults = PlacesService.searchLocalPlaces(query, currentPosition);
      searchResults = fallbackResults;
      showSearchResults = true;
      onStateChanged?.call();
    } finally {
      isSearching = false;
      onStateChanged?.call();
    }
  }

  // Remove duplicates and sort results
  List<Map<String, dynamic>> removeDuplicatesAndSort(List<Map<String, dynamic>> results) {
    // Remove duplicates based on placeId
    final Map<String, Map<String, dynamic>> uniqueResults = {};
    for (final result in results) {
      final placeId = result['placeId'] as String? ?? '';
      if (!uniqueResults.containsKey(placeId)) {
        uniqueResults[placeId] = result;
      }
    }
    
    final List<Map<String, dynamic>> uniqueList = uniqueResults.values.toList();
    
    // Sort by distance, then by source priority, then by relevance
    uniqueList.sort((a, b) {
      final aDistance = a['distance'] as double? ?? double.infinity;
      final bDistance = b['distance'] as double? ?? double.infinity;
      
      // First sort by distance (closer first)
      if (aDistance != bDistance) {
        return aDistance.compareTo(bDistance);
      }
      
      // Then by source priority (local > internet > internet_global)
      final aSource = a['source'] as String? ?? '';
      final bSource = b['source'] as String? ?? '';
      if (aSource != bSource) {
        if (aSource == 'local') return -1;
        if (bSource == 'local') return 1;
        if (aSource == 'internet') return -1;
        if (bSource == 'internet') return 1;
        if (aSource == 'internet_global') return -1;
        if (bSource == 'internet_global') return 1;
      }
      
      return 0;
    });
    
    return uniqueList;
  }

  // Get place name from coordinates using reverse geocoding
  Future<String?> getPlaceNameFromCoordinates(LatLng point) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?'
        'lat=${point.latitude}&lon=${point.longitude}&'
        'format=json&zoom=18&addressdetails=1'
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'LetsGo/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Try to get the most specific name available
        String? placeName;
        
        // Check for house number and road name
        if (data['address'] != null) {
          final address = data['address'] as Map<String, dynamic>;
          
          // Try house number + road name
          if (address['house_number'] != null && address['road'] != null) {
            placeName = '${address['house_number']} ${address['road']}';
          }
          // Try just road name
          else if (address['road'] != null) {
            placeName = address['road'];
          }
          // Try building name
          else if (address['building'] != null) {
            placeName = address['building'];
          }
          // Try amenity name
          else if (address['amenity'] != null) {
            placeName = address['amenity'];
          }
          // Try shop name
          else if (address['shop'] != null) {
            placeName = address['shop'];
          }
          // Try place name
          else if (address['place'] != null) {
            placeName = address['place'];
          }
        }
        
        // If no specific name found, use display name
        if (placeName == null && data['display_name'] != null) {
          final displayName = data['display_name'] as String;
          // Take the first part of the display name (usually the most specific)
          placeName = displayName.split(',')[0].trim();
        }
        
        return placeName;
      }
    } catch (e) {
      // Handle error silently
    }
    
    return null;
  }

  // Find nearby named places within 100 meters using Overpass API, fallback to Nominatim
  Future<String?> findNearbyPlaceName(LatLng point) async {
    try {
      // Overpass API query for all named features within 100m
      final overpassQuery = '''
        [out:json][timeout:25];
        (
          node(around:100,${point.latitude},${point.longitude})["name"];
          way(around:100,${point.latitude},${point.longitude})["name"];
          relation(around:100,${point.latitude},${point.longitude})["name"];
        );
        out center;
      ''';
      final overpassUrl = Uri.parse('https://overpass-api.de/api/interpreter');
      final overpassResponse = await http.post(
        overpassUrl,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'LetsGo/1.0',
        },
        body: overpassQuery,
      ).timeout(const Duration(seconds: 15));
      if (overpassResponse.statusCode == 200) {
        final overpassData = jsonDecode(overpassResponse.body);
        final elements = overpassData['elements'] as List<dynamic>;
        // Collect all named POIs
        final List<Map<String, dynamic>> pois = [];
        for (final element in elements) {
          Map<String, dynamic>? tags = element['tags'] as Map<String, dynamic>?;
          if (tags == null || tags['name'] == null) continue;
          // Always check both lat/lon and center for all elements
          List<LatLng> candidates = [];
          if (element['lat'] != null && element['lon'] != null) {
            candidates.add(LatLng((element['lat'] as num).toDouble(), (element['lon'] as num).toDouble()));
          }
          if (element['center'] != null && element['center']['lat'] != null && element['center']['lon'] != null) {
            candidates.add(LatLng((element['center']['lat'] as num).toDouble(), (element['center']['lon'] as num).toDouble()));
          }
          for (final placePoint in candidates) {
            final distance = calculateDistance(point, placePoint);
            if (distance > 100) continue;
            final label = buildFullLabel(tags);
            pois.add({
              'name': label,
              'distance': distance,
              'tags': tags,
              'type': element['type'] ?? '',
            });
          }
        }
        // Prefer parks/amenities, then by distance, then by type specificity
        pois.sort((a, b) {
          final aTags = a['tags'] as Map<String, dynamic>;
          final bTags = b['tags'] as Map<String, dynamic>;
          int aScore = poiPriorityScore(aTags);
          int bScore = poiPriorityScore(bTags);
          if (aScore != bScore) return bScore - aScore;
          int distComp = (a['distance'] as double).compareTo(b['distance'] as double);
          if (distComp != 0) return distComp;
          // Prefer node over way over relation if all else equal
          const typeOrder = {'node': 3, 'way': 2, 'relation': 1};
          int aType = typeOrder[a['type']] ?? 0;
          int bType = typeOrder[b['type']] ?? 0;
          return bType - aType;
        });
        if (pois.isNotEmpty) {
          return pois.first['name'] as String;
        }
      }
    } catch (e) {
      // Swallow error
    }
    // Fallback: Nominatim reverse geocoding
    return await getPlaceNameFromCoordinates(point);
  }

  // Helper to build a full label from Overpass tags
  String buildFullLabel(Map<String, dynamic> tags) {
    final name = tags['name']?.toString() ?? '';
    final type = tags['leisure'] ?? tags['amenity'] ?? tags['shop'] ?? tags['tourism'] ?? tags['building'];
    final city = tags['addr:city'] ?? tags['is_in:city'];
    final state = tags['addr:state'] ?? tags['is_in:state'];
    final country = tags['addr:country'] ?? tags['is_in:country'];
    final List<String> parts = [name];
    if (type != null && !name.toLowerCase().contains(type.toString().toLowerCase())) parts.add(type.toString());
    if (city != null) parts.add(city.toString());
    if (state != null) parts.add(state.toString());
    if (country != null) parts.add(country.toString());
    return parts.where((e) => e.toString().trim().isNotEmpty).join(', ');
  }

  // Helper to prioritize parks/amenities over generic buildings/roads
  int poiPriorityScore(Map<String, dynamic> tags) {
    if (tags['leisure'] != null && tags['leisure'].toString().toLowerCase().contains('park')) return 100;
    if (tags['amenity'] != null) return 90;
    if (tags['tourism'] != null) return 80;
    if (tags['shop'] != null) return 70;
    if (tags['building'] != null) return 60;
    return 10;
  }

  // Create route via API
  Future<Map<String, dynamic>> createRoute() async {
    if (points.length < 2) {
      return {'success': false, 'error': 'Please select at least origin and destination'};
    }

    try {
      // Calculate distance and duration from route points
      double totalDistance = 0.0;
      int totalDuration = 0;
      
      if (routePoints.isNotEmpty) {
        // Calculate distance from route points
        for (int i = 1; i < routePoints.length; i++) {
          totalDistance += calculateDistance(routePoints[i-1], routePoints[i]);
        }
        totalDistance = totalDistance / 1000; // Convert to kilometers
        
        // Estimate duration (assuming average speed of 50 km/h)
        totalDuration = (totalDistance / 50 * 60).round(); // Convert to minutes
      }

      final routeData = {
        'coordinates': points.map((p) => {
          'lat': p.latitude,
          'lng': p.longitude,
        }).toList(),
        'route_points': routePoints.map((p) => {
          'lat': p.latitude,
          'lng': p.longitude,
        }).toList(),
        'location_names': locationNames,
        'created_at': DateTime.now().toIso8601String(),
      };

      // Debug: Print route data being sent
      debugPrint('Sending route data: ${routeData.toString()}');

      final response = await ApiService.createRoute(routeData);
      
      debugPrint('API Response: ${response.toString()}');
      
      if (response['success'] == true) {
        createdRouteId = response['route']?['id']?.toString();
        routeDistance = response['route']?['distance']?.toDouble() ?? totalDistance;
        routeDuration = response['route']?['duration']?.toInt() ?? totalDuration;
        
        onSuccess?.call('Route created successfully! Distance: ${routeDistance?.toStringAsFixed(1)} km');
        return response;
      } else {
        // If API fails, use calculated values as fallback
        routeDistance = totalDistance;
        routeDuration = totalDuration;
        // Generate a temporary route ID for local use
        createdRouteId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        
        onSuccess?.call('Route created with calculated values. Distance: ${routeDistance?.toStringAsFixed(1)} km');
        return {
          'success': true,
          'route': {
            'id': createdRouteId,
            'distance': routeDistance,
            'duration': routeDuration,
          }
        };
      }
    } catch (e) {
      debugPrint('Error creating route: $e');
      
      // Use calculated values as fallback even on error
      double totalDistance = 0.0;
      int totalDuration = 0;
      
      if (routePoints.isNotEmpty) {
        for (int i = 1; i < routePoints.length; i++) {
          totalDistance += calculateDistance(routePoints[i-1], routePoints[i]);
        }
        totalDistance = totalDistance / 1000;
        totalDuration = (totalDistance / 50 * 60).round();
      }
      
      routeDistance = totalDistance;
      routeDuration = totalDuration;
      // Generate a temporary route ID for local use
      createdRouteId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      
      onSuccess?.call('Route created with fallback values. Distance: ${routeDistance?.toStringAsFixed(1)} km');
      return {
        'success': true,
        'route': {
          'id': createdRouteId,
          'distance': routeDistance,
          'duration': routeDuration,
        }
      };
    }
  }

  // Get route data for navigation
  Map<String, dynamic> getRouteData() {
    return {
      'points': points,
      'locationNames': locationNames,
      'routePoints': routePoints,
      'actualRoutePoints': actualRoutePoints,
      'preferActualPath': preferActualPath,
      'routeId': createdRouteId,
      'distance': routeDistance,
      'duration': routeDuration,
    };
  }

  // Clear all route data
  void clearRoute() {
    points.clear();
    locationNames.clear();
    routePoints.clear();
    createdRouteId = null;
    routeDistance = null;
    routeDuration = null;
    onStateChanged?.call();
  }

  // Clear search results
  void clearSearch() {
    searchResults.clear();
    showSearchResults = false;
    onStateChanged?.call();
  }

  // Handle map tap for adding stops
  Future<void> handleMapTap(LatLng point, BuildContext context) async {
    isSearchingPlace = true;
    onStateChanged?.call();

    try {
      // Get place name from coordinates
      final placeName = await findNearbyPlaceName(point);

      if (!context.mounted) return;

      // Show dialog to confirm/add stop name
      final stopName = await _showStopNameDialog(context, placeName ?? 'Stop ${points.length + 1}');
      
      if (stopName != null && stopName.isNotEmpty) {
        // Add point to route
        addPointToRoute(point, stopName);

        // Show temporary highlight
        tempHighlightPoint = point;
        tempHighlightName = stopName;
        onStateChanged?.call();

        // Clear highlight after 2 seconds
        Timer(const Duration(seconds: 2), () {
          tempHighlightPoint = null;
          tempHighlightName = null;
          onStateChanged?.call();
        });
      }

    } catch (e) {
      onError?.call('Error adding stop: $e');
    } finally {
      isSearchingPlace = false;
      onStateChanged?.call();
    }
  }

  // Show dialog to get stop name
  Future<String?> _showStopNameDialog(BuildContext context, String suggestedName) async {
    final TextEditingController nameController = TextEditingController(text: suggestedName);
    
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Stop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Stop Name',
                hintText: 'Enter stop name',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Add Stop'),
          ),
        ],
      ),
    );
  }

  // Select search result and add to route
  void selectSearchResult(Map<String, dynamic> result, MapController mapController) {
    final lat = double.tryParse(result['lat'] ?? '') ?? 0.0;
    final lon = double.tryParse(result['lon'] ?? '') ?? 0.0;
    
    if (lat == 0.0 && lon == 0.0) {
      onError?.call('Invalid coordinates for selected location');
      return;
    }

    final point = LatLng(lat, lon);
    final locationName = result['mainText'] ?? result['description'] ?? 'Stop ${points.length + 1}';

    // Add point to route
    addPointToRoute(point, locationName);

    // Clear search results
    searchResults.clear();
    showSearchResults = false;
    onStateChanged?.call();

    // Move map to the new point
    mapController.move(point, 15.0);

    // Show temporary highlight
    tempHighlightPoint = point;
    tempHighlightName = locationName;
    onStateChanged?.call();

    // Clear highlight after 2 seconds
    Timer(const Duration(seconds: 2), () {
      tempHighlightPoint = null;
      tempHighlightName = null;
      onStateChanged?.call();
    });
  }

  // Edit stop name
  void editStopName(int index, String newName) {
    updateStopName(index, newName);
  }
} 
