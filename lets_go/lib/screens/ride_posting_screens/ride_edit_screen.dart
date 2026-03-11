import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import '../../controllers/ride_posting_controllers/ride_edit_controller.dart';
import '../../utils/map_util.dart';
import 'create_route_screen.dart';

class RideEditScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Map<String, dynamic> rideData;

  const RideEditScreen({super.key, required this.userData, required this.rideData});

  @override
  State<RideEditScreen> createState() => _RideEditScreenState();
}

class _RideEditScreenState extends State<RideEditScreen> {
  final MapController _mapController = MapController();
  late final RideEditController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RideEditController(
      onStateChanged: () => mounted ? setState(() {}) : null,
      onError: (m) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red)),
      onSuccess: (m) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(m), backgroundColor: Colors.green),
        );
        // After a short delay, navigate back to My Rides so the updated ride list is shown
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          Navigator.pushReplacementNamed(
            context,
            '/my-rides',
            arguments: widget.userData,
          );
        });
      },
      onInfo: (m) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m))),
    );
    _controller.initializeWithRideData(widget.rideData);
    _controller.getCurrentLocation();
    final userId = widget.userData['id'] as int?;
    if (userId != null) _controller.loadUserVehicles(userId);
  }

  void _fitMapToStops() {
    if (_controller.points.isEmpty) return;
    if (_controller.points.length == 1) {
      _mapController.move(_controller.points.first, 15.0);
      return;
    }
    double minLat = _controller.points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = _controller.points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = _controller.points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = _controller.points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final maxDiff = (maxLat - minLat) > (maxLng - minLng) ? (maxLat - minLat) : (maxLng - minLng);
    double zoom = 15.0;
    if (maxDiff > 0.1) zoom = 10.0;
    if (maxDiff > 0.5) zoom = 8.0;
    if (maxDiff > 1.0) zoom = 6.0;
    if (maxDiff > 2.0) zoom = 4.0;
    _mapController.move(center, zoom);
  }

  Future<void> _openRouteEditor() async {
    final updated = await Navigator.push(
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
            // Overlay-only: preserve actual_path from the original trip so the
            // user can see it while editing the planned route.
            'actualRoutePoints': _controller.actualRoutePoints,
          },
          routeEditMode: true,
        ),
      ),
    );
    if (updated is Map<String, dynamic>) {
      _controller.applyUpdatedRouteData(updated);
    }
  }

  void _showPriceEditDialog() {
    final ctrl = TextEditingController(
      text: (_controller.fareCalculation['total_price'] ?? _controller.dynamicPricePerSeat).toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Total Price'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'New Total Price (PKR)', prefixText: '₨'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final raw = ctrl.text.trim();
              if (raw.isEmpty || raw.contains('.')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid format. Enter an integer price (no decimals).'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              final sanitized = raw.replaceAll(RegExp(r'[^0-9]'), '');
              final v = int.tryParse(sanitized);
              if (v != null && v > 0) {
                _controller.updateTotalPrice(v.toDouble());
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid format. Enter an integer price (no decimals).'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
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
        onMapReady: _fitMapToStops,
        onTap: (tapPos, point) => _openRouteEditor(),
      ),
      children: [
        MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
        MarkerLayer(
          markers: [
            if (_controller.currentPosition != null)
              Marker(
                width: 36,
                height: 36,
                point: _controller.currentPosition!,
                child: const Icon(Icons.my_location, color: Colors.green, size: 36),
              ),
            ..._controller.points.asMap().entries.map((e) {
              final idx = e.key;
              final p = e.value;
              return Marker(
                width: 40,
                height: 40,
                point: p,
                child: Icon(
                  idx == 0
                      ? Icons.trip_origin
                      : idx == _controller.points.length - 1
                          ? Icons.place
                          : Icons.location_on,
                  color: idx == 0
                      ? Colors.green
                      : idx == _controller.points.length - 1
                          ? Colors.red
                          : Colors.orange,
                  size: 36,
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

  @override
  Widget build(BuildContext context) {
    final tripId = (widget.rideData['trip_id'] ?? widget.rideData['id'] ?? '').toString();
    // Robust fare payload support
    final Map<String, dynamic> fareCalc = (_controller.fareCalculation.isNotEmpty
            ? _controller.fareCalculation
            : (widget.rideData['fare_calculation'] as Map<String, dynamic>?)
                ?? (widget.rideData['fare_data'] as Map<String, dynamic>?)
                ?? <String, dynamic>{});
    final List<dynamic> stopBreakdown = (fareCalc['stop_breakdown'] as List<dynamic>?)
            ?? (widget.rideData['stop_breakdown'] as List<dynamic>?)
            ?? <dynamic>[];
    final num? totalDistanceKm = (fareCalc['total_distance_km'] as num?)
            ?? (fareCalc['calculation_breakdown'] is Map ? (fareCalc['calculation_breakdown']['total_distance_km'] as num?) : null);
    final int? totalDurationMin = (fareCalc['total_duration_minutes'] as int?)
            ?? (fareCalc['calculation_breakdown'] is Map ? (fareCalc['calculation_breakdown']['total_duration_minutes'] as int?) : null);
    final num totalPrice = (fareCalc['total_price'] as num?) ?? _controller.dynamicPricePerSeat;
    final bool isBusy = _controller.isUpdating || _controller.isCancelling;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Ride'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: _controller.isCancelling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.cancel),
            tooltip: 'Cancel Ride',
            onPressed: isBusy ? null : () => _controller.cancelRide(tripId),
          ),
          IconButton(
            icon: _controller.isUpdating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save),
            onPressed: isBusy ? null : () => _controller.updateRide(widget.userData, tripId),
            tooltip: 'Update Ride',
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.33,
                child: _buildMap(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(
                    children: [
                      const Icon(Icons.edit, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('Edit Ride', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Vehicle selector and negotiation toggle
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_car, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Vehicle', border: InputBorder.none),
                              isExpanded: true,
                              initialValue: _controller.selectedVehicle,
                              items: _controller.userVehicles
                                  .map<DropdownMenuItem<String>>((v) => DropdownMenuItem(
                                        value: v['id'].toString(),
                                        child: Text('${v['registration_number'] ?? 'Vehicle'} • ${v['vehicle_type'] ?? ''}'),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() => _controller.selectedVehicle = val);
                                _controller.calculateDynamicFare();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Negotiable'),
                              Switch(
                                value: _controller.isPriceNegotiable,
                                onChanged: (v) {
                                  setState(() => _controller.togglePriceNegotiation(v));
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Gender preference selector
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.transgender, color: Colors.purple),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Gender Preference', border: InputBorder.none),
                              isExpanded: true,
                              initialValue: _controller.genderPreference,
                              items: _controller.genderOptions
                                  .map<DropdownMenuItem<String>>((g) => DropdownMenuItem(
                                        value: g,
                                        child: Text(g),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() => _controller.genderPreference = val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          leading: const Icon(Icons.calendar_today, color: Colors.blue),
                          title: const Text('Date'),
                          subtitle: Text(DateFormat('MMM dd, yyyy').format(_controller.selectedDate)),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _controller.selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) {
                              setState(() => _controller.selectedDate = d);
                              _controller.calculateDynamicFare();
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          leading: const Icon(Icons.access_time, color: Colors.blue),
                          title: const Text('Time'),
                          subtitle: Text(_controller.selectedTime.format(context)),
                          onTap: () async {
                            final t = await showTimePicker(context: context, initialTime: _controller.selectedTime);
                            if (t != null) {
                              setState(() => _controller.selectedTime = t);
                              _controller.calculateDynamicFare();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Card(
                    color: Colors.green[50],
                    child: ListTile(
                      leading: const Icon(Icons.attach_money, color: Colors.green),
                      title: const Text('Total Price'),
                      subtitle: Text('₨${(totalPrice).toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                      trailing: IconButton(icon: const Icon(Icons.edit), onPressed: _showPriceEditDialog),
                    ),
                  ),
                  const Divider(),
                  // Route Summary and editable stop breakdown
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Route Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              TextButton.icon(onPressed: _openRouteEditor, icon: const Icon(Icons.map), label: const Text('Edit Route')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Stops: ${_controller.locationNames.length}'),
                                  const SizedBox(height: 4),
                                  Text('Gender Preference: ${_controller.genderPreference ?? 'Any'}'),
                                ],
                              ),
                              Flexible(
                                child: Text('Route: ${_controller.locationNames.join(' → ')}', style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis, maxLines: 2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (totalDistanceKm != null || totalDurationMin != null) ...[
                            Row(
                              children: [
                                if (totalDistanceKm != null) Text('Total Distance: ${totalDistanceKm.toStringAsFixed(1)} km'),
                                if (totalDistanceKm != null && totalDurationMin != null) const SizedBox(width: 12),
                                if (totalDurationMin != null) Text('Total Duration: $totalDurationMin min'),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (stopBreakdown.isNotEmpty) ...[
                            Text('Stop Breakdown', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ...List<Widget>.from((stopBreakdown.asMap().entries).map((entry) {
                              final idx = entry.key;
                              final m = entry.value as Map<String, dynamic>;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.route, size: 18, color: Colors.grey),
                                title: Text('${m['from_stop_name']} → ${m['to_stop_name']}'),
                                subtitle: Text('Distance: ${((m['distance_km'] ?? m['distance']) as num?)?.toStringAsFixed(1) ?? 'N/A'} km • Duration: ${(m['duration_minutes'] ?? m['duration']) ?? 'N/A'} min'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('₨${((m['price'] ?? 0) as num).toStringAsFixed(0)}',
                                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () {
                                        final ctrl = TextEditingController(text: ((m['price'] ?? 0) as num).toString());
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Edit Stop Price'),
                                            content: TextField(
                                              controller: ctrl,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(labelText: 'Price (PKR)', prefixText: '₨'),
                                            ),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                              ElevatedButton(
                                                onPressed: () {
                                                  final sanitized = ctrl.text.replaceAll(RegExp(r'[^0-9\\.]'), '');
                                                  final v = double.tryParse(sanitized);
                                                  if (v != null && v >= 0) {
                                                    _controller.updateStopPrice(idx, v);
                                                    Navigator.pop(context);
                                                  }
                                                },
                                                child: const Text('Update'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            })),
                          ],
                        ],
                      ),
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isBusy)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
