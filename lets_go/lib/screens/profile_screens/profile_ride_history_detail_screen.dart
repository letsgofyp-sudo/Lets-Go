// import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
// import '../../services/api_service.dart';
// import '../../utils/map_util.dart';
// import '../../utils/recreate_trip_mapper.dart';
// import '../ride_posting_screens/create_ride_details_screen.dart';

// class ProfileRideHistoryDetailScreen extends StatefulWidget {
//   final Map<String, dynamic> userData;
//   final String tripId;

//   const ProfileRideHistoryDetailScreen({
//     super.key,
//     required this.userData,
//     required this.tripId,
//   });

//   @override
//   State<ProfileRideHistoryDetailScreen> createState() => _ProfileRideHistoryDetailScreenState();
// }

// class _ProfileRideHistoryDetailScreenState extends State<ProfileRideHistoryDetailScreen> {
//   bool _loading = true;
//   String? _error;
//   Map<String, dynamic>? _trip;
//   bool _useActualPath = false;

//   Future<void> _recreateRide() async {
//     final tripId = widget.tripId.trim();
//     if (tripId.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Trip id missing; cannot recreate this ride')),
//       );
//       return;
//     }

//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (_) => const Center(child: CircularProgressIndicator()),
//     );

//     try {
//       Map<String, dynamic> detail = <String, dynamic>{};
//       try {
//         detail = await ApiService.getRideBookingDetails(tripId);
//       } catch (_) {
//         // Fall back to trip details endpoint (supports history snapshot).
//         detail = await ApiService.getTripDetailsById(tripId);
//       }

//       if (!mounted) return;
//       Navigator.of(context).pop();

//       final trip = RecreateTripMapper.normalizeRideBookingDetail(detail);
//       if (trip.isEmpty) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Unable to load trip details')),
//         );
//         return;
//       }

//       final routeData = RecreateTripMapper.buildRouteDataFromNormalizedTrip(
//         trip,
//         preferActualPath: _useActualPath,
//       );

//       if (routeData == null) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Trip route data missing')),
//         );
//         return;
//       }

//       final vehicle = (trip['vehicle'] is Map)
//           ? Map<String, dynamic>.from(trip['vehicle'] as Map)
//           : <String, dynamic>{};

//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (_) => RideDetailsScreen(
//             userData: widget.userData,
//             routeData: routeData,
//             recreateMode: true,
//             initialTripDate: (trip['trip_date'] ?? '').toString(),
//             initialDepartureTime: (trip['departure_time'] ?? '').toString(),
//             initialVehicleId: (vehicle['id'] ?? '').toString(),
//             initialTotalSeats: int.tryParse((trip['total_seats'] ?? '').toString()),
//             initialGenderPreference: (trip['gender_preference'] ?? '').toString(),
//             initialNotes: '',
//             initialIsNegotiable: (trip['is_negotiable'] == true),
//             initialBaseFare: int.tryParse((trip['base_fare'] ?? '').toString()),
//           ),
//         ),
//       );
//     } catch (e) {
//       if (!mounted) return;
//       Navigator.of(context).pop();
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Failed to recreate trip: $e')),
//       );
//     }
//   }

//   @override
//   void initState() {
//     super.initState();
//     () async {
//       try {
//         final raw = widget.userData['id'] ?? widget.userData['user_id'];
//         final userId = int.tryParse(raw?.toString() ?? '') ?? 0;
//         if (userId > 0) {
//           await ApiService.triggerAutoArchiveForDriver(userId: userId, limit: 10);
//         }
//       } catch (_) {
//         // ignore
//       }
//     }();
//     _load();
//   }

//   Future<void> _load() async {
//     setState(() {
//       _loading = true;
//       _error = null;
//       _trip = null;
//     });

//     try {
//       final detail = await ApiService.getTripDetailsById(widget.tripId);
//       if (!mounted) return;

//       if (detail.isEmpty) {
//         setState(() {
//           _error = 'Unable to load trip details';
//           _loading = false;
//         });
//         return;
//       }

