import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'create_route_screen.dart';
import '../../controllers/ride_posting_controllers/create_ride_details_controller.dart';
import '../../utils/auth_session.dart';
import '../../utils/map_util.dart';

class RideDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Map<String, dynamic> routeData;
  final bool recreateMode;
  final String? initialTripDate;
  final String? initialDepartureTime;
  final String? initialVehicleId;
  final int? initialTotalSeats;
  final String? initialGenderPreference;
  final String? initialNotes;
  final bool? initialIsNegotiable;
  final int? initialBaseFare;

  const RideDetailsScreen({
    super.key,
    required this.userData,
    required this.routeData,
    this.recreateMode = false,
    this.initialTripDate,
    this.initialDepartureTime,
    this.initialVehicleId,
    this.initialTotalSeats,
    this.initialGenderPreference,
    this.initialNotes,
    this.initialIsNegotiable,
    this.initialBaseFare,
  });

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  final MapController _mapController = MapController();
  late RideDetailsController _controller;

  bool _shownRecreateTimeAdjustedInfo = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _controller = RideDetailsController(
      onStateChanged: () {
        if (!mounted) return;
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
          if (message == 'navigate_to_my_rides') {
            // Navigate to MyRidesScreen
            Navigator.pushReplacementNamed(context, '/my-rides', arguments: widget.userData);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      },
      onInfo: (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.blue,
            ),
          );
        }
      },
    );

    _controller.recreateMode = widget.recreateMode;

    // Initialize controller with route data
    _controller.initializeRouteData(widget.routeData);

    if (widget.recreateMode) {
      // Apply prefilled values; only date/time should remain editable.
      bool adjusted = false;
      try {
        if ((widget.initialTripDate ?? '').toString().trim().isNotEmpty) {
          final dt = DateTime.tryParse(widget.initialTripDate!.toString());
          if (dt != null) {
            _controller.updateSelectedDate(dt);
          }
        }
      } catch (_) {}

      try {
        final raw = (widget.initialDepartureTime ?? '').toString();
        final parts = raw.split(':');
        if (parts.length >= 2) {
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          _controller.updateSelectedTime(TimeOfDay(hour: h, minute: m));
        }
      } catch (_) {}

      try {
        final now = DateTime.now();
        final requested = DateTime(
          _controller.selectedDate.year,
          _controller.selectedDate.month,
          _controller.selectedDate.day,
          _controller.selectedTime.hour,
          _controller.selectedTime.minute,
        );
        final minStart = now.add(const Duration(minutes: 15));
        if (requested.isBefore(minStart)) {
          final fallback = now.add(const Duration(minutes: 30));
          _controller.updateSelectedDate(DateTime(fallback.year, fallback.month, fallback.day));
          _controller.updateSelectedTime(TimeOfDay(hour: fallback.hour, minute: fallback.minute));
          adjusted = true;
        }
      } catch (_) {}

      if (widget.initialTotalSeats != null && (widget.initialTotalSeats ?? 0) > 0) {
        _controller.totalSeats = widget.initialTotalSeats!;
      }
      if ((widget.initialGenderPreference ?? '').toString().trim().isNotEmpty) {
        _controller.genderPreference = widget.initialGenderPreference;
      }
      if ((widget.initialNotes ?? '').toString().trim().isNotEmpty) {
        _controller.description = widget.initialNotes!.toString();
      }
      if (widget.initialIsNegotiable != null) {
        _controller.isPriceNegotiable = widget.initialIsNegotiable!;
      }
      if (widget.initialBaseFare != null && (widget.initialBaseFare ?? 0) > 0) {
        _controller.dynamicPricePerSeat = widget.initialBaseFare!;
      }

      // Defer vehicle selection until vehicles are loaded.
      _controller.prefilledVehicleId = widget.initialVehicleId;

      if (adjusted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_shownRecreateTimeAdjustedInfo) return;
          _shownRecreateTimeAdjustedInfo = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Recreate: date/time adjusted to a valid future time. You can change it before creating the ride.',
              ),
              backgroundColor: Colors.blue,
            ),
          );
        });
      }
    }

    _controller.getCurrentLocation();
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }
    int userId = toInt(widget.userData['id'])
        ?? toInt(widget.userData['user_id'])
        ?? toInt(widget.userData['user']?['id'])
        ?? toInt(widget.userData['profile']?['id'])
        ?? 0;
    debugPrint('[CREATE_RIDE_DETAILS] userData keys: ${widget.userData.keys.toList()}');
    debugPrint('[CREATE_RIDE_DETAILS] resolved userId: $userId');
    if (userId > 0) {
      _controller.loadUserVehicles(userId);
    } else {
      // Fallback: try to load from persisted AuthSession
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final session = await AuthSession.load();
        int? sessId;
        if (session != null) {
          sessId = toInt(session['id']) ?? toInt(session['user_id']);
        }
        debugPrint('[CREATE_RIDE_DETAILS] session userId: $sessId');
        if (mounted && (sessId ?? 0) > 0) {
          _controller.loadUserVehicles(sessId!);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Missing user id. Please re-login and try again.')),
          );
        }
      });
    }
    
    // Delay map loading and fare calculation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _controller.setMapLoading(false);
          // Do not call _fitMapToStops() here; wait for onMapReady to avoid controller errors
        }
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _controller.calculateDynamicFare();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  // Method to build the one-third map for ride details view
  Widget _buildOneThirdMap() {
    if (_controller.isMapLoading) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.33,
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    
    LatLng initialCenter;
    if (_controller.points.isNotEmpty) {
      double minLat = _controller.points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      double maxLat = _controller.points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      double minLng = _controller.points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      double maxLng = _controller.points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
      initialCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    } else {
      initialCenter = _controller.currentPosition ?? const LatLng(33.6844, 73.0479);
    }
    
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 13.0,
        onMapReady: () {
          if (_controller.points.isNotEmpty) {
            _fitMapToStops();
          }
        },
        onTap: (tapPosition, point) async {
          // Open full route editor in edit mode and wait for updated route data
          final updatedRoute = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (context) => CreateRouteScreen(
                userData: widget.userData,
                existingRouteData: {
                  'points': _controller.points,
                  'locationNames': _controller.locationNames,
                  'routePoints': _controller.routePoints,
                  'routeId': _controller.createdRouteId,
                  'distance': _controller.routeDistance,
                  'duration': _controller.routeDuration,
                  'actualRoutePoints': _controller.actualRoutePoints,
                  'preferActualPath': _controller.useActualPath,
                },
                routeEditMode: true,
              ),
            ),
          );

          if (!mounted) return;

          if (updatedRoute != null) {
            if (updatedRoute['actualRoutePoints'] == null) {
              updatedRoute['actualRoutePoints'] = _controller.actualRoutePoints;
            }
            if (updatedRoute['preferActualPath'] == null) {
              updatedRoute['preferActualPath'] = _controller.useActualPath;
            }
            // Re-initialize controller with the updated route and recalculate fare
            _controller.initializeRouteData(updatedRoute);
            _controller.calculateDynamicFare();
            setState(() {});
          }
        },
      ),
      children: [
        MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
        MarkerLayer(
          markers: [
            if (_controller.currentPosition != null)
              Marker(
                width: 40,
                height: 40,
                point: _controller.currentPosition!,
                child: const Icon(Icons.my_location, color: Colors.green, size: 40),
              ),
            ..._controller.points.asMap().entries.map((entry) {
              final index = entry.key;
              final point = entry.value;
              final locationName = index < _controller.locationNames.length ? _controller.locationNames[index] : null;
              return Marker(
                width: 40,
                height: 40,
                point: point,
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
                  ],
                ),
              );
            }),
          ],
        ),
        if (_controller.routePoints.isNotEmpty)
          MapUtil.buildPolylineLayerFromPolylines(
            polylines: [
              MapUtil.polyline(
                points: _controller.routePoints,
                color: Colors.blue,
                strokeWidth: 4,
              ),
            ],
          ),
      ],
    );
  }

  // Show price edit dialog with stop distribution
  void _showPriceEditDialog() {
    final TextEditingController priceController = TextEditingController(
      text: _controller.dynamicPricePerSeat.toString(),
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Total Price'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Total: ₨${_controller.dynamicPricePerSeat}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Stops: ${(_controller.fareCalculation['stop_breakdown'] as List<dynamic>? ?? []).length}'),
                    Text('Distance: ${_controller.fareCalculation['total_distance_km']?.toStringAsFixed(1) ?? 'N/A'} km'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New Total Price (PKR)',
                prefixText: '₨',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This will distribute the new total price across all stops proportionally.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
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
              final newPrice = int.tryParse(priceController.text.trim());
              if (newPrice != null && newPrice > 0) {
                _controller.updateTotalPrice(newPrice);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid price'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Update Total'),
          ),
        ],
      ),
    );
  }

  // Show comprehensive fare breakdown dialog with editable prices
  void _showFareBreakdownDialog() {
    if (_controller.fareCalculation.isEmpty) return;
    // Debug: dump current stop prices and totals at dialog open
    try {
      final stops = (_controller.fareCalculation['stop_breakdown'] as List<dynamic>? ?? [])
          .map((e) => (e as Map<String, dynamic>)['price'])
          .toList();
      debugPrint('[CREATE_SCREEN] Open Breakdown - stop prices=$stops total=${_controller.fareCalculation['total_price']} dyn=${_controller.dynamicPricePerSeat}');
    } catch (_) {}
    
    final breakdown = _controller.fareCalculation['calculation_breakdown'] as Map<String, dynamic>? ?? {};
    final stopBreakdown = _controller.fareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Route Summary & Pricing'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stopBreakdown.isNotEmpty) ...[
                Text(
                  'Individual Stop Breakdown',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...stopBreakdown.asMap().entries.map<Widget>((entry) {
                  final index = entry.key;
                  final stopData = entry.value as Map<String, dynamic>;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(
                        '${stopData['from_stop_name']} → ${stopData['to_stop_name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Distance: ${stopData['distance']?.toStringAsFixed(1) ?? 'N/A'} km'),
                          Text('Duration: ${stopData['duration'] ?? 'N/A'} minutes'),
                          Text(
                            'Price: ₨${stopData['price'] ?? 'N/A'}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showStopPriceEditDialog(index, stopData, fromBreakdownDialog: true),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
              
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Route Summary',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showPriceEditDialog(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Total Distance: ${breakdown['total_distance_km']?.toStringAsFixed(1) ?? 'N/A'} km'),
                      Text('Total Duration: ${breakdown['total_duration_minutes'] ?? 'N/A'} minutes'),
                      Text('Number of Stops: ${stopBreakdown.length + 1}'),
                      const Divider(),
                      Text(
                        'Total Price: ₨${breakdown['total_price'] ?? _controller.dynamicPricePerSeat}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Calculation Factors',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Base Rate: ₨${breakdown['base_rate_per_km']?.toStringAsFixed(2) ?? 'N/A'}/km'),
                      Text('Vehicle Multiplier: ${breakdown['vehicle_multiplier']?.toStringAsFixed(2) ?? 'N/A'}'),
                      Text('Time Multiplier: ${breakdown['time_multiplier']?.toStringAsFixed(2) ?? 'N/A'}'),
                      Text('Distance Factor: ${breakdown['distance_factor']?.toStringAsFixed(2) ?? 'N/A'}'),
                      if (breakdown['is_peak_hour'] == true)
                        const Text('Peak Hour: Yes (+20%)'),
                      Text('Fuel Type: ${breakdown['fuel_type'] ?? 'N/A'}'),
                      Text('Vehicle Type: ${breakdown['vehicle_type'] ?? 'N/A'}'),
                      Text('Total Seats: ${breakdown['total_seats'] ?? 'N/A'}'),
                      if (breakdown['bulk_discount_percentage'] != null && breakdown['bulk_discount_percentage'] > 0)
                        Text('Bulk Discount: ${breakdown['bulk_discount_percentage']?.toStringAsFixed(1) ?? 'N/A'}%'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Show individual stop price edit dialog
  void _showStopPriceEditDialog(int stopIndex, Map<String, dynamic> stopData, {bool fromBreakdownDialog = false}) {
    final TextEditingController priceController = TextEditingController(
      text: stopData['price']?.toString() ?? '0',
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Stop Price'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stopData['from_stop_name']} → ${stopData['to_stop_name']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Distance: ${stopData['distance']?.toStringAsFixed(1) ?? 'N/A'} km'),
                    Text('Duration: ${stopData['duration'] ?? 'N/A'} minutes'),
                    Text(
                      'Current Price: ₨${stopData['price'] ?? 'N/A'}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New Price (PKR)',
                prefixText: '₨',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: This will only change this stop\'s price and increase the total accordingly.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
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
              final newPrice = int.tryParse(priceController.text);
              if (newPrice != null && newPrice >= 0) {
                // update in controller and close
                final updated = _controller.fareCalculation['stop_breakdown'] as List<dynamic>? ?? [];
                if (stopIndex >= 0 && stopIndex < updated.length) {
                  final copy = List<Map<String, dynamic>>.from(
                    updated.map((e) => Map<String, dynamic>.from(e as Map)),
                  );
                  copy[stopIndex]['price'] = newPrice;
                  // Use controller helper to keep totals consistent
                  _controller.manualFareCalculation['stop_breakdown'] = copy;
                  _controller.updateTotalPrice(
                    copy.fold<int>(0, (s, e) => s + ((e['price'] as num?)?.toInt() ?? 0)),
                  );
                }
                Navigator.pop(context);
                if (fromBreakdownDialog) {
                  Navigator.pop(context);
                  // Reopen with updated state
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showFareBreakdownDialog();
                  });
                }
                // Debug: dump controller state after update
                try {
                  final stopsAfter = (_controller.fareCalculation['stop_breakdown'] as List<dynamic>? ?? [])
                      .map((e) => (e as Map<String, dynamic>)['price'])
                      .toList();
                  debugPrint('[CREATE_SCREEN] After Stop Update idx=$stopIndex new=$newPrice -> stop prices=$stopsAfter total=${_controller.fareCalculation['total_price']} dyn=${_controller.dynamicPricePerSeat}');
                } catch (_) {}
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid price'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Update Price'),
          ),
        ],
      ),
    );
  }

  // Show description dialog
  void _showDescriptionDialog() {
    final TextEditingController descController = TextEditingController(
      text: _controller.description,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Description'),
        content: TextField(
          controller: descController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'Enter ride description...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _controller.updateDescription(descController.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Build the ride details view with form and one-third map
  Widget _buildRideDetailsView() {
    // Map fitting is handled in onMapReady within _buildOneThirdMap
    
    return Column(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.33,
          child: _buildOneThirdMap(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ride Details',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Date and Time
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('Date'),
                        subtitle: Text(
                          DateFormat('MMM dd, yyyy').format(_controller.selectedDate),
                        ),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _controller.selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (date != null) {
                            _controller.updateSelectedDate(date);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text('Time'),
                        subtitle: Text(_controller.selectedTime.format(context)),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _controller.selectedTime,
                          );
                          if (time != null) {
                            _controller.updateSelectedTime(time);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                
                const Divider(),
                
                // Vehicle Selection
                ListTile(
                  leading: Builder(
                    builder: (_) {
                      if (_controller.selectedVehicle == null) {
                        return const Icon(Icons.directions_car);
                      }
                      final vehicle = _controller.userVehicles.firstWhere(
                        (v) => v['id']?.toString() == _controller.selectedVehicle,
                        orElse: () => const {},
                      );
                      final photoUrl = (vehicle['photo_front'] ?? '').toString();
                      if (photoUrl.isEmpty) {
                        return const Icon(Icons.directions_car);
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          photoUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.directions_car, color: Colors.grey),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.directions_car, color: Colors.grey),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  title: const Text('Vehicle'),
                  subtitle: Builder(
                    builder: (_) {
                      if (_controller.selectedVehicle == null) {
                        return const Text('Select a vehicle');
                      }
                      final vehicle = _controller.userVehicles.firstWhere(
                        (v) => v['id']?.toString() == _controller.selectedVehicle,
                        orElse: () => const {
                          'company_name': 'Unknown',
                          'model_number': '',
                          'plate_number': 'N/A',
                          'color': 'N/A',
                          'seats': 0,
                          'vehicle_type': 'FW',
                        },
                      );
                      final company = (vehicle['company_name'] ?? 'Unknown').toString();
                      final model = (vehicle['model_number'] ?? '').toString();
                      final plate = (vehicle['plate_number'] ?? 'N/A').toString();
                      final color = (vehicle['color'] ?? 'N/A').toString();
                      final seats = (vehicle['seats'] ?? 0).toString();
                      final typeCode = (vehicle['vehicle_type'] ?? 'FW').toString();
                      final type = typeCode == 'FW' ? 'Four Wheeler' : typeCode == 'TW' ? 'Two Wheeler' : typeCode;
                      return Text(
                        '$company $model\nPlate: $plate • Color: $color • Seats: $seats • $type',
                        maxLines: 3,
                        softWrap: true,
                      );
                    },
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Select Vehicle'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _controller.userVehicles.length,
                            itemBuilder: (context, index) {
                              final vehicle = _controller.userVehicles[index];
                              final photoUrl = vehicle['photo_front'];
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: photoUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          photoUrl,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[300],
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.directions_car,
                                                color: Colors.grey,
                                              ),
                                            );
                                          },
                                        ),
                                      )
                                    : Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.directions_car,
                                          color: Colors.grey,
                                        ),
                                      ),
                                  title: Text('${vehicle['company_name']} ${vehicle['model_number']}'),
                                  subtitle: Text(
                                    'Plate: ${vehicle['plate_number']} • Color: ${vehicle['color']} • Seats: ${vehicle['seats'] ?? 'N/A'}',
                                  ),
                                  onTap: () {
                                    _controller.selectVehicle(vehicle['id']?.toString() ?? '');
                                    Navigator.pop(context);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                
                const Divider(),
                
                // Seats and Gender Preference
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.airline_seat_recline_normal),
                        title: const Text('Available Seats'),
                        subtitle: Text('${_controller.totalSeats} seats'),
                        onTap: () {
                          final selectedVehicle = _controller.userVehicles.firstWhere(
                            (v) => v['id']?.toString() == _controller.selectedVehicle,
                            orElse: () => {'seats': 4},
                          );
                          final maxSeats = selectedVehicle['seats'] as int? ?? 4;
                          final availableSeats = maxSeats - 1;
                          
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Select Available Seats'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(availableSeats, (index) {
                                  final seats = index + 1;
                                  return ListTile(
                                    title: Text('$seats seat${seats > 1 ? 's' : ''}'),
                                    subtitle: Text('${maxSeats - seats} seat(s) for driver'),
                                    trailing: _controller.totalSeats == seats ? const Icon(Icons.check) : null,
                                    onTap: () {
                                      _controller.updateTotalSeats(seats);
                                      Navigator.pop(context);
                                    },
                                  );
                                }),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: const Text('Gender Preference'),
                        subtitle: Text(_controller.genderPreference ?? 'Any'),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Gender Preference'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _controller.genderOptions.map((gender) {
                                  return ListTile(
                                    title: Text(gender),
                                    trailing: _controller.genderPreference == gender ? const Icon(Icons.check) : null,
                                    onTap: () {
                                      _controller.updateGenderPreference(gender);
                                      Navigator.pop(context);
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                
                const Divider(),
                
                // Price Negotiation Section
                ListTile(
                  leading: const Icon(Icons.handshake, color: Colors.orange),
                  title: const Text('Allow Price Negotiation'),
                  subtitle: const Text('Let passengers negotiate the fare with you'),
                  trailing: Switch(
                    value: _controller.isPriceNegotiable,
                    onChanged: (value) {
                      _controller.togglePriceNegotiation(value);
                    },
                    activeThumbColor: Colors.orange,
                  ),
                ),

                if (_controller.hasActualPathAvailable) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.alt_route, color: Colors.blue),
                    title: const Text('Use Actual Path'),
                    subtitle: const Text('Toggle between planned route and actual traveled path'),
                    trailing: Switch(
                      value: _controller.useActualPath,
                      onChanged: (value) {
                        _controller.setUseActualPath(value);
                      },
                      activeThumbColor: Colors.blue,
                    ),
                  ),
                ],
                
                const Divider(),
                
                // Dynamic Total Price
                Card(
                  color: Colors.green[50],
                  child: ListTile(
                    leading: const Icon(Icons.attach_money, color: Colors.green),
                    title: const Text('Total Price'),
                    subtitle: Text(
                      '₨${_controller.dynamicPricePerSeat}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            _showFareBreakdownDialog();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {
                            _showPriceEditDialog();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const Divider(),
                
                // Description
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Description (Optional)'),
                  subtitle: Text(_controller.description.isEmpty ? 'Add a description' : _controller.description),
                  onTap: () {
                    _showDescriptionDialog();
                  },
                ),
                
                const SizedBox(height: 20),
                
                // Route Summary with Individual Stops
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Route Summary',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.info_outline),
                              onPressed: () => _showFareBreakdownDialog(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        if (_controller.fareCalculation['stop_breakdown'] != null) ...[
                          Text(
                            'Individual Stops:',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...(_controller.fareCalculation['stop_breakdown'] as List<dynamic>).asMap().entries.map<Widget>((entry) {
                            final index = entry.key;
                            final stopData = entry.value as Map<String, dynamic>;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${stopData['from_stop_name']} → ${stopData['to_stop_name']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 20),
                                          onPressed: () => _showStopPriceEditDialog(index, stopData),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Distance: ${stopData['distance']?.toStringAsFixed(1) ?? 'N/A'} km',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                            Text(
                                              'Duration: ${stopData['duration'] ?? 'N/A'} min',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '₨${(stopData['price'] as num?)?.round() ?? 'N/A'}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const Divider(),
                        ],
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total Distance: ${_controller.fareCalculation['total_distance_km']?.toStringAsFixed(1) ?? _controller.routeDistance?.toStringAsFixed(1) ?? 'N/A'} km'),
                                Text('Total Duration: ${_controller.fareCalculation['total_duration_minutes'] ?? _controller.routeDuration ?? 'N/A'} minutes'),
                                Text('Stops: ${_controller.locationNames.length}'),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Total Price:',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  '₨${(_controller.fareCalculation['total_price'] as num?)?.round() ?? _controller.dynamicPricePerSeat}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Route: ${_controller.locationNames.join(' → ')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Details'),
      ),
      body: _buildRideDetailsView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _controller.isSubmitting ? null : () => _controller.createRide(widget.userData),
        label: _controller.isSubmitting
            ? const Text('Creating...')
            : const Text('Create Ride'),
        icon: _controller.isSubmitting
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.check),
      ),
    );
  }
} 