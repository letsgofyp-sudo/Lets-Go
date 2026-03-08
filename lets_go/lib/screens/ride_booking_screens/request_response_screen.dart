import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lets_go/services/api_service.dart';
import 'package:lets_go/utils/image_utils.dart';

class RequestResponseScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String tripId;
  final Map<String, dynamic> request;

  const RequestResponseScreen({
    super.key,
    required this.userData,
    required this.tripId,
    required this.request,
  });

  @override
  State<RequestResponseScreen> createState() => _RequestResponseScreenState();
}

class _RequestResponseScreenState extends State<RequestResponseScreen> {
  bool _submitting = false;
  String? _error;
  final TextEditingController _counterFareCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  bool _loading = true;
  bool _canRespond = true;
  Map<String, dynamic>? _details; // fetched detailed booking
  List<Map<String, dynamic>> _history = [];

  Timer? _pollTimer;
  bool _pollInFlight = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _counterFareCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _startPolling();
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
        await _loadDetails(silent: true);
      } finally {
        _pollInFlight = false;
      }
    });
  }

  Future<void> _loadDetails({bool silent = false}) async {
    final bookingId = _bookingId;
    if (bookingId == null) {
      setState(() {
        _loading = false;
        _error = 'Missing booking id';
      });
      return;
    }
    try {
      final res = await ApiService.getNegotiationHistory(
        tripId: widget.tripId,
        bookingId: bookingId,
      );
      if (!mounted) return;
      setState(() {
        final booking = res['booking'];
        _details = booking is Map<String, dynamic>
            ? booking
            : (booking is Map ? Map<String, dynamic>.from(booking) : widget.request);
        final hist = res['history'];
        _history = hist is List
            ? hist.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        _canRespond = res['can_respond'] == true;
        if (!silent) {
          _loading = false;
        }
      });

      if (!_canRespond) {
        _pollTimer?.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _details = widget.request; // fallback to list data
        _history = [];
        _canRespond = true;
        if (!silent) {
          _loading = false;
        }
        _error = null; // don't block UI
      });
    }
  }

  int get _driverId => int.tryParse(widget.userData['id']?.toString() ?? '') ?? 0;
  int? get _bookingId => (widget.request['booking_id'] as int?) ?? int.tryParse(widget.request['id']?.toString() ?? '');

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  int? _parseCounterFareStrict() {
    final raw = _counterFareCtrl.text.trim();
    if (raw.isEmpty) return null;
    if (raw.contains('.')) return null;
    return int.tryParse(raw);
  }

  double? _computeFinalFarePerSeat(Map<String, dynamic> req) {
    final v = req['final_fare_per_seat'] ??
        req['final_fare'] ??
        req['accepted_fare_per_seat'] ??
        req['negotiated_fare_per_seat'] ??
        req['negotiated_fare'] ??
        req['passenger_offer_per_seat'] ??
        req['passenger_offer'] ??
        req['original_fare_per_seat'];
    return _asDouble(v);
  }

  String? _passengerPhotoUrl(Map<String, dynamic> req) {
    final raw = req['passenger_photo_url'] ??
        req['passenger_profile_image'] ??
        req['passenger_image'] ??
        req['photo_url'] ??
        req['profile_image'];
    final ensured = ImageUtils.ensureValidImageUrl(raw?.toString());
    if (ensured != null && ImageUtils.isValidImageUrl(ensured)) {
      return ensured;
    }
    return null;
  }

  Future<void> _respond({required String action}) async {
    if (_bookingId == null) {
      setState(() => _error = 'Missing booking id');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final int? counterFare = action == 'counter' ? _parseCounterFareStrict() : null;
      if (action == 'counter' && (counterFare == null || counterFare <= 0)) {
        setState(() {
          _error = 'Invalid format. Enter an integer fare (no decimals).';
          _submitting = false;
        });
        return;
      }
      final res = await ApiService.respondBookingRequest(
        tripId: widget.tripId,
        bookingId: _bookingId!,
        action: action,
        driverId: _driverId,
        counterFare: counterFare,
        reason: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );
      final bool success =
          res['success'] == true || !res.containsKey('success');
      if (success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Request updated successfully')),
        );
        await _loadDetails(silent: true);
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = null;
        });
        return;
      } else {
        setState(() {
          _error = res['error']?.toString() ?? 'Unknown error';
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
    final req = _details ?? widget.request;
    final raw = widget.request;

    final passengerName = (req['passenger_name'] ?? raw['passenger_name'] ?? 'Passenger').toString();
    final seats = _asInt(req['number_of_seats'] ?? raw['number_of_seats']) ?? 1;
    final status = (req['bargaining_status'] ?? raw['bargaining_status'] ?? 'PENDING').toString();
    final passengerId = _asInt(req['passenger_id'] ?? raw['passenger_id']);
    final fromName = (req['from_stop_name'] ?? raw['from_stop_name'] ?? 'Origin').toString();
    final toName = (req['to_stop_name'] ?? raw['to_stop_name'] ?? 'Destination').toString();
    final offerPerSeat = (req['passenger_offer_per_seat'] ?? raw['passenger_offer_per_seat']) as num?;
    final originalFare = (req['original_fare_per_seat'] ?? raw['original_fare_per_seat']) as num?;
    final negotiatedFare = (req['negotiated_fare_per_seat'] ?? raw['negotiated_fare_per_seat']) as num?;
    final message = (req['passenger_message'] ?? raw['passenger_message'] ?? '').toString();
    final gender = (req['passenger_gender'] ?? raw['passenger_gender'] ?? '').toString();
    final rating = (req['passenger_rating'] ?? raw['passenger_rating']) as num?;
    final requestedAt = (req['requested_at'] ?? raw['requested_at'] ?? '').toString();

    int maleSeats = _asInt(req['male_seats'] ?? raw['male_seats']) ?? 0;
    int femaleSeats = _asInt(req['female_seats'] ?? raw['female_seats']) ?? 0;
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

    final finalFarePerSeat = _computeFinalFarePerSeat(req);
    final finalTotal = (finalFarePerSeat != null) ? (finalFarePerSeat.round() * seats) : null;

    // Keep using a valid passenger photo URL even after detailed history loads
    // Some detail payloads may omit passenger_photo_url, so fall back to the
    // original request map when needed.
    final passengerPhotoUrl = _passengerPhotoUrl(req) ?? _passengerPhotoUrl(raw);

    return Scaffold(
      appBar: AppBar(title: const Text('Respond to Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
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
                              if (passengerPhotoUrl != null &&
                                  ImageUtils.isValidImageUrl(passengerPhotoUrl))
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
                              if (requestedAt.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Requested at: $requestedAt', style: const TextStyle(color: Colors.grey)),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                          child: Text(status, style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.route, size: 18, color: Colors.teal),
                              SizedBox(width: 8),
                              Text('Route & Seats', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Pickup: $fromName'),
                          Text('Drop-off: $toName'),
                          const SizedBox(height: 4),
                          Text('Seats: $seats (M:$maleSeats F:$femaleSeats)'),
                          if (gender.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Passenger gender: $gender'),
                          ],
                        ],
                      ),
                    ),
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
                        Icon(Icons.person_pin_circle, color: Colors.teal),
                        SizedBox(width: 8),
                        Text('Passenger Request Details', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('From: $fromName'),
                    Text('To: $toName'),
                    const SizedBox(height: 4),
                    Text('Seats requested: $seats (M:$maleSeats F:$femaleSeats)'),
                    if (req['from_stop_order'] != null && req['to_stop_order'] != null) ...[
                      const SizedBox(height: 4),
                      Text('Stop Orders: ${req['from_stop_order']} → ${req['to_stop_order']}', style: const TextStyle(color: Colors.grey)),
                    ],
                    const SizedBox(height: 8),
                    if (originalFare != null)
                      Text('Base price (per seat): ₨${originalFare.round()}'),
                    if (offerPerSeat != null)
                      Text('Passenger offer (per seat): ₨${offerPerSeat.round()}'),
                    if (negotiatedFare != null)
                      Text('Your latest counter (per seat): ₨${negotiatedFare.round()}'),
                    if (originalFare != null && offerPerSeat != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Passenger offer is ₨${(originalFare - offerPerSeat).abs().round()} '
                        '${offerPerSeat < originalFare ? 'below' : 'above'} base per seat',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Passenger note:'),
                      const SizedBox(height: 2),
                      Text(message),
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
                        Icon(Icons.payments, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Final Fare', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (finalFarePerSeat != null)
                      Text('Per seat: ₨${finalFarePerSeat.round()}', style: const TextStyle(fontWeight: FontWeight.w600))
                    else
                      const Text('Per seat: —', style: TextStyle(color: Colors.grey)),
                    if (finalTotal != null)
                      Text('Total ($seats seat(s), M:$maleSeats F:$femaleSeats): ₨$finalTotal', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (!_canRespond) ...[
                      const SizedBox(height: 6),
                      const Text('Negotiation finalized', style: TextStyle(color: Colors.grey)),
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
                      const Text('No negotiation messages yet.', style: TextStyle(color: Colors.grey)),
                    if (_history.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ..._history.map((e) {
                            final action = (e['action'] ?? '').toString();
                            final ts = (e['ts'] ?? '').toString();
                            final actor = (e['actor_type'] ?? '').toString();
                            final price = (e['price_per_seat'] ?? e['counter_fare'])?.toString();
                            final seatsHist = e['seats'] ?? e['number_of_seats'];
                            final noteHist = (e['note'] ?? e['reason'] ?? '').toString();
                            final summary = StringBuffer()..write(action.replaceAll('_', ' '));
                            if (price != null) summary.write(' • ₨$price/seat');
                            if (seatsHist != null) summary.write(' • $seatsHist seat(s)');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(summary.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (noteHist.isNotEmpty)
                                    Text(noteHist, style: const TextStyle(fontSize: 12)),
                                  if (ts.isNotEmpty)
                                    Text(ts, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  if (actor.isNotEmpty)
                                    Text(actor, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_canRespond) ...[
              Text(
                'Your response',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
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
                  labelText: 'Notes / Reason (optional)',
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
                      onPressed: _submitting ? null : () => _respond(action: 'accept'),
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : () => _respond(action: 'counter'),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Counter'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : () => _respond(action: 'reject'),
                      icon: const Icon(Icons.thumb_down),
                      label: const Text('Reject'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade700, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : () => _respond(action: 'block'),
                      icon: const Icon(Icons.block),
                      label: const Text('Block (this ride)'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : () => _respond(action: 'blacklist'),
                      icon: const Icon(Icons.no_accounts),
                      label: const Text('Add to blacklist'),
                    ),
                  ),
                ],
              ),
            ] else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Negotiation Completed', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'This request has reached a final state. You cannot change your response anymore.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            if (status.toUpperCase() == 'BLOCKED' && passengerId != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () async {
                          setState(() {
                            _submitting = true;
                            _error = null;
                          });
                          final res = await ApiService.unblockPassengerForTrip(
                            tripId: widget.tripId,
                            passengerId: passengerId,
                            driverId: _driverId,
                          );
                          if (!context.mounted) return;
                          if (res['success'] == true) {
                            await _loadDetails(silent: true);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res['message']?.toString() ?? 'Passenger unblocked')),
                            );
                            setState(() {
                              _submitting = false;
                            });
                          } else {
                            setState(() {
                              _submitting = false;
                              _error = (res['error'] ?? 'Failed to unblock passenger').toString();
                            });
                          }
                        },
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unblock (this ride)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
