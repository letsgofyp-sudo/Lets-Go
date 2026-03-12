import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import '../../services/api_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/map_util.dart';
import '../ride_booking_screens/negotiation_details_screen.dart';
import '../chat_screens/passenger_chat_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class BookingDetailScreen extends StatelessWidget {
  final Map<String, dynamic> booking;
  final Map<String, dynamic> userData;

  const BookingDetailScreen({
    super.key,
    required this.booking,
    required this.userData,
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
    if (ensured != null && ImageUtils.isValidImageUrl(ensured)) {
      return ensured;
    }
    return null;
  }

  String? _vehicleFrontPhotoUrl(Map<String, dynamic> vehicle) {
    final raw = vehicle['photo_front'] ?? vehicle['front_image'] ?? vehicle['front_photo_url'] ?? vehicle['image_url'];
    final ensured = ImageUtils.ensureValidImageUrl(raw?.toString());
    if (ensured != null && ImageUtils.isValidImageUrl(ensured)) {
      return ensured;
    }
    return null;
  }

  String _originName(Map<String, dynamic> b) {
    try {
      final rn = (b['route_names'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (rn.isNotEmpty) return rn.first;
    } catch (_) {}

    if (b['route'] is Map<String, dynamic>) {
      final route = b['route'] as Map<String, dynamic>;
      if (route['stops'] is List && (route['stops'] as List).isNotEmpty) {
        final firstStop = route['stops'][0];
        final name = firstStop['name']?.toString();
        if (name != null && name.trim().isNotEmpty) return name.trim();
      }
    }

    final from = b['from_location'] ?? b['trip']?['from_location'];
    if (from is String && from.isNotEmpty && from.toLowerCase() != 'unknown') return from;
    final desc = b['description']?.toString();
    if (desc != null && desc.trim().isNotEmpty) {
      final parts = desc.split(RegExp(r"\s*[→>-]+\s*"));
      if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
        return parts.first.trim();
      }
    }
    return 'Unknown';
  }

  Future<Map<String, dynamic>> _loadBookingDetails() async {
    Map<String, dynamic> merged = Map<String, dynamic>.from(booking);

    final hasDetailedData =
        merged['stop_breakdown'] is List ||
        (merged['fare_calculation'] is Map &&
            (merged['fare_calculation'] as Map)['stop_breakdown'] is List) ||
        merged['fare_data'] is Map;

    if (hasDetailedData) {
      return merged;
    }

    final dynamic tripIdRaw =
        merged['trip_id'] ?? merged['trip']?['trip_id'];
    final tripId = tripIdRaw?.toString();

    if (tripId == null || tripId.isEmpty) {
      return merged;
    }

    try {
      final detail = await ApiService.getRideBookingDetails(tripId);

      // Preserve polylines if provided at the top-level of the payload.
      if (detail['route_points'] != null) {
        merged['route_points'] = detail['route_points'];
      }
      if (detail['actual_path'] != null) {
        merged['actual_path'] = detail['actual_path'];
      }
      if (detail['trip'] is Map<String, dynamic>) {
        final existingTrip = (merged['trip'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(merged['trip'] as Map)
            : <String, dynamic>{};
        merged['trip'] = {
          ...existingTrip,
          ...Map<String, dynamic>.from(detail['trip']),
        };

        // Also preserve polylines if they are on the trip object.
        final t = Map<String, dynamic>.from(detail['trip']);
        if (t['route_points'] != null) {
          (merged['trip'] as Map<String, dynamic>)['route_points'] = t['route_points'];
        } else if (detail['route_points'] != null) {
          (merged['trip'] as Map<String, dynamic>)['route_points'] = detail['route_points'];
        }
        if (t['actual_path'] != null) {
          (merged['trip'] as Map<String, dynamic>)['actual_path'] = t['actual_path'];
        } else if (detail['actual_path'] != null) {
          (merged['trip'] as Map<String, dynamic>)['actual_path'] = detail['actual_path'];
        }
      }

      if (detail['driver'] is Map<String, dynamic>) {
        final existingDriver = (merged['driver'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(merged['driver'] as Map)
            : <String, dynamic>{};
        merged['driver'] = {
          ...existingDriver,
          ...Map<String, dynamic>.from(detail['driver']),
        };
      }
      if (detail['vehicle'] is Map<String, dynamic>) {
        final existingVehicle = (merged['vehicle'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(merged['vehicle'] as Map)
            : <String, dynamic>{};
        merged['vehicle'] = {
          ...existingVehicle,
          ...Map<String, dynamic>.from(detail['vehicle']),
        };
      }

      if (detail['route'] is Map<String, dynamic>) {
        if (merged['route'] == null) {
          merged['route'] = Map<String, dynamic>.from(detail['route']);
        } else if (merged['route'] is Map<String, dynamic>) {
          final r = Map<String, dynamic>.from(merged['route']);
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

      if (detail['stop_breakdown'] != null) {
        merged['stop_breakdown'] = detail['stop_breakdown'];
      }
      if (detail['fare_calculation'] != null) {
        merged['fare_calculation'] = detail['fare_calculation'];
      }
      if (detail['fare_data'] != null) {
        merged['fare_data'] = detail['fare_data'];
      }
      if (detail['booking_info'] != null) {
        merged['booking_info'] = detail['booking_info'];
      }
    } catch (_) {
      // Ignore network errors and keep using existing data
    }

    return merged;
  }

  String _destinationName(Map<String, dynamic> b) {
    try {
      final rn = (b['route_names'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (rn.isNotEmpty) return rn.last;
    } catch (_) {}

    if (b['route'] is Map<String, dynamic>) {
      final route = b['route'] as Map<String, dynamic>;
      if (route['stops'] is List && (route['stops'] as List).isNotEmpty) {
        final lastStop = route['stops'].last;
        final name = lastStop['name']?.toString();
        if (name != null && name.trim().isNotEmpty) return name.trim();
      }
    }

    final to = b['to_location'] ?? b['trip']?['to_location'];
    if (to is String && to.isNotEmpty && to.toLowerCase() != 'unknown') return to;
    final desc = b['description']?.toString();
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
    final origin = _originName(booking);
    final destination = _destinationName(booking);

    final tripDateStr = booking['trip_date'] ?? booking['trip']?['trip_date'];
    DateTime? tripDate;
    if (tripDateStr is String && tripDateStr.isNotEmpty) {
      try {
        tripDate = DateTime.parse(tripDateStr);
      } catch (_) {}
    }

    final departureTime = booking['departure_time'] ?? booking['trip']?['departure_time'];
    final seats = booking['number_of_seats'] ?? booking['seats'];
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final totalSeats = asInt(seats);
    int maleSeats = asInt(booking['male_seats']);
    int femaleSeats = asInt(booking['female_seats']);
    String seatDisplay;
    if ((maleSeats + femaleSeats) > 0) {
      seatDisplay = 'Total $totalSeats (M:$maleSeats F:$femaleSeats)';
    } else {
      seatDisplay = totalSeats > 0 ? totalSeats.toString() : 'N/A';
    }
    final price = booking['total_fare'] ?? booking['custom_price'];
    final status = booking['status'] ?? booking['booking_status'] ?? 'unknown';

    final driver = _asMap(booking['driver'] ?? booking['trip']?['driver']);
    final vehicle = _asMap(booking['vehicle'] ?? booking['trip']?['vehicle']);

    final driverName = _asString(driver['full_name'] ?? driver['name'] ?? driver['username'], 'N/A');

    String driverRatingDisplay;
    final dynamic rawDriverRating = driver['driver_rating'] ?? driver['rating'];
    if (rawDriverRating is num) {
      driverRatingDisplay = rawDriverRating.toStringAsFixed(1);
    } else if (rawDriverRating is String) {
      final parsed = double.tryParse(rawDriverRating);
      driverRatingDisplay = parsed != null ? parsed.toStringAsFixed(1) : 'N/A';
    } else {
      driverRatingDisplay = 'N/A';
    }

    final vehicleName = _asString(vehicle['vehicle_name'] ?? vehicle['model'], 'N/A');
    final licensePlate = _asString(
      vehicle['license_plate'] ??
          vehicle['registration_number'] ??
          vehicle['plate_number'],
      'N/A',
    );

    final bookingStatusDisplay = status.toString().toUpperCase();

    bool canCancelBooking(String status) {
      final lowerStatus = status.toLowerCase();
      return lowerStatus == 'pending' ||
          lowerStatus == 'active' ||
          lowerStatus == 'requested' ||
          lowerStatus == 'booked' ||
          lowerStatus == 'confirmed';
    }

    Future<void> cancelBooking(BuildContext ctx) async {
      final rawId = booking['id'] ?? booking['db_id'] ?? booking['booking_id'];
      int? bookingId;
      if (rawId is int) {
        bookingId = rawId;
      } else if (rawId is String) {
        bookingId = int.tryParse(rawId);
      }

      if (bookingId == null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Cannot cancel booking: invalid booking ID')), 
        );
        return;
      }

      try {
        final resp = await ApiService.cancelBooking(bookingId, 'Cancelled by passenger');
        if (!ctx.mounted) return;
        if (resp['success'] == true) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Booking cancelled successfully'), backgroundColor: Colors.green),
          );
          Navigator.of(ctx).pop(true);
        } else {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('Failed to cancel booking: ${resp['error'] ?? 'Unknown error'}')),
          );
        }
      } catch (e) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error cancelling booking: $e')),
        );
      }
    }

    String normalizePaymentStatus(dynamic raw) {
      if (raw == null) return 'PENDING';
      final s = raw.toString().trim().toUpperCase();
      if (s.isEmpty || s == 'UNKNOWN') return 'PENDING';
      if (s == 'PAID' || s == 'COMPLETED') return 'PAID';
      if (s == 'PENDING' || s == 'UNPAID') return 'PENDING';
      if (s == 'CANCELLED' || s == 'CANCELED') return 'CANCELLED';
      return s;
    }

    final paymentStatus = normalizePaymentStatus(
      booking['payment_status'] ??
      booking['payment']?['status'] ??
      booking['payment_status_display'],
    );

    // Additional trip / fare context for passenger view
    final trip = _asMap(booking['trip']);
    final fareData = _asMap(booking['fare_data']);
    final bookingInfo = _asMap(booking['booking_info']);

    final dynamic isNegotiableDynamic = trip['is_negotiable'] ?? bookingInfo['is_negotiable'];
    final bool isNegotiable = isNegotiableDynamic is bool
        ? isNegotiableDynamic
        : ((isNegotiableDynamic?.toString() ?? '').toLowerCase() == 'true');

    final dynamic pricePerSeatDynamic =
        bookingInfo['price_per_seat'] ?? fareData['base_fare_per_seat'] ?? fareData['base_fare'] ?? trip['base_fare'];

    num? asNum(dynamic v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    final num? pricePerSeatNum = asNum(pricePerSeatDynamic);

    final num? distanceKm =
        asNum(fareData['total_distance_km'] ?? trip['distance_km'] ?? trip['distance']);
    final num? durationMinutes =
        asNum(fareData['total_duration_minutes'] ?? trip['duration_minutes'] ?? trip['duration']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Details'),
        actions: [
          IconButton(
            tooltip: 'Share trip link',
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              final tripId = (booking['trip_id'] ?? booking['trip']?['trip_id'])?.toString() ?? '';
              if (tripId.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Missing trip id')),
                );
                return;
              }

              int? bookingId;
              final rawId = booking['id'] ?? booking['db_id'] ?? booking['booking_id'];
              if (rawId is int) {
                bookingId = rawId;
              } else if (rawId is String) {
                bookingId = int.tryParse(rawId);
              }

              String shareUrl = '';
              try {
                final res = await ApiService.createTripShareUrl(
                  tripId: tripId,
                  role: 'passenger',
                  bookingId: bookingId,
                );
                if (res['success'] == true) {
                  shareUrl = (res['share_url'] ?? '').toString();
                }
              } catch (_) {}

              if (!context.mounted) return;

              final urlToShare = shareUrl.trim();
              if (urlToShare.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to generate share link')),
                );
                return;
              }

              await Share.share(urlToShare);
            },
          ),
          IconButton(
            tooltip: 'View Negotiation',
            icon: const Icon(Icons.handshake),
            onPressed: () {
              final hasAnyId = booking['booking_id'] ?? booking['id'] ?? booking['db_id'] ?? booking['trip_id'];
              if (hasAnyId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No negotiation details available for this booking')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NegotiationDetailsScreen(
                    userData: userData,
                    booking: booking,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Chat with Driver',
            icon: const Icon(Icons.chat),
            onPressed: () {
              final tripId = (booking['trip_id'] ?? booking['trip']?['trip_id'])?.toString();
              if (tripId == null || tripId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat is only available for bookings linked to a trip')),
                );
                return;
              }

              final driver = _asMap(booking['driver'] ?? booking['trip']?['driver']);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PassengerChatScreen(
                    userData: userData,
                    tripId: tripId,
                    chatRoomId: tripId,
                    driverInfo: driver,
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
          // Route Map card (lazy loads detailed path data)
          FutureBuilder<Map<String, dynamic>>(
            future: _loadBookingDetails(),
            builder: (context, snapshot) {
              final isLoading = snapshot.connectionState == ConnectionState.waiting;
              final data = snapshot.data ?? booking;

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
                          Icon(Icons.map, color: Colors.blueAccent),
                          SizedBox(width: 8),
                          Text('Route Map',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
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

          // Booking Status card
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
                      Icon(Icons.bookmark, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Booking Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(bookingStatusDisplay),
                      ),
                      Chip(
                        label: Text('Payment: $paymentStatus'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Trip Information card
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
                            _buildInfoRow(Icons.star, 'Rating: $driverRatingDisplay / 5'),
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
                            _buildInfoRow(Icons.confirmation_number, 'License Plate: $licensePlate'),
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
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Route Details card
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
                      Icon(Icons.alt_route, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Route Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: const [
                          Icon(Icons.fiber_manual_record, color: Colors.green, size: 16),
                          SizedBox(height: 24),
                          Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pickup', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(origin),
                            const SizedBox(height: 16),
                            const Text('Drop-off', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(destination),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Fare Details card
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
                  if (seats != null)
                    _buildInfoRow(Icons.event_seat, 'Number of Seats: $seatDisplay'),
                  if (pricePerSeatNum != null)
                    _buildInfoRow(Icons.monetization_on,
                        'Price per seat: ₨${pricePerSeatNum.toStringAsFixed(0)}'),
                  if (price != null)
                    _buildInfoRow(Icons.money, 'Total Fare: ₨${price.toString()}'),
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

          if (booking['description']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(booking['description'].toString()),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (canCancelBooking(status))
            ElevatedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Cancel Booking'),
                    content: Text(
                      'Are you sure you want to cancel your booking for the ride from $origin to $destination?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('No'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Cancel Booking'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  if (!context.mounted) return;
                  await cancelBooking(context);
                }
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Booking'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapSection(BuildContext context, Map<String, dynamic> dataSource) {
    final points = <LatLng>[];
    final names = <String>[];

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    List<LatLng> parsePolyline(dynamic raw) {
      dynamic normalized = raw;
      if (normalized is String) {
        try {
          normalized = json.decode(normalized);
        } catch (_) {
          normalized = null;
        }
      }
      if (normalized is! List) return <LatLng>[];
      final out = <LatLng>[];
      for (final p in normalized) {
        if (p is! Map) continue;
        final lat = toDouble(p['lat'] ?? p['latitude']);
        final lng = toDouble(p['lng'] ?? p['longitude']);
        if (lat != null && lng != null) {
          out.add(LatLng(lat, lng));
        }
      }
      return out;
    }

    // Prefer backend-provided geometry if available (authoritative route line).
    // NOTE: For recreated/hybrid rides we persist the selected/hybrid geometry into
    // `route_points`, while `actual_path` (if present) may still represent the
    // original purely-actual track. So `route_points` must take precedence.
    final backendRoutePoints = parsePolyline(
      dataSource['route_points'] ??
          dataSource['route_points_list'] ??
          dataSource['route_points_polyline'] ??
          dataSource['trip']?['route_points'] ??
          dataSource['trip']?['route']?['route_points'] ??
          dataSource['route']?['route_points'],
    );
    final backendActualPath = parsePolyline(
      dataSource['actual_path'] ??
          dataSource['trip']?['actual_path'] ??
          dataSource['trip']?['route']?['actual_path'],
    );
    // Prefer `route_points` (supports hybrid). Only fall back to `actual_path` if
    // route_points is missing.
    final polylineOverride = backendRoutePoints.length >= 2
        ? backendRoutePoints
        : (backendActualPath.length >= 2 ? backendActualPath : <LatLng>[]);

    // 1) Try to build from stop_breakdown segment coordinates for better path approximation
    List<dynamic> stopBreakdown = const [];
    if (dataSource['stop_breakdown'] is List) {
      stopBreakdown = List<dynamic>.from(dataSource['stop_breakdown']);
    } else if (dataSource['fare_calculation'] is Map &&
        (dataSource['fare_calculation'] as Map)['stop_breakdown'] is List) {
      stopBreakdown =
          List<dynamic>.from((dataSource['fare_calculation'] as Map)['stop_breakdown']);
    }

    if (stopBreakdown.isNotEmpty) {
      stopBreakdown.sort((a, b) {
        final am = a as Map<String, dynamic>;
        final bm = b as Map<String, dynamic>;
        final ao = (am['from_stop_order'] ?? 0) as int;
        final bo = (bm['from_stop_order'] ?? 0) as int;
        final at = (am['to_stop_order'] ?? 0) as int;
        final bt = (bm['to_stop_order'] ?? 0) as int;
        if (ao != bo) return ao.compareTo(bo);
        return at.compareTo(bt);
      });

      LatLng? lastPoint;

      LatLng? mk(Map? c) {
        if (c == null) return null;
        final lat = c['lat'] as num?;
        final lng = c['lng'] as num?;
        if (lat == null || lng == null) return null;
        return LatLng(lat.toDouble(), lng.toDouble());
      }

      for (final raw in stopBreakdown) {
        if (raw is! Map<String, dynamic>) continue;
        final fromC = raw['from_coordinates'] as Map?;
        final toC = raw['to_coordinates'] as Map?;

        final fromPoint = mk(fromC);
        final toPoint = mk(toC);

        if (fromPoint != null) {
          final lp = lastPoint;
          if (lp == null || lp.latitude != fromPoint.latitude || lp.longitude != fromPoint.longitude) {
            points.add(fromPoint);
            names.add(raw['from_stop_name']?.toString() ?? 'Stop');
            lastPoint = fromPoint;
          }
        }

        if (toPoint != null) {
          final lp = lastPoint;
          if (lp == null || lp.latitude != toPoint.latitude || lp.longitude != toPoint.longitude) {
            points.add(toPoint);
            names.add(raw['to_stop_name']?.toString() ?? 'Stop');
            lastPoint = toPoint;
          }
        }
      }
    }

    // 2) Fallback to route stops if we didn't get usable segment coordinates
    if (points.isEmpty) {
      final stops = _extractStopsFromBooking(dataSource);
      if (stops.isEmpty) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.33,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text('Map not available for this booking'),
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
          child: Text('Map not available for this booking'),
        ),
      );
    }

    final center = MapUtil.centerFromPoints(polylineOverride.isNotEmpty ? polylineOverride : points);

    // Determine which part of the route the passenger actually booked so we can
    // visually distinguish it. We rely on either explicit stop orders or names
    // present in the booking payload.
    debugPrint('[BOOKING_MAP] raw booking_info: ${dataSource['booking_info']}');
    int? passengerFromOrder;
    int? passengerToOrder;

    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    // Orders provided directly in booking_info (full booking detail API)
    final bookingInfo = dataSource['booking_info'];
    if (bookingInfo is Map<String, dynamic>) {
      passengerFromOrder = toInt(
        bookingInfo['from_stop_order'] ??
        bookingInfo['pickup_stop_order'] ??
        bookingInfo['from_stop'],
      );
      passengerToOrder = toInt(
        bookingInfo['to_stop_order'] ??
        bookingInfo['dropoff_stop_order'] ??
        bookingInfo['to_stop'],
      );
      debugPrint('[BOOKING_MAP] booking_info resolved orders: from=$passengerFromOrder to=$passengerToOrder');
    }

    // Many MyBookings summaries put the passenger segment directly on the
    // booking object (e.g. from_stop_order / to_stop_order). Use these as a
    // primary fallback when booking_info is missing.
    passengerFromOrder ??= toInt(
      dataSource['from_stop_order'] ??
      dataSource['pickup_stop_order'] ??
      dataSource['from_stop'],
    );
    passengerToOrder ??= toInt(
      dataSource['to_stop_order'] ??
      dataSource['dropoff_stop_order'] ??
      dataSource['to_stop'],
    );
    debugPrint('[BOOKING_MAP] root-level resolved orders: from=$passengerFromOrder to=$passengerToOrder');

    // Fallback by matching pickup/drop-off stop names against breakdown orders
    if (passengerFromOrder == null || passengerToOrder == null) {
      final pickupName = (dataSource['pickup_stop'] ??
              dataSource['pickup_stop_name'] ??
              dataSource['from_stop'] ??
              dataSource['from'] ??
              dataSource['pickup'])
          ?.toString();
      final dropName = (dataSource['dropoff_stop'] ??
              dataSource['dropoff_stop_name'] ??
              dataSource['to_stop'] ??
              dataSource['to'] ??
              dataSource['dropoff'])
          ?.toString();
      if (pickupName != null || dropName != null) {
        debugPrint('[BOOKING_MAP] fallback by names: pickupName=$pickupName dropName=$dropName');
        for (final raw in stopBreakdown) {
          if (raw is! Map<String, dynamic>) continue;
          final fromName = raw['from_stop_name']?.toString();
          final toName = raw['to_stop_name']?.toString();
          final fromOrder = toInt(raw['from_stop_order'] ?? raw['from_stop']);
          final toOrder = toInt(raw['to_stop_order'] ?? raw['to_stop']);

          if (pickupName != null && passengerFromOrder == null && fromName == pickupName) {
            passengerFromOrder = fromOrder;
          }
          if (dropName != null && passengerToOrder == null && toName == dropName) {
            passengerToOrder = toOrder;
          }
        }
        debugPrint('[BOOKING_MAP] fallback resolved orders: from=$passengerFromOrder to=$passengerToOrder');
      }
    }

    bool isWithinPassengerSegment(int orderIndex) {
      // If we could not resolve passenger stop orders, fall back to
      // treating the full route as the passenger segment.
      if (passengerFromOrder == null || passengerToOrder == null) return true;
      if (orderIndex < passengerFromOrder) return false;
      if (orderIndex > passengerToOrder) return false;
      return true;
    }

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
            if (polylineOverride.length >= 2)
              MapUtil.buildPolylineLayer(points: polylineOverride)
            else
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
                        Builder(
                          builder: (context) {
                            // Stop orders in breakdown are 1-based; align marker index
                            final stopOrder = i + 1;
                            final within = isWithinPassengerSegment(stopOrder);

                            // Derive pickup/drop indexes strictly from passenger stop orders.
                            // When orders are not available, we do not force a fake
                            // pickup/drop marker. Instead we simply show all stops.
                            int? pickupIndex =
                                (passengerFromOrder != null) ? passengerFromOrder - 1 : null;
                            int? dropIndex =
                                (passengerToOrder != null) ? passengerToOrder - 1 : null;

                            Color baseColor;
                            if (pickupIndex != null && i == pickupIndex) {
                              // Passenger pickup point – green
                              baseColor = const Color(0xFF4CAF50);
                            } else if (dropIndex != null && i == dropIndex) {
                              // Passenger drop-off point – red
                              baseColor = const Color(0xFFE53935);
                            } else {
                              // Other in-route stops – orange by default
                              baseColor = const Color(0xFFFF9800);
                            }

                            final color = within ? baseColor : Colors.grey;

                            IconData icon;
                            if (pickupIndex != null && i == pickupIndex) {
                              icon = Icons.trip_origin;
                            } else if (dropIndex != null && i == dropIndex) {
                              icon = Icons.place;
                            } else {
                              icon = Icons.location_on;
                            }

                            // Log first few markers to understand coloring behaviour
                            if (i < 5) {
                              debugPrint('[BOOKING_MAP] marker index=$i order=$stopOrder within=$within pickupIndex=$pickupIndex dropIndex=$dropIndex color=$color name=${i < names.length ? names[i] : 'Stop ${i + 1}'}');
                            }

                            return Icon(
                              icon,
                              color: color,
                              size: 32,
                            );
                          },
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

  List<dynamic> _extractStopsFromBooking(Map<String, dynamic> dataSource) {
    if (dataSource['route_stops'] is List) {
      return List<dynamic>.from(dataSource['route_stops']);
    }
    if (dataSource['route'] is Map && dataSource['route']['stops'] is List) {
      return List<dynamic>.from(dataSource['route']['stops']);
    }
    if (dataSource['trip'] is Map && dataSource['trip']['route'] is Map && dataSource['trip']['route']['stops'] is List) {
      return List<dynamic>.from(dataSource['trip']['route']['stops']);
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

