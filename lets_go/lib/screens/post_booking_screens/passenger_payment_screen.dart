import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import '../../utils/auth_session.dart';

class PassengerPaymentScreen extends StatefulWidget {
  final String tripId;
  final int passengerId;
  final int bookingId;

  const PassengerPaymentScreen({
    super.key,
    required this.tripId,
    required this.passengerId,
    required this.bookingId,
  });

  @override
  State<PassengerPaymentScreen> createState() => _PassengerPaymentScreenState();
}

class _PassengerPaymentScreenState extends State<PassengerPaymentScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  Map<String, dynamic>? _data;

  File? _receiptFile;
  bool _paidByCash = false;
  int _driverRating = 5;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _shareQr(String url) async {
    if (url.trim().isEmpty) return;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download QR image')),
        );
        return;
      }
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/lets_go_payment_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(res.bodyBytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Payment QR code',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to download QR image')),
      );
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiService.getBookingPaymentDetails(
        bookingId: widget.bookingId,
        role: 'PASSENGER',
        userId: widget.passengerId,
      );
      if (res['success'] == true) {
        setState(() {
          _data = Map<String, dynamic>.from(res);
        });
      } else {
        setState(() {
          _error = (res['error'] ?? 'Failed to load payment details').toString();
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

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    setState(() {
      _receiptFile = File(x.path);
      _paidByCash = false;
    });
  }

  Future<void> _submit() async {
    if (!_paidByCash && _receiptFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please attach payment receipt or select Paid by Cash')),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final res = await ApiService.submitBookingPayment(
        bookingId: widget.bookingId,
        passengerId: widget.passengerId,
        driverRating: _driverRating.toDouble(),
        driverFeedback: _commentController.text.trim(),
        receiptFile: _paidByCash ? null : _receiptFile,
        paidByCash: _paidByCash,
      );

      if (res['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _paidByCash
                  ? 'Marked as cash payment. Waiting for driver confirmation.'
                  : 'Receipt sent. Waiting for driver confirmation.',
            ),
          ),
        );

        // Refresh current user's profile so ratings update everywhere.
        try {
          final fresh = await ApiService.getUserProfile(widget.passengerId);
          await AuthSession.save(fresh);
        } catch (_) {
          // ignore
        }
        await _load();
      } else {
        setState(() {
          _error = (res['error'] ?? 'Submit failed').toString();
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
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

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final booking = (data?['booking'] is Map)
        ? Map<String, dynamic>.from(data!['booking'] as Map)
        : <String, dynamic>{};
    final driverBank = (data?['driver_bank'] is Map)
        ? Map<String, dynamic>.from(data!['driver_bank'] as Map)
        : <String, dynamic>{};
    final payment = (data?['payment'] is Map)
        ? Map<String, dynamic>.from(data!['payment'] as Map)
        : null;

    final bankName = (driverBank['bankname'] ?? '').toString();
    final accountNo = (driverBank['accountno'] ?? '').toString();
    final iban = (driverBank['iban'] ?? '').toString();
    final qrUrl = (driverBank['accountqr_url'] ?? '').toString();

    final paymentStatus = (booking['payment_status'] ?? '').toString().toUpperCase();
    final alreadyRated = booking['driver_rating'] != null;
    final receiptUrl = payment?['receipt_url']?.toString();
    final paymentMethod = (payment?['payment_method'] ?? '').toString().toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Payment',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: ${paymentStatus.isEmpty ? 'PENDING' : paymentStatus}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (paymentMethod.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Method: $paymentMethod'),
                          ),
                        const SizedBox(height: 8),
                        if (receiptUrl != null && receiptUrl.isNotEmpty)
                          Row(
                            children: [
                              const Expanded(child: Text('Receipt already uploaded')),
                              TextButton(
                                onPressed: () => _openImage(receiptUrl),
                                child: const Text('View'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Driver Bank Details', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: qrUrl.isNotEmpty
                                  ? InkWell(
                                      onTap: () => _openImage(qrUrl),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          qrUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.qr_code, color: Colors.grey),
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.qr_code, color: Colors.grey),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('Bank: ${bankName.isEmpty ? 'Not provided' : bankName}'),
                                      ),
                                      if (bankName.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 18),
                                          onPressed: () => _copy(bankName, 'Bank name'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('Account: ${accountNo.isEmpty ? 'Not provided' : accountNo}'),
                                      ),
                                      if (accountNo.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 18),
                                          onPressed: () => _copy(accountNo, 'Account number'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('IBAN: ${iban.isEmpty ? 'Not provided' : iban}'),
                                      ),
                                      if (iban.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 18),
                                          onPressed: () => _copy(iban, 'IBAN'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: qrUrl.isEmpty ? null : () => _shareQr(qrUrl),
                                          icon: const Icon(Icons.download),
                                          label: const Text('Download QR'),
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
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payment Proof', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: _paidByCash,
                          onChanged: _submitting
                              ? null
                              : (v) {
                                  setState(() {
                                    _paidByCash = v == true;
                                    if (_paidByCash) {
                                      _receiptFile = null;
                                    }
                                  });
                                },
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Paid by Cash'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 10),
                        if (!_paidByCash) ...[
                          if (_receiptFile != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _receiptFile!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) {
                                  return const SizedBox(
                                    height: 180,
                                    child: Center(child: Text('Selected file preview not available')),
                                  );
                                },
                              ),
                            )
                          else
                            Container(
                              height: 180,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('No receipt selected'),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _submitting ? null : _pickReceipt,
                                  icon: const Icon(Icons.attach_file),
                                  label: Text(_receiptFile == null ? 'Attach Receipt' : 'Change Receipt'),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Container(
                            height: 80,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(20),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Cash payment selected'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rate Driver', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        const Text('Rate driver'),
                        _ratingRow(
                          value: _driverRating,
                          enabled: !alreadyRated && !_submitting,
                          onChanged: (v) => setState(() => _driverRating = v),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _commentController,
                          enabled: !alreadyRated && !_submitting,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Comment (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: alreadyRated || _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Submit'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
    );
  }
}
