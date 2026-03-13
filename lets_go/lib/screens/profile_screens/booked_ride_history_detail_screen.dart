import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';

import '../../services/api_service.dart';
import '../../utils/map_util.dart';
import '../../utils/recreate_trip_mapper.dart';

class BookedRideHistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Map<String, dynamic> booking;

  const BookedRideHistoryDetailScreen({
    super.key,
    required this.userData,
    required this.booking,
  });

  @override
  State<BookedRideHistoryDetailScreen> createState() =>
      _BookedRideHistoryDetailScreenState();
}

class _BookedRideHistoryDetailScreenState
    extends State<BookedRideHistoryDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _trip;
  bool _useActualPath = false;

  String _safe(dynamic v, {String fallback = 'N/A'}) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _formatNum(dynamic v, {int digits = 1, String fallback = 'N/A'}) {
    if (v is num) {
      try {
        return v.toStringAsFixed(digits);
      } catch (_) {
        return v.toString();
      }
    }
    final n = num.tryParse(v?.toString() ?? '');
    if (n == null) return fallback;
    return n.toStringAsFixed(digits);
  }

  String _tripId() {
    return (widget.booking['trip_id'] ?? '').toString().trim();
  }

  Future<void> _load() async {
    final tripId = _tripId();
    if (tripId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Trip id missing';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _trip = null;
    });

    try {
      // ApiService.getTripDetailsById() returns the trip map directly.
      // Some other endpoints return {success:true, trip:{...}}. Support both.
      Map<String, dynamic> trip = <String, dynamic>{};
      try {
        final res = await ApiService.getTripDetailsById(tripId);
        if (res['success'] == true && res['trip'] is Map) {
          trip = Map<String, dynamic>.from(res['trip'] as Map);
        } else {
          // Most common path in this codebase: res is already the trip
          // (it should contain trip_id / route / etc.).
          trip = Map<String, dynamic>.from(res);
        }
      } catch (_) {
        // Fallback: ride-booking details can still reconstruct trip + route.
        final detail = await ApiService.getRideBookingDetails(tripId);
        final normalized = RecreateTripMapper.normalizeRideBookingDetail(
          detail,
        );
        trip = normalized;
      }

      if (trip.isNotEmpty) {
        setState(() {
          _trip = trip;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Unable to load trip details';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Unable to load trip details: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _stopsFromTrip(Map<String, dynamic> trip) {
    final route = (trip['route'] is Map)
        ? Map<String, dynamic>.from(trip['route'] as Map)
        : <String, dynamic>{};
    final stops = (route['stops'] is List)
        ? List.from(route['stops'] as List)
        : <dynamic>[];
    return stops
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<LatLng> _polylineFromTrip(Map<String, dynamic> trip) {
    final route = (trip['route'] is Map)
        ? Map<String, dynamic>.from(trip['route'] as Map)
        : <String, dynamic>{};

    final planned = <LatLng>[];
    dynamic rp = route['route_points'];
    if (rp is String) {
      try {
        rp = json.decode(rp);
      } catch (_) {
        rp = null;
      }
    }
    if (rp is List) {
      for (final p in rp) {
        if (p is! Map) continue;
        final lat = p['lat'] ?? p['latitude'];
        final lng = p['lng'] ?? p['longitude'];
        if (lat is num && lng is num) {
          planned.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }

    if (planned.length >= 2) return planned;

    final stops = _stopsFromTrip(trip);
    final fallback = <LatLng>[];
    for (final s in stops) {
      final lat = s['latitude'];
      final lng = s['longitude'];
      if (lat is num && lng is num) {
        fallback.add(LatLng(lat.toDouble(), lng.toDouble()));
      }
    }
    return fallback;
  }

  List<LatLng> _actualPolylineFromTrip(Map<String, dynamic> trip) {
    dynamic raw = trip['actual_path'];
    if (raw is String) {
      try {
        raw = json.decode(raw);
      } catch (_) {
        raw = null;
      }
    }
    final listRaw = (raw is List) ? List.from(raw) : <dynamic>[];
    final actual = <LatLng>[];
    for (final p in listRaw) {
      if (p is! Map) continue;
      final lat = p['lat'] ?? p['latitude'];
      final lng = p['lng'] ?? p['longitude'];
      if (lat is num && lng is num) {
        actual.add(LatLng(lat.toDouble(), lng.toDouble()));
      }
    }
    return actual;
  }

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final raw = widget.userData['id'] ?? widget.userData['user_id'];
        final userId = int.tryParse(raw?.toString() ?? '') ?? 0;
        if (userId > 0) {
          await ApiService.triggerAutoArchiveForDriver(
            userId: userId,
            limit: 10,
          );
        }
      } catch (_) {
        // ignore
      }
    }();
    _load();
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: TextStyle(color: Colors.grey[700])),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Booking Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
          ? Center(child: Text(_error!))
          : _buildContent(booking),
    );
  }

  Widget _buildContent(Map<String, dynamic> booking) {
    final trip = _trip ?? <String, dynamic>{};

    final plannedPolyline = _polylineFromTrip(trip);
    final actualPolyline = _actualPolylineFromTrip(trip);
    final stops = _stopsFromTrip(trip);

    final hasActual = actualPolyline.length >= 2;
    final showActual = _useActualPath && hasActual;

    final tripDate = _safe(trip['trip_date']);
    final depTime = _safe(trip['departure_time']);

    final dist = trip['total_distance_km'];
    final dur = trip['total_duration_minutes'];
    final baseFare = trip['base_fare'];

    final distText = (dist is num)
        ? '${_formatNum(dist, digits: 1)} km'
        : _safe(dist);
    final durText = (dur is num) ? '${dur.toString()} min' : _safe(dur);
    final fareText = (baseFare is num)
        ? 'Rs. ${baseFare.toInt()}'
        : _safe(baseFare);

    LatLng initialCenter = const LatLng(33.6844, 73.0479);
    final mapPolyline = showActual ? actualPolyline : plannedPolyline;
    if (mapPolyline.isNotEmpty) {
      initialCenter = mapPolyline[mapPolyline.length ~/ 2];
    } else if (stops.isNotEmpty) {
      final lat = stops.first['latitude'];
      final lng = stops.first['longitude'];
      if (lat is num && lng is num) {
        initialCenter = LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Booking'),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _kv(
                  'Booking ID',
                  _safe(booking['booking_id'] ?? booking['id']),
                ),
                _kv('Trip ID', _safe(booking['trip_id'])),
                _kv(
                  'Status',
                  _safe(booking['booking_status'] ?? booking['status']),
                ),
                _kv('Ride Status', _safe(booking['ride_status'])),
                _kv('Payment', _safe(booking['payment_status'])),
                _kv(
                  'From',
                  _safe(
                    (booking['route_names'] is List &&
                            (booking['route_names'] as List).isNotEmpty)
                        ? (booking['route_names'] as List).first
                        : booking['from_stop_name'],
                  ),
                ),
                _kv(
                  'To',
                  _safe(
                    (booking['route_names'] is List &&
                            (booking['route_names'] as List).isNotEmpty)
                        ? (booking['route_names'] as List).last
                        : booking['to_stop_name'],
                  ),
                ),
                _kv('Seats', _safe(booking['number_of_seats'])),
                _kv('Fare Paid', _safe(booking['total_fare'])),
                if (_safe(booking['updated_at'], fallback: '').isNotEmpty)
                  _kv('Updated', _safe(booking['updated_at'], fallback: '')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('Trip'),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _kv('Date', tripDate),
                _kv('Departure', depTime),
                _kv('Distance', distText),
                _kv('Duration', durText),
                _kv('Base Fare', fareText),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle('Route Map'),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Map',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (hasActual)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Planned')),
                          ButtonSegment(value: true, label: Text('Actual')),
                        ],
                        selected: {_useActualPath},
                        onSelectionChanged: (s) {
                          setState(() {
                            _useActualPath = s.contains(true);
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: initialCenter,
                        initialZoom: 12,
                      ),
                      children: [
                        MapUtil.buildDefaultTileLayer(
                          userAgentPackageName: 'com.example.lets_go',
                        ),
                        if (mapPolyline.length >= 2)
                          MapUtil.buildPolylineLayerFromPolylines(
                            polylines: [
                              MapUtil.polyline(
                                points: mapPolyline,
                                color: showActual ? Colors.green : Colors.blue,
                                strokeWidth: 4,
                              ),
                            ],
                          ),
                        if (stops.isNotEmpty)
                          MarkerLayer(
                            markers: stops
                                .map((s) {
                                  final lat = s['latitude'];
                                  final lng = s['longitude'];
                                  if (lat is! num || lng is! num) return null;
                                  return Marker(
                                    width: 42,
                                    height: 42,
                                    point: LatLng(
                                      lat.toDouble(),
                                      lng.toDouble(),
                                    ),
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.red,
                                      size: 34,
                                    ),
                                  );
                                })
                                .whereType<Marker>()
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _legendDot('Stops', Colors.red),
                    _legendDot('Planned path', Colors.blue),
                    if (hasActual) _legendDot('Actual path', Colors.green),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
