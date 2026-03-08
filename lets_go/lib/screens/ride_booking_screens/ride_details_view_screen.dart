import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../controllers/ride_booking_controllers/ride_details_view_controller.dart';
import '../../utils/image_utils.dart';
import '../../utils/map_util.dart';

class RideDetailsViewScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String tripId;

  const RideDetailsViewScreen({
    super.key,
    required this.userData,
    required this.tripId,
  });

  @override
  State<RideDetailsViewScreen> createState() => _RideDetailsViewScreenState();
}

class _RideDetailsViewScreenState extends State<RideDetailsViewScreen> {
  final MapController _mapController = MapController();
  late RideDetailsViewController _controller;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _controller = RideDetailsViewController(
      onStateChanged: () {
        setState(() {});
      },
      onError: (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        }
      },
      onInfo: (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.blue),
          );
        }
      },
    );

    // Load ride details
    _controller.loadRideDetails(widget.tripId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Build the one-third map for ride details
  Widget _buildOneThirdMap() {
    if (_controller.isLoading || _controller.routePoints.isEmpty) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.33,
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final center = MapUtil.centerFromPoints(_controller.routePoints);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13.0,
        onMapReady: () {
          // Fit map to show all stops
          if (_controller.routePoints.isNotEmpty) {
            _fitMapToStops();
          }
        },
      ),
      children: [
        MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
        MarkerLayer(
          markers: _controller.stopPoints.asMap().entries.map((entry) {
            final index = entry.key;
            final point = entry.value;
            final locationName = index < _controller.locationNames.length
                ? _controller.locationNames[index]
                : null;
            return Marker(
              width: 40,
              height: 40,
              point: point,
              child: Stack(
                children: [
                  Icon(
                    index == 0
                        ? Icons.trip_origin
                        : index == _controller.stopPoints.length - 1
                        ? Icons.place
                        : Icons.location_on,
                    color: index == 0
                        ? Colors.green
                        : index == _controller.stopPoints.length - 1
                        ? Colors.red
                        : Colors.orange,
                    size: 40,
                  ),
                  if (locationName != null)
                    Positioned(
                      bottom: -2,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          locationName.length > 8
                              ? '${locationName.substring(0, 8)}...'
                              : locationName,
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
          }).toList(),
        ),
        // Draw route line
        if (_controller.routePoints.length > 1)
          MapUtil.buildPolylineLayerFromPolylines(
            polylines: [
              MapUtil.polyline(
                points: _controller.getInterpolatedRoutePoints(),
                color: Colors.blue,
                strokeWidth: 4,
              ),
            ],
          ),
      ],
    );
  }

  // Method to fit all stops in map view
  void _fitMapToStops() {
    if (_controller.routePoints.isEmpty) return;

    if (_controller.routePoints.length == 1) {
      _mapController.move(_controller.routePoints.first, 15.0);
    } else {
      double minLat = _controller.routePoints
          .map((p) => p.latitude)
          .reduce((a, b) => a < b ? a : b);
      double maxLat = _controller.routePoints
          .map((p) => p.latitude)
          .reduce((a, b) => a > b ? a : b);
      double minLng = _controller.routePoints
          .map((p) => p.longitude)
          .reduce((a, b) => a < b ? a : b);
      double maxLng = _controller.routePoints
          .map((p) => p.longitude)
          .reduce((a, b) => a > b ? a : b);

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

  // Build the ride details view
  Widget _buildRideDetailsView() {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _controller.errorMessage!,
              style: TextStyle(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _controller.loadRideDetails(widget.tripId),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with trip status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _controller.getTripStatusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _controller.getTripStatusColor()),
                ),
                child: Text(
                  _controller.getTripStatusText(),
                  style: TextStyle(
                    color: _controller.getTripStatusColor(),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.info_outline,
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                'Ride Details',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Trip Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trip Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.calendar_today,
                          title: 'Date',
                          subtitle: _controller.getFormattedTripDate(),
                        ),
                      ),
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.access_time,
                          title: 'Departure',
                          subtitle: _controller.getFormattedDepartureTime(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.airline_seat_recline_normal,
                          title: 'Available Seats',
                          subtitle: '${_controller.getTripInfo()['available_seats'] ?? 0} seats',
                        ),
                      ),
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.person,
                          title: 'Gender Preference',
                          subtitle: _controller.getGenderPreferenceText(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.attach_money,
                          title: 'Base Fare',
                          subtitle: '₨${(_controller.getTripInfo()['base_fare'] as num?)?.round() ?? 0}',
                        ),
                      ),
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.handshake,
                          title: 'Price Negotiable',
                          subtitle: _controller.getTripInfo()['is_negotiable'] == true ? 'Yes' : 'No',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Driver Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.teal.shade100,
                        backgroundImage: ImageUtils.isValidImageUrl(_controller.getDriverInfo()['profile_photo'])
                            ? NetworkImage(_controller.getDriverInfo()['profile_photo'])
                            : null,
                        child: !ImageUtils.isValidImageUrl(_controller.getDriverInfo()['profile_photo'])
                            ? Text(
                                (_controller.getDriverInfo()['name'] ?? 'D')[0].toUpperCase(),
                                style: TextStyle(
                                  color: Colors.teal.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _controller.getDriverInfo()['name'] ?? 'Unknown Driver',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${_controller.getDriverInfo()['driver_rating']?.toStringAsFixed(1) ?? '0.0'}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.person, color: Colors.grey, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  _controller.getDriverInfo()['gender'] ?? 'N/A',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Vehicle Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vehicle Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ImageUtils.isValidImageUrl(_controller.getVehicleInfo()['photo_front'])
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _controller.getVehicleInfo()['photo_front'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    final type = (_controller.getVehicleInfo()['type'] ?? '').toString().toUpperCase();
                                    final isTw = type.contains('TW') || type.contains('TWO');
                                    return Icon(
                                      isTw ? Icons.motorcycle : Icons.directions_car,
                                      size: 30,
                                      color: Colors.grey.shade600,
                                    );
                                  },
                                ),
                              )
                            : () {
                                final type = (_controller.getVehicleInfo()['type'] ?? '').toString().toUpperCase();
                                final isTw = type.contains('TW') || type.contains('TWO');
                                return Icon(
                                  isTw ? Icons.motorcycle : Icons.directions_car,
                                  size: 30,
                                  color: Colors.grey.shade600,
                                );
                              }(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_controller.getVehicleInfo()['company']} ${_controller.getVehicleInfo()['model']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _controller.getVehicleInfo()['type'] ?? 'N/A',
                                    style: TextStyle(
                                      color: Colors.blue.shade800,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_controller.getVehicleInfo()['seats']} seats',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if ((_controller.getVehicleInfo()['plate_number'] ?? _controller.getVehicleInfo()['plate_no'] ?? _controller.getVehicleInfo()['license_plate'] ?? _controller.getVehicleInfo()['plate'] ?? _controller.getVehicleInfo()['number_plate']) != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      (_controller.getVehicleInfo()['plate_number'] ?? _controller.getVehicleInfo()['plate_no'] ?? _controller.getVehicleInfo()['license_plate'] ?? _controller.getVehicleInfo()['plate'] ?? _controller.getVehicleInfo()['number_plate']).toString(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                if ((_controller.getVehicleInfo()['color'] ?? _controller.getVehicleInfo()['vehicle_color'] ?? _controller.getVehicleInfo()['colour']) != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      (_controller.getVehicleInfo()['color'] ?? _controller.getVehicleInfo()['vehicle_color'] ?? _controller.getVehicleInfo()['colour']).toString(),
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Route Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Route Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.route,
                          title: 'Route Name',
                          subtitle: _controller.rideData['route']?['name'] ?? 'Custom Route',
                        ),
                      ),
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.straighten,
                          title: 'Distance',
                          subtitle: '${_controller.routeDistance?.toStringAsFixed(1) ?? 'N/A'} km',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.timer,
                          title: 'Duration',
                          subtitle: '${_controller.routeDuration ?? 'N/A'} min',
                        ),
                      ),
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.location_on,
                          title: 'Stops',
                          subtitle: '${_controller.locationNames.length} stops',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Route: ${_controller.locationNames.join(' → ')}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Existing Passengers Card (if any)
          if (_controller.getPassengersInfo().isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Other Passengers',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._controller.getPassengersInfo().map((passenger) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey.shade200,
                            child: Text(
                              (passenger['name'] ?? 'P')[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  passenger['name'] ?? 'Unknown',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                Row(
                                  children: [
                                    Icon(Icons.star, color: Colors.amber, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${passenger['passenger_rating']?.toStringAsFixed(1) ?? '0.0'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(width: 16),
                                    Icon(Icons.person, color: Colors.grey, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      passenger['gender'] ?? 'N/A',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              () {
                                final total = (passenger['seats_booked'] as num?)?.toInt() ?? 1;
                                final male = (passenger['male_seats'] as num?)?.toInt() ?? 0;
                                final female = (passenger['female_seats'] as num?)?.toInt() ?? 0;
                                if ((male + female) > 0) {
                                  return '$total (M:$male F:$female) seat${total > 1 ? 's' : ''}';
                                }
                                return '$total seat${total > 1 ? 's' : ''}';
                              }(),
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Book This Ride Button
          if (_controller.isRideBookable()) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to ride request screen
                  Navigator.pushNamed(
                    context,
                    '/ride-request',
                    arguments: {
                      'userData': widget.userData,
                      'tripId': widget.tripId,
                      'rideData': _controller.rideData,
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Book This Ride',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ] else ...[
            // Ride not bookable
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This ride is not available for booking',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Helper method to build info tiles
  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
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
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.loadRideDetails(widget.tripId),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Top 1/3: Map View
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.33,
            child: _buildOneThirdMap(),
          ),
          // Bottom 2/3: Ride Details
          Expanded(child: _buildRideDetailsView()),
        ],
      ),
    );
  }
}