//       setState(() {
//         _trip = detail;
//         _loading = false;
//       });
//     } catch (e) {
//       if (!mounted) return;
//       setState(() {
//         _error = 'Failed to load trip details: $e';
//         _loading = false;
//       });
//     }
//   }

//   String _safe(dynamic v, {String fallback = 'N/A'}) {
//     final s = (v ?? '').toString().trim();
//     return s.isEmpty ? fallback : s;
//   }

//   List<Map<String, dynamic>> _stopsFromTrip(Map<String, dynamic> trip) {
//     final route = (trip['route'] is Map) ? Map<String, dynamic>.from(trip['route'] as Map) : <String, dynamic>{};
//     final stops = (route['stops'] is List) ? List.from(route['stops'] as List) : <dynamic>[];
//     return stops.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
//   }

//   List<LatLng> _polylineFromTrip(Map<String, dynamic> trip) {
//     final route = (trip['route'] is Map) ? Map<String, dynamic>.from(trip['route'] as Map) : <String, dynamic>{};

//     final planned = <LatLng>[];
//     final rp = route['route_points'];
//     if (rp is List) {
//       for (final p in rp) {
//         if (p is! Map) continue;
//         final lat = p['lat'];
//         final lng = p['lng'];
//         if (lat is num && lng is num) {
//           planned.add(LatLng(lat.toDouble(), lng.toDouble()));
//         }
//       }
//     }

//     if (planned.length >= 2) return planned;

//     final stops = _stopsFromTrip(trip);
//     final points = <LatLng>[];
//     for (final s in stops) {
//       final lat = s['latitude'];
//       final lng = s['longitude'];
//       if (lat is num && lng is num) {
//         points.add(LatLng(lat.toDouble(), lng.toDouble()));
//       }
//     }
//     return points;
//   }

//   List<LatLng> _actualPolylineFromTrip(Map<String, dynamic> trip) {
//     final raw = (trip['actual_path'] is List) ? List.from(trip['actual_path'] as List) : <dynamic>[];
//     final actual = <LatLng>[];
//     for (final p in raw) {
//       if (p is! Map) continue;
//       final lat = p['lat'];
//       final lng = p['lng'];
//       if (lat is num && lng is num) {
//         actual.add(LatLng(lat.toDouble(), lng.toDouble()));
//       }
//     }

//     if (actual.length < 2) return actual;

//     try {
//       return MapUtil.densifyPolyline(actual, maxStepMeters: 25);
//     } catch (_) {
//       return actual;
//     }
//   }

//   String _formatNum(dynamic v, {int digits = 1, String fallback = 'N/A'}) {
//     if (v is num) {
//       try {
//         return v.toStringAsFixed(digits);
//       } catch (_) {
//         return v.toString();
//       }
//     }
//     return _safe(v, fallback: fallback);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Ride Details'),
//         actions: [
//           IconButton(
//             onPressed: _loading ? null : _load,
//             icon: const Icon(Icons.refresh),
//           )
//         ],
//       ),
//       body: _loading
//           ? const Center(child: CircularProgressIndicator())
//           : (_error != null)
//               ? Center(child: Text(_error!))
//               : _buildContent(),
//     );
//   }

//   Widget _buildContent() {
//     final trip = _trip ?? <String, dynamic>{};
//     final stops = _stopsFromTrip(trip);
//     final plannedPolyline = _polylineFromTrip(trip);
//     final actualPolyline = _actualPolylineFromTrip(trip);

//     final hasActual = actualPolyline.length >= 2;
//     final showActual = _useActualPath && hasActual;
//     final mapPolyline = showActual ? actualPolyline : plannedPolyline;

//     final vehicle = (trip['vehicle'] is Map) ? Map<String, dynamic>.from(trip['vehicle'] as Map) : <String, dynamic>{};
//     final driver = (trip['driver'] is Map) ? Map<String, dynamic>.from(trip['driver'] as Map) : <String, dynamic>{};

//     final tripDate = _safe(trip['trip_date']);
//     final depTime = _safe(trip['departure_time']);
//     final status = _safe(trip['status']);

