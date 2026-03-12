import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'create_ride_details_screen.dart';
import '../../controllers/ride_posting_controllers/create_route_controller.dart';
import '../../utils/auth_session.dart';
import '../../utils/map_util.dart';

class CreateRouteScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Map<String, dynamic>? existingRouteData;
  // When true, confirm will return updated route data back to caller instead of navigating to create ride
  final bool routeEditMode;
  final CreateRouteController? controllerOverride;
  final bool skipInitSideEffects;
  final TileLayer? tileLayerOverride;

  const CreateRouteScreen({
    super.key,
    required this.userData,
    this.existingRouteData,
    this.routeEditMode = false,
    this.controllerOverride,
    this.skipInitSideEffects = false,
    this.tileLayerOverride,
  });

  @override
  State<CreateRouteScreen> createState() => _CreateRouteScreenState();
}

class _CreateRouteScreenState extends State<CreateRouteScreen> {
  final MapController _mapController = MapController();
  late CreateRouteController _controller;
  
  // Text editing controllers
  final TextEditingController _stopNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _controller = widget.controllerOverride ??
        CreateRouteController(
          onStateChanged: () {
            setState(() {});
          },
          onError: (message) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            }
          },
          onSuccess: (message) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
        );

    // If controller was injected (tests), ensure callbacks are wired.
    if (widget.controllerOverride != null) {
      _controller.onStateChanged = () {
        if (mounted) setState(() {});
      };
      _controller.onError = (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      };
      _controller.onSuccess = (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
      };
    }

    // Initialize controller with existing data
    _controller.loadExistingRouteData(widget.existingRouteData);

    if (!widget.skipInitSideEffects) {
      _controller.getCurrentLocation();
      _controller.loadPlacesData();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _stopNameController.dispose();
    super.dispose();
  }

  // Method to delete stop
  void _deleteStop(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Stop'),
        content: Text('Are you sure you want to delete ${_controller.locationNames.isNotEmpty && index < _controller.locationNames.length ? _controller.locationNames[index] : 'Stop ${index + 1}'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _controller.deleteStop(index);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Method to handle map tap for route editing
  void _onMapTap(TapPosition tapPosition, LatLng point) async {
    // If a place lookup is already in progress, ignore additional taps
    if (_controller.isSearchingPlace) {
      return;
    }
    await _controller.handleMapTap(point, context);
  }

  // Method to show stop edit dialog
  void _showStopEditDialog(int index, String? currentName) {
    _stopNameController.text = currentName ?? 'Stop ${index + 1}';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Stop ${index + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _stopNameController,
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
            onPressed: () {
              Navigator.of(context).pop();
              _deleteStop(index);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _controller.editStopName(index, _stopNameController.text.trim());
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // Method to build the full-screen map
  Widget _buildFullScreenMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _controller.currentPosition!,
            initialZoom: 15,
            onTap: (tapPosition, point) async {
              _onMapTap(tapPosition, point);
            },
          ),
          children: [
            widget.tileLayerOverride ??
                MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
            if (_controller.actualRoutePoints.length > 1 || _controller.routePoints.length > 1)
              MapUtil.buildPolylineLayerFromPolylines(
                polylines: [
                  if (_controller.actualRoutePoints.length > 1)
                    MapUtil.polyline(
                      points: _controller.actualRoutePoints,
                      color: Colors.grey,
                      strokeWidth: 5.0,
                    ),
                  if (_controller.routePoints.length > 1)
                    MapUtil.polyline(
                      points: _controller.routePoints,
                      color: Colors.blue,
                      strokeWidth: 4.0,
                    ),
                ],
              ),
            _buildMarkerLayer(),
          ],
        ),
        if (_controller.isSearchingPlace)
          Positioned.fill(
            child: Container(
              color: Colors.black.withAlpha(64),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }

  // Method to build the marker layer
  Widget _buildMarkerLayer() {
    return MarkerLayer(
      markers: [
        // Current position marker
        if (_controller.currentPosition != null)
          Marker(
            width: 40,
            height: 40,
            point: _controller.currentPosition!,
            child: const Icon(Icons.my_location, color: Colors.green, size: 40),
          ),
        // Temporary highlight marker for selected search result
        if (_controller.tempHighlightPoint != null)
          Marker(
            width: 50,
            height: 50,
            point: _controller.tempHighlightPoint!,
            child: Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.location_on,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),
                if (_controller.tempHighlightName != null)
                  Positioned(
                    bottom: -25,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _controller.tempHighlightName!.length > 12 
                            ? '${_controller.tempHighlightName!.substring(0, 12)}...' 
                            : _controller.tempHighlightName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // Route points markers
        ..._controller.points.asMap().entries.map((entry) {
          final index = entry.key;
          final point = entry.value;
          final locationName = index < _controller.locationNames.length ? _controller.locationNames[index] : null;
          
          return Marker(
            width: 40,
            height: 40,
            point: point,
            child: GestureDetector(
              onTap: () {
                _showStopEditDialog(index, locationName);
              },
              child: Stack(
                children: [
                  Icon(
                    index == 0 ? Icons.trip_origin : 
                    index == _controller.points.length - 1 ? Icons.place : Icons.location_on,
                    color: index == 0 ? Colors.green : 
                           index == _controller.points.length - 1 ? Colors.red : Colors.orange,
                    size: 40,
                  ),
                  if (locationName != null)
                    Positioned(
                      bottom: -2,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          locationName.length > 8 ? '${locationName.substring(0, 8)}...' : locationName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // Method to fit all stops in map view
  void _fitMapToStops() {
    if (_controller.points.isEmpty) return;
    
    if (_controller.points.length == 1) {
      _mapController.move(_controller.points.first, 15.0);
    } else {
      double minLat = _controller.points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      double maxLat = _controller.points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      double minLng = _controller.points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      double maxLng = _controller.points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
      
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      final center = LatLng(centerLat, centerLng);
      
      final latDiff = maxLat - minLat;
      final lngDiff = maxLng - minLng;
      final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
      
      double zoom = 15.0;
      if (maxDiff > 0.1) zoom = 10.0;
      if (maxDiff > 0.5) zoom = 8.0;
      if (maxDiff > 1.0) zoom = 6.0;
      if (maxDiff > 2.0) zoom = 4.0;
      
      _mapController.move(center, zoom);
    }
  }

  // Build search results widget
  Widget _buildSearchResults() {
    if (!_controller.showSearchResults || _controller.searchResults.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _controller.searchResults.length,
        itemBuilder: (context, index) {
          final result = _controller.searchResults[index];
          return ListTile(
            leading: Icon(
              result['source'] == 'local' ? Icons.location_on : Icons.public,
              color: result['source'] == 'local' ? Colors.green : Colors.blue,
            ),
            title: Text(
              result['name'] ?? 'Unknown location',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result['address'] != null)
                  Text(
                    result['address']!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (result['distance'] != null)
                  Text(
                    '${result['distance']!.toStringAsFixed(1)} km away',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
            onTap: () {
              _controller.selectSearchResult(result, _mapController);
            },
          );
        },
      ),
    );
  }

  // Build the main content
  Widget _buildMainContent() {
    if (_controller.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        _buildFullScreenMap(),
        // Search bar at the top
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search for places...',
                        border: InputBorder.none,
                        suffixIcon: _controller.isSearching
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                      ),
                      onChanged: (query) {
                        _controller.searchPlaces(query);
                      },
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _controller.clearSearch();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        // Search results
        if (_controller.showSearchResults)
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            left: 16,
            right: 16,
            child: SizedBox(
              height: 300,
              child: _buildSearchResults(),
            ),
          ),
        // Bottom action buttons
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _controller.points.length >= 2
                      ? () async {
                          // Create/Update route first
                          final routeResult = await _controller.createRoute();
                          if (!mounted) return;
                          if (routeResult['success']) {
                            // Treat presence of existingRouteData as edit session too
                            final bool isEditSession = widget.routeEditMode || (widget.existingRouteData != null);
                            if (isEditSession) {
                              // Return updated route back to caller
                              Navigator.pop(context, {
                                'points': _controller.points,
                                'locationNames': _controller.locationNames,
                                'routePoints': _controller.routePoints,
                                'actualRoutePoints': _controller.actualRoutePoints,
                                'preferActualPath': _controller.preferActualPath,
                                'routeId': _controller.createdRouteId,
                                'distance': _controller.routeDistance,
                                'duration': _controller.routeDuration,
                              });
                            } else {
                              // Proceed to ride details creation (ensure user id is present)
                              int? toInt(dynamic v) {
                                if (v == null) return null;
                                if (v is int) return v;
                                return int.tryParse(v.toString());
                              }
                              Map<String, dynamic> enrichedUser = Map<String, dynamic>.from(widget.userData);
                              int userId = toInt(widget.userData['id'])
                                  ?? toInt(widget.userData['user_id'])
                                  ?? 0;
                              if (userId == 0) {
                                final session = await AuthSession.load();
                                if (!mounted) return;
                                if (session != null) {
                                  final sessId = toInt(session['id']) ?? toInt(session['user_id']);
                                  if (sessId != null && sessId > 0) {
                                    enrichedUser['id'] = sessId;
                                  }
                                }
                              }

                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RideDetailsScreen(
                                    userData: enrichedUser,
                                    routeData: {
                                      'points': _controller.points,
                                      'locationNames': _controller.locationNames,
                                      'routePoints': _controller.routePoints,
                                      'routeId': _controller.createdRouteId,
                                      'distance': _controller.routeDistance,
                                      'duration': _controller.routeDuration,
                                    },
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      : null,
                  icon: const Icon(Icons.check),
                  label: Text((widget.routeEditMode || (widget.existingRouteData != null)) ? 'Update Route' : 'Create Ride'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routeEditMode ? 'Edit Route' : 'Create Route'),
        actions: [
          if (_controller.points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.fit_screen),
              onPressed: _fitMapToStops,
              tooltip: 'Fit to stops',
            ),
        ],
      ),
      body: _buildMainContent(),
    );
  }
}