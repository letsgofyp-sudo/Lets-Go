import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'request_response_screen.dart';

class DriverRequestsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String tripId;

  const DriverRequestsScreen({
    super.key,
    required this.userData,
    required this.tripId,
  });

  @override
  State<DriverRequestsScreen> createState() => _DriverRequestsScreenState();
}

class _DriverRequestsScreenState extends State<DriverRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    if (!mounted) return;
    final sw = Stopwatch()..start();
    debugPrint('[DriverRequests] fetch start tripId=${widget.tripId}');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t0 = DateTime.now();
      debugPrint('[DriverRequests] calling ApiService.listPendingRequests at $t0');
      final items = await ApiService.listPendingRequests(tripId: widget.tripId);
      final t1 = DateTime.now();
      debugPrint('[DriverRequests] listPendingRequests returned ${items.length} items in ${t1.difference(t0).inMilliseconds}ms');
      if (!mounted) return;
      setState(() {
        _requests = items;
        _loading = false;
      });
      debugPrint('[DriverRequests] UI state set with ${items.length} items; total elapsed ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load requests: $e';
        _loading = false;
      });
      debugPrint('[DriverRequests] error: $e; total elapsed ${sw.elapsedMilliseconds}ms');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Ride Requests',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRequests,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _requests.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        final req = _requests[index];
                        final passengerName = (req['passenger_name'] ?? 'Passenger').toString();
                        final seats = int.tryParse((req['number_of_seats'] ?? 1).toString()) ?? 1;
                        final fromName = (req['from_stop_name'] ?? 'Origin').toString();
                        final toName = (req['to_stop_name'] ?? 'Destination').toString();
                        final offerPerSeat = req['passenger_offer_per_seat'] as num?;
                        final gender = (req['passenger_gender'] ?? '').toString();
                        final status = (req['bargaining_status'] ?? req['booking_status'] ?? 'PENDING').toString();

                        int maleSeats = int.tryParse((req['male_seats'] ?? 0).toString()) ?? 0;
                        int femaleSeats = int.tryParse((req['female_seats'] ?? 0).toString()) ?? 0;
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

                        final rawPhoto = req['passenger_photo_url'];
                        final photoUrl = rawPhoto?.toString();

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                    (photoUrl != null && photoUrl.startsWith('http'))
                                        ? NetworkImage(photoUrl)
                                        : null,
                                child: (photoUrl == null || !photoUrl.startsWith('http'))
                                    ? Text(
                                        passengerName.isNotEmpty
                                            ? passengerName[0].toUpperCase()
                                            : 'P',
                                      )
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      passengerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (gender.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      gender.toLowerCase() == 'female' ? Icons.female : Icons.male,
                                      size: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$fromName → $toName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Seats: $seats (M:$maleSeats F:$femaleSeats)'
                                    '${offerPerSeat != null ? ' • Offer/seat: ₨${offerPerSeat.round()}' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w600),
                                ),
                              ),
                              onTap: () async {
                                if (!mounted) return;
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RequestResponseScreen(
                                      userData: widget.userData,
                                      tripId: widget.tripId,
                                      request: req,
                                    ),
                                  ),
                                );
                                if (result == true) {
                                  _fetchRequests();
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Passenger requests will appear here.\nTap refresh to update.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