//     final dist = trip['total_distance_km'];
//     final dur = trip['total_duration_minutes'];
//     final baseFare = trip['base_fare'];

//     final distText = (dist is num) ? '${_formatNum(dist, digits: 1)} km' : _safe(dist);
//     final durText = (dur is num) ? '${dur.toString()} min' : _safe(dur);
//     final fareText = (baseFare is num) ? 'Rs. ${baseFare.toInt()}' : _safe(baseFare);

//     final notes = _safe(trip['notes'], fallback: '');

//     LatLng initialCenter = const LatLng(33.6844, 73.0479);
//     if (mapPolyline.isNotEmpty) {
//       initialCenter = mapPolyline[mapPolyline.length ~/ 2];
//     } else if (stops.isNotEmpty) {
//       final lat = stops.first['latitude'];
//       final lng = stops.first['longitude'];
//       if (lat is num && lng is num) {
//         initialCenter = LatLng(lat.toDouble(), lng.toDouble());
//       }
//     }

//     return ListView(
//       padding: const EdgeInsets.all(16),
//       children: [
//         SizedBox(
//           width: double.infinity,
//           child: ElevatedButton.icon(
//             onPressed: _recreateRide,
//             icon: const Icon(Icons.replay),
//             label: const Text('Recreate Ride'),
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.teal,
//               foregroundColor: Colors.white,
//               padding: const EdgeInsets.symmetric(vertical: 12),
//             ),
//           ),
//         ),
//         const SizedBox(height: 12),
//         Card(
//           elevation: 0,
//           color: Theme.of(context).colorScheme.surface,
//           child: Padding(
//             padding: const EdgeInsets.all(12),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         'Route Map',
//                         style: Theme.of(context).textTheme.titleMedium,
//                       ),
//                     ),
//                     if (hasActual)
//                       SegmentedButton<bool>(
//                         segments: const [
//                           ButtonSegment(value: false, label: Text('Planned')),
//                           ButtonSegment(value: true, label: Text('Actual')),
//                         ],
//                         selected: {_useActualPath},
//                         onSelectionChanged: (s) {
//                           setState(() {
//                             _useActualPath = s.contains(true);
//                           });
//                         },
//                       ),
//                   ],
//                 ),
//                 const SizedBox(height: 10),
//                 SizedBox(
//                   height: 240,
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(12),
//                     child: FlutterMap(
//                       options: MapOptions(initialCenter: initialCenter, initialZoom: 12),
//                       children: [
//                         MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
//                         if (plannedPolyline.length >= 2)
//                           MapUtil.buildPolylineLayerFromPolylines(
//                             polylines: [
//                               MapUtil.polyline(
//                                 points: plannedPolyline,
//                                 color: Colors.blue.withValues(alpha: showActual ? 0.35 : 1.0),
//                                 strokeWidth: showActual ? 3 : 4,
//                               ),
//                             ],
//                           ),
//                         if (actualPolyline.length >= 2)
//                           MapUtil.buildPolylineLayerFromPolylines(
//                             polylines: [
//                               MapUtil.polyline(
//                                 points: actualPolyline,
//                                 color: Colors.green,
//                                 strokeWidth: showActual ? 4 : 0,
//                               ),
//                             ],
//                           ),
//                         if (stops.isNotEmpty)
//                           MarkerLayer(
//                             markers: stops
//                                 .map((s) {
//                                   final lat = s['latitude'];
//                                   final lng = s['longitude'];
//                                   if (lat is! num || lng is! num) return null;
//                                   return Marker(
//                                     width: 42,
//                                     height: 42,
//                                     point: LatLng(lat.toDouble(), lng.toDouble()),
//                                     child: const Icon(Icons.location_on, color: Colors.red, size: 34),
//                                   );
//                                 })
//                                 .whereType<Marker>()
//                                 .toList(),
//                           ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 10),
//                 Wrap(
//                   spacing: 10,
//                   runSpacing: 6,
//                   children: [
//                     _legendDot('Stops', Colors.red),
//                     _legendDot('Planned path', Colors.blue),
//                     if (hasActual) _legendDot('Actual path', Colors.green),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
//         const SizedBox(height: 16),
//         _sectionTitle('Trip'),
//         Card(
//           elevation: 0,
//           child: Padding(
//             padding: const EdgeInsets.all(12),
//             child: Column(
//               children: [
//                 _kv('Trip ID', widget.tripId),
//                 _kv('Status', status),
//                 _kv('Date', tripDate),
//                 _kv('Departure', depTime),
//                 _kv('Distance', distText),
//                 _kv('Duration', durText),
//                 _kv('Fare', fareText),
//                 if (notes.isNotEmpty) ...[
//                   const Divider(height: 18),
//                   Align(
//                     alignment: Alignment.centerLeft,
//                     child: Text('Notes', style: TextStyle(color: Colors.grey[700])),
//                   ),
//                   const SizedBox(height: 6),
//                   Align(
//                     alignment: Alignment.centerLeft,
//                     child: Text(notes),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ),
//         const SizedBox(height: 16),
//         _sectionTitle('Stops'),
//         Card(
//           elevation: 0,
//           child: Padding(
//             padding: const EdgeInsets.all(6),
//             child: (stops.isEmpty)
//                 ? const Padding(
//                     padding: EdgeInsets.all(10),
//                     child: Text('No stops data'),
//                   )
//                 : Column(
//                     children: stops.asMap().entries.map((e) {
//                       final idx = e.key;
//                       final s = e.value;
//                       final title = _safe(s['name'] ?? s['stop_name'] ?? 'Stop');
//                       final lat = s['latitude'];
//                       final lng = s['longitude'];
//                       final coord = (lat is num && lng is num)
//                           ? '${_formatNum(lat, digits: 5)}, ${_formatNum(lng, digits: 5)}'
//                           : 'N/A';

