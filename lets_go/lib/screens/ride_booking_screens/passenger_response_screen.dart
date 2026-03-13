import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lets_go/services/api_service.dart';
import 'package:lets_go/utils/image_utils.dart';

class PassengerResponseScreen extends StatefulWidget {
  final Map<String, dynamic> userData; // passenger
  final Map<String, dynamic> booking;  // booking item from My Bookings list

  const PassengerResponseScreen({
    super.key,
    required this.userData,
    required this.booking,
  });

  @override
  State<PassengerResponseScreen> createState() => _PassengerResponseScreenState();
}

class _PassengerResponseScreenState extends State<PassengerResponseScreen> {
  bool _submitting = false;
  String? _error;
  final TextEditingController _counterFareCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _canRespond = true;
  Map<String, dynamic>? _bookingDetails;
  List<Map<String, dynamic>> _history = [];

  Timer? _pollTimer;
  bool _pollInFlight = false;

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  bool _canAcceptNow(Map<String, dynamic> ride) {
    final bs = (ride['bargaining_status'] ?? '').toString().toUpperCase();
    if (bs == 'COUNTER_OFFER') return true;
    if (_history.isNotEmpty) {
      final a = (_history.last['action'] ?? '').toString();
      if (a == 'driver_counter') return true;
    }
    return false;
  }

  int? _resolveBookingPk(Map<String, dynamic> booking) {
    // IMPORTANT:
    // booking['booking_id'] is often a human-readable string like "B123-...".
    // For API calls we must use the numeric DB primary key (id/db_id).
    return _parseInt(booking['id']) ??
        _parseInt(booking['db_id']) ??
        _parseInt(booking['booking']?['id']) ??
        _parseInt(booking['booking_id']);
  }

