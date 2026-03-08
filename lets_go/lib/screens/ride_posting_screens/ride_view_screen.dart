import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/api_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/map_util.dart';
import '../chat_screens/driver_chat_members_screen.dart';
import '../ride_booking_screens/ride_details_view_screen.dart';
import 'package:share_plus/share_plus.dart';

class RideViewScreen extends StatelessWidget {
  final Map<String, dynamic> userData;
  final Map<String, dynamic> rideData;

  const RideViewScreen({
    super.key,
    required this.userData,
    required this.rideData,
  });

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  String _asString(dynamic value, String fallback) {
    if (value == null) return fallback;
    final s = value.toString();
    if (s.trim().isEmpty) return fallback;
    return s;
  }

  String? _driverPhotoUrl(Map<String, dynamic> driver) {
    final raw = driver['photo_url'] ?? driver['profile_photo'] ?? driver['profile_image'];
    final ensured = ImageUtils.ensureValidImageUrl(raw?.toString());
    // Only use a direct, valid URL; otherwise let the UI fall back to initials.
    if (ensured != null && ImageUtils.isValidImageUrl(ensured)) {
      return ensured;
    }
    return null;
  }

  String? _vehicleFrontPhotoUrl(Map<String, dynamic> vehicle) {
    final raw = vehicle['photo_front'] ?? vehicle['front_image'] ?? vehicle['front_photo_url'] ?? vehicle['image_url'];
    final ensured = ImageUtils.ensureValidImageUrl(raw?.toString());
    // Only use a direct, valid URL; otherwise let the UI fall back to the car icon.
    if (ensured != null && ImageUtils.isValidImageUrl(ensured)) {
      return ensured;
    }
    return null;
  }