//                       return ListTile(
//                         dense: true,
//                         leading: CircleAvatar(
//                           radius: 14,
//                           child: Text('${idx + 1}', style: const TextStyle(fontSize: 12)),
//                         ),
//                         title: Text(title),
//                         subtitle: Text(coord),
//                       );
//                     }).toList(),
//                   ),
//           ),
//         ),
//         const SizedBox(height: 16),
//         _sectionTitle('Vehicle'),
//         Card(
//           elevation: 0,
//           child: Padding(
//             padding: const EdgeInsets.all(12),
//             child: Column(
//               children: [
//                 _kv('Vehicle ID', _safe(vehicle['id'])),
//                 _kv('Model', _safe(vehicle['model_number'])),
//                 _kv('Company', _safe(vehicle['company_name'])),
//                 _kv('Plate', _safe(vehicle['plate_number'])),
//                 _kv('Type', _safe(vehicle['vehicle_type'])),
//                 _kv('Color', _safe(vehicle['color'])),
//                 _kv('Seats', _safe(vehicle['seats'])),
//                 _kv('Fuel', _safe(vehicle['fuel_type'])),
//               ],
//             ),
//           ),
//         ),
//         const SizedBox(height: 16),
//         _sectionTitle('Driver'),
//         Card(
//           elevation: 0,
//           child: Padding(
//             padding: const EdgeInsets.all(12),
//             child: Column(
//               children: [
//                 _kv('Driver ID', _safe(driver['id'])),
//                 _kv('Name', _safe(driver['name'])),
//                 _kv('Phone', _safe(driver['phone_no'])),
//               ],
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _legendDot(String label, Color color) {
//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Container(
//           width: 10,
//           height: 10,
//           decoration: BoxDecoration(color: color, shape: BoxShape.circle),
//         ),
//         const SizedBox(width: 6),
//         Text(label),
//       ],
//     );
//   }

//   Widget _sectionTitle(String text) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 8),
//       child: Text(
//         text,
//         style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//       ),
//     );
//   }

//   Widget _kv(String k, String v) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 6),
//       child: Row(
//         children: [
//           Expanded(child: Text(k, style: TextStyle(color: Colors.grey[700]))),
//           const SizedBox(width: 12),
//           Expanded(child: Text(v, textAlign: TextAlign.right)),
//         ],
//       ),
//     );
//   }
// }