  int? _parseCounterFareStrict() {
    final raw = _counterFareCtrl.text.trim();
    if (raw.isEmpty) return null;
    if (raw.contains('.')) return null;
    return int.tryParse(raw);
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  double? _computeFinalFarePerSeat(Map<String, dynamic> ride) {
    return _parseDouble(
      ride['final_fare_per_seat'] ??
          ride['final_fare'] ??
          ride['accepted_fare_per_seat'] ??
          ride['negotiated_fare'] ??
          ride['passenger_offer'] ??
          ride['original_fare_per_seat'],
    );
  }

  String? _passengerPhotoUrl(Map<String, dynamic> ride) {
    final raw = ride['passenger_photo_url'] ??
        ride['passenger_profile_image'] ??
        ride['passenger_image'] ??
        ride['photo_url'] ??
        ride['profile_image'];
    final ensured = ImageUtils.ensureValidImageUrl(raw?.toString());
    if (ensured != null && ImageUtils.isValidImageUrl(ensured)) {
      return ensured;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _counterFareCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      if (_submitting) return;
      if (_pollInFlight) return;
      if (!_canRespond) {
        _pollTimer?.cancel();
        return;
      }

      _pollInFlight = true;
      try {
        await _loadHistory(showLoading: false);
      } finally {
        _pollInFlight = false;
      }
    });
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final baseBooking = widget.booking;
      final tripId = (baseBooking['trip_id'] ?? baseBooking['trip']?['trip_id'])?.toString();
      final bookingId = _resolveBookingPk(baseBooking);

      if (tripId == null || bookingId == null) {
        setState(() {
          _loading = false;
          _canRespond = true;
          _bookingDetails = baseBooking;
          _history = [];
          _error = 'Missing trip/booking id';
        });
        return;
      }

      final res = await ApiService.getNegotiationHistory(
        tripId: tripId,
        bookingId: bookingId,
      );

      if (!mounted) return;
      setState(() {
        final booking = res['booking'];
        _bookingDetails = booking is Map<String, dynamic>
            ? booking
            : (booking is Map ? Map<String, dynamic>.from(booking) : baseBooking);
        final hist = res['history'];
        _history = hist is List
            ? hist.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        _canRespond = res['can_respond'] == true;
        if (showLoading) {
          _loading = false;
        }
      });

      if (!_canRespond) {
        _pollTimer?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingDetails = widget.booking;
        _history = [];
        _canRespond = true;
        if (showLoading) {
          _loading = false;
        }
        _error = 'Failed to load history: $e';
      });
    }
  }

  Future<void> _respond(String action) async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Resolve identifiers
      final tripId = (widget.booking['trip_id'] ?? widget.booking['trip']?['trip_id'])?.toString();
      final bookingId = _resolveBookingPk(widget.booking);
      final passengerId = _parseInt(widget.booking['passenger_id'])
          ?? _parseInt(widget.booking['passenger']?['id'])
          ?? _parseInt(widget.userData['id']);
      if (tripId == null || bookingId == null || passengerId == null) {
        setState(() {
          _error = 'Missing trip/booking/passenger id';
          _submitting = false;
        });
        return;
      }

      int? cf;
      if (action == 'counter') {
        cf = _parseCounterFareStrict();
        if (cf == null || cf <= 0) {
          setState(() {
            _error = 'Invalid format. Enter an integer fare (no decimals).';
            _submitting = false;
          });
          return;
        }
      }

      // Call backend endpoint
      final res = await ApiService.passengerRespondBooking(
        tripId: tripId,
        bookingId: bookingId,
        action: action,
        passengerId: passengerId,
        counterFare: cf,
        note: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );
      if (res['success'] != true) {
        setState(() {
          _error = res['error']?.toString() ?? 'Failed to submit response';
          _submitting = false;
        });
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'counter' ? 'Counter offer sent' : 'Response submitted')),
      );
      await _loadHistory();
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _bookingDetails ?? widget.booking;
    final fromLocation = ride['from_location'] ?? ride['from_stop_name'] ?? 'Origin';
    final toLocation = ride['to_location'] ?? ride['to_stop_name'] ?? 'Destination';
    final bookingStatus = (ride['booking_status'] ?? ride['status'] ?? '').toString();
    final bargainingStatus = (ride['bargaining_status'] ?? 'Pending').toString();
    final negotiatedFare = (ride['negotiated_fare'] as num?)?.toInt();
    final passengerOffer = (ride['passenger_offer'] as num?)?.toInt();
    final finalFarePerSeat = (ride['final_fare_per_seat'] as num?)?.toInt();

    final passengerName = (ride['passenger_name'] ?? widget.userData['name'] ?? 'Passenger').toString();
    final gender = (ride['passenger_gender'] ?? widget.userData['gender'] ?? '').toString();
    final rating = _parseDouble(ride['passenger_rating'] ?? widget.userData['rating']);
    final seats = _parseInt(ride['number_of_seats'] ?? ride['seats']) ?? 1;

    int maleSeats = _parseInt(ride['male_seats']) ?? 0;
    int femaleSeats = _parseInt(ride['female_seats']) ?? 0;
    if ((maleSeats + femaleSeats) <= 0) {
      final g = gender.toLowerCase();
      if (g == 'female') {
        femaleSeats = seats;
        maleSeats = 0;
      } else if (g == 'male') {
        maleSeats = seats;
        femaleSeats = 0;
      }
    }

    final computedFinalFarePerSeat = _computeFinalFarePerSeat(ride);
    final finalTotal = computedFinalFarePerSeat != null ? computedFinalFarePerSeat.round() * seats : null;

    final canAccept = _canAcceptNow(ride);

    final passengerPhotoUrl = _passengerPhotoUrl(ride) ?? _passengerPhotoUrl(widget.userData);

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Negotiation',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 56,
                                height: 56,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      child: Text(passengerName.isNotEmpty ? passengerName[0].toUpperCase() : 'P'),
                                    ),
                                    if (passengerPhotoUrl != null && ImageUtils.isValidImageUrl(passengerPhotoUrl))
                                      ClipOval(
                                        child: Image.network(
                                          passengerPhotoUrl,
                                          width: 56,
                                          height: 56,
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(passengerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                        if (gender.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Icon(gender.toLowerCase() == 'female' ? Icons.female : Icons.male, size: 16, color: Colors.grey),
                                        ],
                                        if (rating != null) ...[
                                          const SizedBox(width: 6),
                                          Icon(Icons.star, color: Colors.amber.shade600, size: 16),
                                          Text(rating.toStringAsFixed(1)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Seats: $seats (M:$maleSeats F:$femaleSeats)',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.directions_car, color: Color(0xFF00897B)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$fromLocation → $toLocation',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                                child: Text(
                                  bargainingStatus,
                                  style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (negotiatedFare != null)
                            Text('Driver counter (per seat): PKR $negotiatedFare'),
                          if (passengerOffer != null)
                            Text('Your last offer (per seat): PKR $passengerOffer'),
                          const SizedBox(height: 8),
                          if (computedFinalFarePerSeat != null)
                            Text(
                              'Final fare: PKR ${computedFinalFarePerSeat.round()}/seat'
                              '${finalTotal != null ? ' • PKR $finalTotal total' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          if (!_canRespond) ...[
                            const SizedBox(height: 4),
                            Text('Status: $bookingStatus ($bargainingStatus)'),
                            if (finalFarePerSeat != null)
                              Text('Final fare per seat: PKR $finalFarePerSeat')
                            else if (negotiatedFare != null)
                              Text('Final fare per seat: PKR $negotiatedFare')
                            else if (passengerOffer != null)
                              Text('Final fare per seat: PKR $passengerOffer'),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(_error!, style: const TextStyle(color: Colors.red)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.history, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Negotiation History', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_history.isEmpty)
                            const Text('No negotiation messages yet.', style: TextStyle(color: Colors.grey))
                          else
                            ..._history.map((e) {
                              final action = (e['action'] ?? '').toString();
                              final ts = (e['ts'] ?? '').toString();
                              final actor = (e['actor_type'] ?? '').toString();
                              final price = (e['price_per_seat'] ?? e['counter_fare'])?.toString();
                              final seats = e['seats'] ?? e['number_of_seats'];
                              final note = (e['note'] ?? e['reason'] ?? '').toString();
                              final summary = StringBuffer()..write(action.replaceAll('_', ' '));
                              if (price != null) summary.write(' • PKR $price/seat');
                              if (seats != null) summary.write(' • $seats seat(s)');
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(summary.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 12)),
                                    if (ts.isNotEmpty) Text(ts, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    if (actor.isNotEmpty) Text(actor, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_canRespond)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _counterFareCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Counter Fare (PKR)',
                                hintText: 'Enter counter fare per seat',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Notes / Message (optional)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _submitting ? null : (canAccept ? () => _respond('accept') : null),
                                    icon: const Icon(Icons.check),
                                    label: const Text('Accept'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _submitting ? null : () => _respond('counter'),
                                    icon: const Icon(Icons.swap_horiz),
                                    label: const Text('Counter'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            if (!canAccept) ...[
                              const SizedBox(height: 6),
                              const Text('Waiting for driver counter offer…', style: TextStyle(color: Colors.grey)),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _submitting ? null : () => _respond('withdraw'),
                                    icon: const Icon(Icons.cancel),
                                    label: const Text('Withdraw'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade700, foregroundColor: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('This negotiation is finalized. You can no longer respond.', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
