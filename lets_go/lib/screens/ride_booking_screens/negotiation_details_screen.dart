import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lets_go/services/api_service.dart';

class NegotiationDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> userData; // current passenger
  final Map<String, dynamic> booking;  // booking item from My Bookings

  const NegotiationDetailsScreen({
    super.key,
    required this.userData,
    required this.booking,
  });

  @override
  State<NegotiationDetailsScreen> createState() => _NegotiationDetailsScreenState();
}

class _NegotiationDetailsScreenState extends State<NegotiationDetailsScreen> {
  final TextEditingController _counterFareCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

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

  int? _resolveBookingPk(Map<String, dynamic> booking) {
    // booking['booking_id'] may be a human readable string; prefer numeric PK.
    return _parseInt(booking['id']) ??
        _parseInt(booking['db_id']) ??
        _parseInt(booking['booking']?['id']) ??
        _parseInt(booking['booking_id']);
  }

  String? _latestAction() {
    if (_history.isEmpty) return null;
    final v = _history.last['action'];
    return v?.toString();
  }

  bool _canAcceptNow() {
    // Passenger should only accept when a DRIVER counter is the latest pending action.
    // This prevents passenger from accepting their own offer/request.
    return _latestAction() == 'driver_counter';
  }

  int? _parseCounterFareStrict() {
    final raw = _counterFareCtrl.text.trim();
    if (raw.isEmpty) return null;
    if (raw.contains('.')) return null;
    return int.tryParse(raw);
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
    _messageCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final baseBooking = _bookingDetails ?? widget.booking;
    final status = (baseBooking['booking_status'] ?? baseBooking['status'] ?? '').toString();
    final bargainingStatus = (baseBooking['bargaining_status'] ?? '').toString();
    final passengerOffer = (baseBooking['passenger_offer'] as num?)?.toInt();
    // negotiated_fare is only a "driver counter" if the driver actually countered.
    final normalizedBargaining = bargainingStatus.toUpperCase();
    final hasDriverCounter = normalizedBargaining.contains('COUNTER') || normalizedBargaining.contains('OFFER');
    final negotiatedFare = hasDriverCounter ? (baseBooking['negotiated_fare'] as num?)?.toInt() : null;
    final finalFarePerSeat = (baseBooking['final_fare_per_seat'] as num?)?.toInt();
    final notes = (baseBooking['negotiation_notes'] ?? '').toString();
    final driverResponse = (baseBooking['driver_response'] ?? '').toString();

    final totalSeats = _parseInt(baseBooking['number_of_seats'] ?? baseBooking['seats']) ?? 1;
    int maleSeats = _parseInt(baseBooking['male_seats']) ?? 0;
    int femaleSeats = _parseInt(baseBooking['female_seats']) ?? 0;
    if ((maleSeats + femaleSeats) <= 0) {
      final g = (baseBooking['passenger_gender'] ?? widget.userData['gender'] ?? '').toString().toLowerCase();
      if (g == 'female') {
        femaleSeats = totalSeats;
        maleSeats = 0;
      } else if (g == 'male') {
        maleSeats = totalSeats;
        femaleSeats = 0;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Negotiation Details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(status, bargainingStatus, negotiatedFare, passengerOffer, totalSeats, maleSeats, femaleSeats),
                  const SizedBox(height: 12),
                  _buildHistoryCard(driverResponse, notes),
                  const SizedBox(height: 12),
                  if (_canRespond)
                    _buildRespondCard()
                  else
                    _buildCompletedInfoCard(status, bargainingStatus, negotiatedFare, passengerOffer, finalFarePerSeat),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(
    String status,
    String bargainingStatus,
    int? negotiatedFare,
    int? passengerOffer,
    int totalSeats,
    int maleSeats,
    int femaleSeats,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Summary', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            _row('Booking Status', status),
            _row('Negotiation Status', bargainingStatus),
            _row('Seats', 'Total $totalSeats (M:$maleSeats F:$femaleSeats)'),
            if (negotiatedFare != null) _row('Driver Counter (per seat)', 'PKR $negotiatedFare'),
            if (passengerOffer != null) _row('Your Last Offer (per seat)', 'PKR $passengerOffer'),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(String driverResponse, String notes) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Negotiation History', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty && driverResponse.isEmpty && notes.isEmpty)
              const Text('No negotiation messages yet.', style: TextStyle(color: Colors.grey)),
            if (_history.isNotEmpty)
              ..._history.map((e) {
                final action = (e['action'] ?? '').toString();
                final ts = (e['ts'] ?? '').toString();
                final actor = (e['actor_type'] ?? '').toString();
                final price = (e['price_per_seat'] ?? e['counter_fare'])?.toString();
                final seats = e['seats'] ?? e['number_of_seats'];
                final note = (e['note'] ?? e['reason'] ?? '').toString();
                final summary = StringBuffer()
                  ..write(action.replaceAll('_', ' '));
                if (price != null) summary.write(' • PKR $price/seat');
                if (seats != null) summary.write(' • $seats seat(s)');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(summary.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (note.isNotEmpty)
                        Text(note, style: const TextStyle(fontSize: 12)),
                      if (ts.isNotEmpty)
                        Text(ts, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (actor.isNotEmpty)
                        Text(actor, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                );
              }),
            if (driverResponse.isNotEmpty) _row('Driver Response', driverResponse),
            if (notes.isNotEmpty) _row('Notes', notes),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedInfoCard(String status, String bargainingStatus, int? negotiatedFare, int? passengerOffer, int? finalFarePerSeat) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Negotiation Completed', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Status: $status ($bargainingStatus)'),
            if (finalFarePerSeat != null)
              Text('Final fare per seat: PKR $finalFarePerSeat'),
            if (finalFarePerSeat == null && negotiatedFare != null)
              Text('Final fare per seat: PKR $negotiatedFare'),
            if (finalFarePerSeat == null && negotiatedFare == null && passengerOffer != null)
              Text('Final fare per seat: PKR $passengerOffer'),
            const SizedBox(height: 4),
            const Text('You can no longer send counter offers for this booking.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildRespondCard() {
    final canAccept = _canAcceptNow();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.reply, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Respond', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _submitting
                        ? null
                        : (canAccept ? _onAccept : null),
                    icon: const Icon(Icons.check),
                    label: const Text('Accept Offer'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
            if (!canAccept) ...[
              const SizedBox(height: 6),
              const Text(
                'Waiting for driver counter offer…',
                style: TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _counterFareCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Counter Fare (per seat, PKR)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageCtrl,
              decoration: const InputDecoration(
                labelText: 'Message to driver (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _onSendCounter,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Send Counter'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _onWithdraw,
                    icon: const Icon(Icons.cancel),
                    label: const Text('Withdraw'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 170, child: Text(k, style: TextStyle(color: Colors.grey.shade600))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Future<void> _onSendCounter() async {
    setState(() { _submitting = true; _error = null; });
    try {
      final tripId = (widget.booking['trip_id'] ?? widget.booking['trip']?['trip_id'])?.toString();
      final bookingId = _resolveBookingPk(widget.booking);
      final passengerId = _parseInt(widget.booking['passenger_id'])
          ?? _parseInt(widget.booking['passenger']?['id'])
          ?? _parseInt(widget.userData['id']);
      if (tripId == null || bookingId == null || passengerId == null) {
        setState(() { _error = 'Missing trip/booking/passenger id'; _submitting = false; });
        return;
      }
      final cf = _parseCounterFareStrict();
      if (cf == null || cf <= 0) {
        setState(() { _error = 'Invalid format. Enter an integer fare (no decimals).'; _submitting = false; });
        return;
      }
      final res = await ApiService.passengerRespondBooking(
        tripId: tripId,
        bookingId: bookingId,
        action: 'counter',
        passengerId: passengerId,
        counterFare: cf,
        note: _messageCtrl.text.trim().isNotEmpty ? _messageCtrl.text.trim() : null,
      );
      if (res['success'] != true) {
        setState(() { _error = res['error']?.toString() ?? 'Failed to send counter'; _submitting = false; });
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Counter offer sent')));
      await _loadHistory();
      setState(() { _submitting = false; });
    } catch (e) {
      setState(() { _error = 'Error: $e'; _submitting = false; });
    }
  }

  Future<void> _onWithdraw() async {
    setState(() { _submitting = true; _error = null; });
    try {
      final tripId = (widget.booking['trip_id'] ?? widget.booking['trip']?['trip_id'])?.toString();
      final bookingId = _resolveBookingPk(widget.booking);
      final passengerId = _parseInt(widget.booking['passenger_id'])
          ?? _parseInt(widget.booking['passenger']?['id'])
          ?? _parseInt(widget.userData['id']);
      if (tripId == null || bookingId == null || passengerId == null) {
        setState(() { _error = 'Missing trip/booking/passenger id'; _submitting = false; });
        return;
      }
      final res = await ApiService.passengerRespondBooking(
        tripId: tripId,
        bookingId: bookingId,
        action: 'withdraw',
        passengerId: passengerId,
        note: _messageCtrl.text.trim().isNotEmpty ? _messageCtrl.text.trim() : null,
      );
      if (res['success'] != true) {
        setState(() { _error = res['error']?.toString() ?? 'Failed to withdraw'; _submitting = false; });
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request withdrawn')));
      await _loadHistory();
      setState(() { _submitting = false; });
    } catch (e) {
      setState(() { _error = 'Error: $e'; _submitting = false; });
    }
  }

  Future<void> _onAccept() async {
    setState(() { _submitting = true; _error = null; });
    try {
      final tripId = (widget.booking['trip_id'] ?? widget.booking['trip']?['trip_id'])?.toString();
      final bookingId = _resolveBookingPk(widget.booking);
      final passengerId = _parseInt(widget.booking['passenger_id'])
          ?? _parseInt(widget.booking['passenger']?['id'])
          ?? _parseInt(widget.userData['id']);
      if (tripId == null || bookingId == null || passengerId == null) {
        setState(() { _error = 'Missing trip/booking/passenger id'; _submitting = false; });
        return;
      }
      final res = await ApiService.passengerRespondBooking(
        tripId: tripId,
        bookingId: bookingId,
        action: 'accept',
        passengerId: passengerId,
        note: _messageCtrl.text.trim().isNotEmpty ? _messageCtrl.text.trim() : null,
      );
      if (res['success'] != true) {
        setState(() { _error = res['error']?.toString() ?? 'Failed to accept offer'; _submitting = false; });
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer accepted')));
      await _loadHistory();
      setState(() { _submitting = false; });
    } catch (e) {
      setState(() { _error = 'Error: $e'; _submitting = false; });
    }
  }
}
