import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

class DriverPaymentConfirmationScreen extends StatefulWidget {
  final String tripId;
  final int driverId;

  const DriverPaymentConfirmationScreen({
    super.key,
    required this.tripId,
    required this.driverId,
  });

  @override
  State<DriverPaymentConfirmationScreen> createState() => _DriverPaymentConfirmationScreenState();
}

class _DriverPaymentConfirmationScreenState extends State<DriverPaymentConfirmationScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiService.getTripPayments(
        tripId: widget.tripId,
        driverId: widget.driverId,
      );

      if (res['success'] == true) {
        final list = (res['payments'] is List) ? List.from(res['payments'] as List) : <dynamic>[];
        setState(() {
          _payments = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      } else {
        setState(() {
          _error = (res['error'] ?? 'Failed to load payments').toString();
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openImage(String url) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: Text('Failed to load image')),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _ratingRow({
    required int value,
    required ValueChanged<int> onChanged,
    bool enabled = true,
  }) {
    return Row(
      children: [
        for (int i = 1; i <= 5; i++)
          IconButton(
            onPressed: !enabled
                ? null
                : () {
                    onChanged(i);
                  },
            icon: Icon(
              i <= value ? Icons.star : Icons.star_border,
              color: Colors.amber,
            ),
          ),
      ],
    );
  }

  Future<void> _confirmPayment(Map<String, dynamic> item) async {
    final bookingId = item['booking_id'];
    if (bookingId is! int) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid booking id')),
      );
      return;
    }

    int rating = 5;
    final commentController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirm Payment'),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rate passenger'),
                  _ratingRow(
                    value: rating,
                    onChanged: (v) => setLocal(() => rating = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comments (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (ok != true) {
      commentController.dispose();
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final res = await ApiService.confirmBookingPayment(
        bookingId: bookingId,
        driverId: widget.driverId,
        passengerRating: rating.toDouble(),
        passengerFeedback: commentController.text.trim(),
      );

      if (res['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed')),
        );

        // Refresh current user's profile so ratings update everywhere.
        try {
          final fresh = await ApiService.getUserProfile(widget.driverId);
          await AuthSession.save(fresh);
        } catch (_) {
          // ignore
        }
        await _load();
      } else {
        setState(() {
          _error = (res['error'] ?? 'Confirm failed').toString();
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      commentController.dispose();
      setState(() {
        _submitting = false;
      });
    }
  }

  Widget _paymentCard(Map<String, dynamic> item) {
    final passenger = (item['passenger'] is Map)
        ? Map<String, dynamic>.from(item['passenger'] as Map)
        : <String, dynamic>{};

    final passengerName = (passenger['name'] ?? 'Passenger').toString();
    final receiptUrl = item['receipt_url']?.toString();
    final paymentMethod = (item['payment_method'] ?? '').toString().toUpperCase();

    final paymentStatus = (item['payment_status'] ?? '').toString().toUpperCase();
    final bookingStatus = (item['booking_status'] ?? '').toString().toUpperCase();

    final canConfirm = paymentStatus != 'COMPLETED' && !_submitting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    passengerName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('Booking #${item['booking_id']}'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Booking: ${bookingStatus.isEmpty ? 'N/A' : bookingStatus}')),
                Chip(label: Text('Payment: ${paymentStatus.isEmpty ? 'PENDING' : paymentStatus}')),
                if (paymentMethod.isNotEmpty) Chip(label: Text('Method: $paymentMethod')),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (receiptUrl == null || receiptUrl.isEmpty)
                        ? null
                        : () => _openImage(receiptUrl),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('View Receipt'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canConfirm ? () => _confirmPayment(item) : null,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Confirm Paid'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: Text('No bookings found for this trip.')),
                  )
                else
                  for (final p in _payments) _paymentCard(p),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
    );
  }
}