  String _originName(Map<String, dynamic> ride) {
    try {
      final stops = ride['route_stops'] ?? ride['trip']?['route']?['route_stops'] ?? ride['route']?['route_stops'];
      if (stops is List && stops.isNotEmpty) {
        final first = stops.first;
        if (first is Map) {
          final s = (first['stop_name'] ?? first['name'] ?? '').toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
    } catch (_) {}

    final from = ride['from_location'] ?? ride['trip']?['from_location'];
    if (from is String && from.isNotEmpty && from.toLowerCase() != 'unknown') return from;
    final desc = ride['description']?.toString();
    if (desc != null && desc.trim().isNotEmpty) {
      final parts = desc.split(RegExp(r"\s*[→>-]+\s*"));
      if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
        return parts.first.trim();
      }
    }
    return 'Unknown';
  }

  int _extractUserId() {
    return int.tryParse(userData['id']?.toString() ?? '') ??
        int.tryParse(userData['user_id']?.toString() ?? '') ??
        0;
  }

  Future<void> _showShareSheet(BuildContext context) async {
    final dynamic tripIdRaw = rideData['trip_id'] ?? rideData['id'] ?? rideData['trip']?['trip_id'];
    final tripId = tripIdRaw?.toString() ?? '';
    if (tripId.trim().isEmpty) return;

    String shareUrl = '';
    try {
      final res = await ApiService.createTripShareUrl(
        tripId: tripId,
        role: 'driver',
        bookingId: null,
      );
      if (res['success'] == true) {
        shareUrl = (res['share_url'] ?? '').toString();
      }
    } catch (_) {}

    final urlToShare = shareUrl.trim();
    if (urlToShare.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to generate share link')),
      );
      return;
    }

    final userId = _extractUserId();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share ride'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Share.share(urlToShare);
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open ride (check availability)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (userId <= 0) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Missing user id')),
                    );
                    return;
                  }
                  final ok = await ApiService.isTripAvailableForUser(
                    userId: userId,
                    tripId: tripId,
                  );
                  if (!context.mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Not available for you')),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RideDetailsViewScreen(
                        userData: userData,
                        tripId: tripId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadRideDetails() async {
    Map<String, dynamic> merged = Map<String, dynamic>.from(rideData);

    final hasDetailedData =
        merged['stop_breakdown'] is List ||
        (merged['fare_calculation'] is Map &&
            (merged['fare_calculation'] as Map)['stop_breakdown'] is List) ||
        merged['fare_data'] is Map;
    final hasPassengers = merged['passengers'] is List;

    // If we already have both detailed fare/stop data AND passengers, no need to refetch.
    if (hasDetailedData && hasPassengers) {
      return merged;
    }

    final dynamic tripIdRaw =
        merged['trip_id'] ?? merged['id'] ?? merged['trip']?['trip_id'];
    final tripId = tripIdRaw?.toString();

    if (tripId == null || tripId.isEmpty) {
      return merged;
    }

    try {
      final detail = await ApiService.getRideBookingDetails(tripId);
      // Merge trip core fields
      if (detail['trip'] is Map<String, dynamic>) {
        final t = Map<String, dynamic>.from(detail['trip']);
        final existingTrip = (merged['trip'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(merged['trip'] as Map)
            : <String, dynamic>{};
        merged['trip'] = {
          ...existingTrip,
          ...t,
        };

        if (t['route'] is Map<String, dynamic>) {
          merged['route'] = {
            ...(merged['route'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(merged['route'] as Map)
                : <String, dynamic>{}),
            ...Map<String, dynamic>.from(t['route']),
          };
        }
        if (t['vehicle'] is Map<String, dynamic>) {
          merged['vehicle'] = {
            ...(merged['vehicle'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(merged['vehicle'] as Map)
                : <String, dynamic>{}),
            ...Map<String, dynamic>.from(t['vehicle']),
          };
        }
        if (t['driver'] is Map<String, dynamic>) {
          merged['driver'] = {
            ...(merged['driver'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(merged['driver'] as Map)
                : <String, dynamic>{}),
            ...Map<String, dynamic>.from(t['driver']),
          };
        }
      }

      // Merge top-level driver / vehicle if provided separately
      if (detail['driver'] is Map<String, dynamic>) {
        merged['driver'] = {
          ...(merged['driver'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(merged['driver'] as Map)
              : <String, dynamic>{}),
          ...Map<String, dynamic>.from(detail['driver']),
        };
      }
      if (detail['vehicle'] is Map<String, dynamic>) {
        merged['vehicle'] = {
          ...(merged['vehicle'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(merged['vehicle'] as Map)
              : <String, dynamic>{}),
          ...Map<String, dynamic>.from(detail['vehicle']),
        };
      }

      // Merge route for map and readable origin/destination
      if (detail['route'] is Map<String, dynamic>) {
        if (merged['route'] == null) {
          merged['route'] = Map<String, dynamic>.from(detail['route']);
        } else if (merged['route'] is Map<String, dynamic>) {
          final r = Map<String, dynamic>.from(merged['route'] as Map);
          merged['route'] = {
            ...r,
            ...Map<String, dynamic>.from(detail['route']),
          };
        }
        final route = merged['route'] as Map<String, dynamic>;
        if (route['stops'] is List && (route['stops'] as List).isNotEmpty) {
          merged['route_stops'] = route['stops'];
        }
      }

      // Merge stop breakdown and fare calculation
      if (detail['stop_breakdown'] != null) {
        merged['stop_breakdown'] = detail['stop_breakdown'];
      }
      if (detail['fare_calculation'] != null) {
        merged['fare_calculation'] = detail['fare_calculation'];
      }

      // Merge passengers list if returned in this payload
      if (detail['passengers'] is List) {
        merged['passengers'] = detail['passengers'];
      }
    } catch (_) {
      // ignore
    }

    return merged;
  }

  String _destinationName(Map<String, dynamic> ride) {
    try {
      final stops = ride['route_stops'] ?? ride['trip']?['route']?['route_stops'] ?? ride['route']?['route_stops'];
      if (stops is List && stops.isNotEmpty) {
        final last = stops.last;
        if (last is Map) {
          final s = (last['stop_name'] ?? last['name'] ?? '').toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
    } catch (_) {}

    final to = ride['to_location'] ?? ride['trip']?['to_location'];
    if (to is String && to.isNotEmpty && to.toLowerCase() != 'unknown') return to;
    final desc = ride['description']?.toString();
    if (desc != null && desc.trim().isNotEmpty) {
      final parts = desc.split(RegExp(r"\s*[→>-]+\s*"));
      if (parts.isNotEmpty && parts.last.trim().isNotEmpty) {
        return parts.last.trim();
      }
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final origin = _originName(rideData);
    final destination = _destinationName(rideData);

    final tripDateStr = rideData['trip_date'] ?? rideData['trip']?['trip_date'];
    DateTime? tripDate;
    if (tripDateStr is String && tripDateStr.isNotEmpty) {
      try {
        tripDate = DateTime.parse(tripDateStr);
      } catch (_) {}
    }

    final departureTime = rideData['departure_time'] ?? rideData['trip']?['departure_time'];
    final seats = rideData['total_seats'] ?? rideData['trip']?['total_seats'];
    final price = rideData['custom_price'] ?? rideData['total_fare'];
    final genderPreference = rideData['gender_preference'] ?? rideData['trip']?['gender_preference'];
    final status = _asString(rideData['status'] ?? rideData['trip']?['status'] ?? 'UNKNOWN', 'UNKNOWN');

    final driver = _asMap(rideData['driver'] ?? rideData['trip']?['driver']);
    final vehicle = _asMap(rideData['vehicle'] ?? rideData['trip']?['vehicle']);

    final driverName = _asString(driver['full_name'] ?? driver['name'] ?? driver['username'], 'N/A');
    final vehicleName = _asString(vehicle['vehicle_name'] ?? vehicle['model'] ?? vehicle['model_number'], 'N/A');
    final vehiclePlate =
        _asString(vehicle['plate_number'] ?? vehicle['license_plate'] ?? vehicle['registration_number'], 'N/A');
    final vehicleColor = _asString(vehicle['color'], 'N/A');

    // Additional trip / fare context for driver view
    final trip = _asMap(rideData['trip']);
    final fareData = _asMap(rideData['fare_data']);

    final dynamic isNegotiableDynamic = rideData['is_negotiable'] ?? trip['is_negotiable'];
    final bool isNegotiable = isNegotiableDynamic is bool
        ? isNegotiableDynamic
        : ((isNegotiableDynamic?.toString() ?? '').toLowerCase() == 'true');

    final dynamic pricePerSeatDynamic =
        fareData['base_fare_per_seat'] ?? fareData['base_fare'] ?? trip['base_fare'] ?? price;

    num? asNum(dynamic v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    final num? pricePerSeatNum = asNum(pricePerSeatDynamic);
    num? distanceKm = asNum(fareData['total_distance_km'] ?? rideData['distance'] ?? trip['distance']);
    num? durationMinutes =
        asNum(fareData['total_duration_minutes'] ?? trip['duration_minutes'] ?? rideData['duration']);

    // If distance/duration are not available from fare_data/trip, derive them from stop_breakdown
    List<dynamic> stopBreakdown = const [];
    if (rideData['stop_breakdown'] is List) {
      stopBreakdown = List<dynamic>.from(rideData['stop_breakdown']);
    } else if (rideData['fare_calculation'] is Map &&
        (rideData['fare_calculation'] as Map)['stop_breakdown'] is List) {
      stopBreakdown = List<dynamic>.from((rideData['fare_calculation'] as Map)['stop_breakdown']);
    }

    num? sumNum(List<dynamic> list, String key, [String? altKey]) {
      num total = 0;
      bool hasAny = false;
      for (final item in list) {
        if (item is Map && item[key] != null) {
          final v = asNum(item[key]);
          if (v != null) {
            total += v;
            hasAny = true;
          }
        } else if (item is Map && altKey != null && item[altKey] != null) {
          final v = asNum(item[altKey]);
          if (v != null) {
            total += v;
            hasAny = true;
          }
        }
      }
      return hasAny ? total : null;
    }

    distanceKm ??= sumNum(stopBreakdown, 'distance', 'distance_km');
    durationMinutes ??= sumNum(stopBreakdown, 'duration', 'duration_minutes');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share ride',
            onPressed: () => _showShareSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Chat with Passengers',
            onPressed: () {
              final dynamic tripIdRaw =
                  rideData['trip_id'] ?? rideData['id'] ?? rideData['trip']?['trip_id'];
              final String tripId = tripIdRaw?.toString() ?? '';

              if (tripId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Missing trip id for chat')),
                );
                return;
              }

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverChatMembersScreen(
                    userData: userData,
                    tripId: tripId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Route Map card first (lazy loads detailed path data)
          FutureBuilder<Map<String, dynamic>>(
            future: _loadRideDetails(),
            builder: (context, snapshot) {
              final isLoading = snapshot.connectionState == ConnectionState.waiting;
              final data = snapshot.data ?? rideData;

              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.map, color: Colors.teal),
                          SizedBox(width: 8),
                          Text('Route Map',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isLoading)
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.33,
                          child: const Center(child: CircularProgressIndicator()),
                        )
                      else
                        _buildMapSection(context, data),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // Stop-by-stop breakdown card (lazy loaded)
          FutureBuilder<Map<String, dynamic>>(
            future: _loadRideDetails(),
            builder: (context, snapshot) {
              final isLoading = snapshot.connectionState == ConnectionState.waiting;
              final data = snapshot.data ?? rideData;

              if (isLoading &&
                  data['stop_breakdown'] is! List &&
                  !(data['fare_calculation'] is Map &&
                      (data['fare_calculation'] as Map)['stop_breakdown'] is List)) {
                return Card(
                  elevation: 1,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              return _buildStopBreakdownCard(data);
            },
          ),

          const SizedBox(height: 12),

          // Status card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.directions_bus, color: Colors.teal),
                      SizedBox(width: 8),
                      Text('Ride Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(status),
                        backgroundColor: Colors.teal.withValues(alpha: 0.08),
                        labelStyle: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                      ),
                      Chip(
                        label: Text('$origin → $destination'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Trip Information card (driver + vehicle)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.directions_car, color: Colors.teal),
                      SizedBox(width: 8),
                      Text('Trip Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.teal.shade100,
                              child: Text(
                                driverName.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  color: Colors.teal.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            if (_driverPhotoUrl(driver) != null && ImageUtils.isValidImageUrl(_driverPhotoUrl(driver)))
                              ClipOval(
                                child: Image.network(
                                  _driverPhotoUrl(driver)!,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox.shrink();
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(Icons.person, 'Driver: $driverName'),
                          ],
                        ),
                      ),
                    ],
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
                        child: Stack(
                          children: [
                            Center(
                              child: Icon(
                                Icons.directions_car,
                                size: 30,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (_vehicleFrontPhotoUrl(vehicle) != null && ImageUtils.isValidImageUrl(_vehicleFrontPhotoUrl(vehicle)))
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _vehicleFrontPhotoUrl(vehicle)!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox.shrink();
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(Icons.directions_car_filled, 'Vehicle: $vehicleName'),
                            _buildInfoRow(Icons.confirmation_number, 'Plate: $vehiclePlate'),
                            _buildInfoRow(Icons.color_lens, 'Color: $vehicleColor'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (tripDate != null)
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Date: ${DateFormat('MMM dd, yyyy').format(tripDate)}',
                    ),
                  if (departureTime != null)
                    _buildInfoRow(
                      Icons.access_time,
                      'Departure Time: ${departureTime.toString()}',
                    ),
                  if (seats != null)
                    _buildInfoRow(
                      Icons.airline_seat_recline_normal,
                      '$seats seats',
                    ),
                  if (genderPreference != null)
                    _buildInfoRow(
                      Icons.group,
                      'Gender Preference: ${genderPreference.toString()}',
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Fare / other info card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.attach_money, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Fare Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pricePerSeatNum != null)
                    _buildInfoRow(Icons.monetization_on,
                        'Price per seat: ₨${pricePerSeatNum.toStringAsFixed(0)}'),
                  if (seats != null && pricePerSeatNum != null)
                    _buildInfoRow(Icons.payments,
                        'Total potential (all seats): ₨${(seats * pricePerSeatNum).toStringAsFixed(0)}'),
                  _buildInfoRow(
                    Icons.handshake,
                    'Negotiable: ${isNegotiable ? 'Yes' : 'No'}',
                  ),
                  if (distanceKm != null)
                    _buildInfoRow(
                      Icons.straighten,
                      'Route distance: ${distanceKm.toStringAsFixed(1)} km',
                    ),
                  if (durationMinutes != null)
                    _buildInfoRow(
                      Icons.timer,
                      'Estimated duration: ${durationMinutes.toStringAsFixed(0)} min',
                    ),
                ],
              ),
            ),
          ),

          if (rideData['description']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.notes, color: Colors.brown),
                        SizedBox(width: 8),
                        Text('Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(rideData['description'].toString()),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStopBreakdownCard(Map<String, dynamic> dataSource) {
    List<dynamic> stops = const [];
    if (dataSource['stop_breakdown'] is List) {
      stops = List<dynamic>.from(dataSource['stop_breakdown']);
    } else if (dataSource['fare_calculation'] is Map &&
        (dataSource['fare_calculation'] as Map)['stop_breakdown'] is List) {
      stops =
          List<dynamic>.from((dataSource['fare_calculation'] as Map)['stop_breakdown']);
    }

    if (stops.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.route, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('Stop-by-stop Breakdown',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ...stops.asMap().entries.map((entry) {
              final index = entry.key;
              final data = entry.value as Map<String, dynamic>;

              num? asNumLocal(dynamic v) {
                if (v is num) return v;
                if (v is String) return num.tryParse(v);
                return null;
              }

              final fromName =
                  _asString(data['from_stop_name'] ?? data['from'] ?? data['from_name'], 'Unknown');
              final toName = _asString(data['to_stop_name'] ?? data['to'] ?? data['to_name'], 'Unknown');
              final distance = asNumLocal(data['distance_km'] ?? data['distance']);
              final duration = asNumLocal(data['duration_minutes'] ?? data['duration']);
              final price = asNumLocal(data['price']);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '$fromName → $toName',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (price != null)
                          Text(
                            '₨${price.round()}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Distance: ${distance != null ? distance.toStringAsFixed(1) : 'N/A'} km',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Duration: ${duration != null ? duration.toStringAsFixed(0) : 'N/A'} min',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    if (index != stops.length - 1) const Divider(height: 12),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection(BuildContext context, Map<String, dynamic> dataSource) {
    final points = <LatLng>[];
    final names = <String>[];

    // 1) Try to build from stop_breakdown segment coordinates for better path approximation
    if (dataSource['stop_breakdown'] is List) {
      final List<dynamic> sbList = List<dynamic>.from(dataSource['stop_breakdown']);
      sbList.sort((a, b) {
        final am = a as Map<String, dynamic>;
        final bm = b as Map<String, dynamic>;
        final ao = (am['from_stop_order'] ?? 0) as int;
        final bo = (bm['from_stop_order'] ?? 0) as int;
        final at = (am['to_stop_order'] ?? 0) as int;
        final bt = (bm['to_stop_order'] ?? 0) as int;
        if (ao != bo) return ao.compareTo(bo);
        return at.compareTo(bt);
      });

      LatLng? last;
      for (final raw in sbList) {
        if (raw is! Map<String, dynamic>) continue;
        final fromC = raw['from_coordinates'] as Map?;
        final toC = raw['to_coordinates'] as Map?;

        LatLng? mk(Map? c) {
          if (c == null) return null;
          final lat = c['lat'] as num?;
          final lng = c['lng'] as num?;
          if (lat == null || lng == null) return null;
          return LatLng(lat.toDouble(), lng.toDouble());
        }

        final fromPoint = mk(fromC);
        final toPoint = mk(toC);

        if (fromPoint != null) {
          final lp = last;
          if (lp == null || lp.latitude != fromPoint.latitude || lp.longitude != fromPoint.longitude) {
            points.add(fromPoint);
            names.add(raw['from_stop_name']?.toString() ?? 'Stop');
            last = fromPoint;
          }
        }

        if (toPoint != null) {
          final lp = last;
          if (lp == null || lp.latitude != toPoint.latitude || lp.longitude != toPoint.longitude) {
            points.add(toPoint);
            names.add(raw['to_stop_name']?.toString() ?? 'Stop');
            last = toPoint;
          }
        }
      }
    }

    // 2) Fallback to route stops if we didn't get usable segment coordinates
    if (points.isEmpty) {
      final stops = _extractStopsFromRide();
      if (stops.isEmpty) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.33,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text('Map not available for this ride'),
          ),
        );
      }

      for (final stop in stops) {
        final lat = (stop['latitude'] ?? stop['lat']) as num?;
        final lng = (stop['longitude'] ?? stop['lng']) as num?;
        if (lat != null && lng != null) {
          points.add(LatLng(lat.toDouble(), lng.toDouble()));
          names.add(stop['name']?.toString() ?? 'Stop');
        }
      }
    }
    if (points.isEmpty) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.33,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Map not available for this ride'),
        ),
      );
    }

    final center = MapUtil.centerFromPoints(points);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.33,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
          ),
          children: [
            MapUtil.buildDefaultTileLayer(),
            FutureBuilder<List<LatLng>>(
              future: MapUtil.roadPolylineOrFallback(points),
              builder: (context, snapshot) {
                final polyPoints =
                    (snapshot.connectionState == ConnectionState.done && snapshot.hasData && snapshot.data!.length > 1)
                        ? snapshot.data!
                        : points;
                return MapUtil.buildPolylineLayer(points: polyPoints);
              },
            ),
            MarkerLayer(
              markers: [
                for (int i = 0; i < points.length; i++)
                  Marker(
                    point: points[i],
                    width: 40,
                    height: 40,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          i == 0
                              ? Icons.trip_origin
                              : i == points.length - 1
                                  ? Icons.place
                                  : Icons.location_on,
                          color: i == 0
                              ? const Color(0xFF4CAF50)
                              : i == points.length - 1
                                  ? const Color(0xFFE53935)
                                  : const Color(0xFFFF9800),
                          size: 32,
                        ),
                        Positioned(
                          bottom: -18,
                          left: -30,
                          right: -30,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(38),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                i < names.length ? names[i] : 'Stop ${i + 1}',
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _extractStopsFromRide() {
    if (rideData['route_stops'] is List) {
      return List<dynamic>.from(rideData['route_stops']);
    }
    if (rideData['route'] is Map && rideData['route']['stops'] is List) {
      return List<dynamic>.from(rideData['route']['stops']);
    }
    if (rideData['trip'] is Map && rideData['trip']['route'] is Map && rideData['trip']['route']['stops'] is List) {
      return List<dynamic>.from(rideData['trip']['route']['stops']);
    }
    return const [];
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

