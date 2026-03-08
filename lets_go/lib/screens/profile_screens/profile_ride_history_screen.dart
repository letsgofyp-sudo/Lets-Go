import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../utils/recreate_trip_mapper.dart';
import '../ride_posting_screens/create_ride_details_screen.dart';
import 'booked_ride_history_detail_screen.dart';
import 'created_ride_history_detail_screen.dart';

class ProfileRideHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Future<Map<String, dynamic>> Function(String tripId)? getRideBookingDetails;

  const ProfileRideHistoryScreen({
    super.key,
    required this.userData,
    this.getRideBookingDetails,
  });

  @override
  State<ProfileRideHistoryScreen> createState() => _ProfileRideHistoryScreenState();
}

class _ProfileRideHistoryScreenState extends State<ProfileRideHistoryScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const int _pageSize = 10;

  late TabController _tabController;

  List<Map<String, dynamic>> createdRides = [];
  List<Map<String, dynamic>> bookedRides = [];

  bool isLoading = true;
  bool isLoadingMoreCreated = false;
  bool isLoadingMoreBooked = false;
  bool hasMoreCreated = true;
  bool hasMoreBooked = true;
  int createdOffset = 0;
  int bookedOffset = 0;
  String? errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    () async {
      try {
        final userId = _extractUserId();
        if (userId > 0) {
          await ApiService.triggerAutoArchiveForDriver(userId: userId, limit: 10);
        }
      } catch (_) {
        // ignore
      }
    }();
    _loadRideHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _extractTripIdFromRideOrBooking(Map<String, dynamic> ride) {
    final direct = (ride['trip_id'] ?? ride['trip']?['trip_id'])?.toString();
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final nestedTrip = ride['trip'];
    if (nestedTrip is Map) {
      final tid = (nestedTrip['trip_id'] ?? nestedTrip['id'])?.toString();
      if (tid != null && tid.trim().isNotEmpty) return tid.trim();
    }
    return '';
  }

  Future<bool> _askRecreateUseActualPath() async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.route, color: Colors.teal),
                title: const Text('Use planned route'),
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              ListTile(
                leading: const Icon(Icons.alt_route, color: Colors.blue),
                title: const Text('Use actual traveled path'),
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        );
      },
    );
    return res == true;
  }

  Future<void> _recreateTripFromRide(Map<String, dynamic> ride, {bool useActualPath = false}) async {
    final tripId = _extractTripIdFromRideOrBooking(ride);
    if (tripId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip id missing; cannot recreate this ride')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // IMPORTANT: recreation must be trip-based (not booking-based). Use the
      // ride-booking detail endpoint because it returns the authoritative
      // planned route geometry (route_points/route_points) and the trip's own
      // actual_path.
      final fetch = widget.getRideBookingDetails ?? ApiService.getRideBookingDetails;
      Map<String, dynamic> detail;
      try {
        detail = await fetch(tripId);
      } catch (_) {
        // Some historical rides may not be available via ride-booking endpoint
        // but can still be reconstructed via trip details (includes snapshot fallback).
        detail = await ApiService.getTripDetailsById(tripId);
      }
      if (!mounted) return;
      Navigator.of(context).pop();

      final trip = RecreateTripMapper.normalizeRideBookingDetail(detail);
      if (trip.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load trip details')),
        );
        return;
      }

      final routeData = RecreateTripMapper.buildRouteDataFromNormalizedTrip(
        trip,
        preferActualPath: (useActualPath == true),
      );
      if (routeData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip route data missing')),
        );
        return;
      }

      final vehicle = (trip['vehicle'] is Map)
          ? Map<String, dynamic>.from(trip['vehicle'] as Map)
          : <String, dynamic>{};

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RideDetailsScreen(
            userData: widget.userData,
            routeData: routeData,
            recreateMode: true,
            initialTripDate: (trip['trip_date'] ?? '').toString(),
            initialDepartureTime: (trip['departure_time'] ?? '').toString(),
            initialVehicleId: (vehicle['id'] ?? '').toString(),
            initialTotalSeats: int.tryParse((trip['total_seats'] ?? '').toString()),
            initialGenderPreference: (trip['gender_preference'] ?? '').toString(),
            // Do not auto-fill notes from previous ride because route edits can
            // make it misleading; default to empty and let user add notes.
            initialNotes: '',
            initialIsNegotiable: (trip['is_negotiable'] == true),
            initialBaseFare: int.tryParse((trip['base_fare'] ?? '').toString()),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to recreate trip: $e')),
      );
    }
  }

  Future<void> _loadRideHistory() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
        createdRides = [];
        bookedRides = [];
        createdOffset = 0;
        bookedOffset = 0;
        hasMoreCreated = true;
        hasMoreBooked = true;
      });

      () async {
        try {
          final userId = _extractUserId();
          if (userId > 0) {
            await ApiService.triggerAutoArchiveForDriver(userId: userId, limit: 10);
          }
        } catch (_) {
          // ignore
        }
      }();

      await Future.wait([
        _loadMoreCreated(initial: true),
        _loadMoreBooked(initial: true),
      ]);

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load ride history: $e';
        isLoading = false;
      });
    }
  }

  int _extractUserId() {
    final raw = widget.userData['id'] ?? widget.userData['user_id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> _loadMoreCreated({bool initial = false}) async {
    if (!hasMoreCreated) return;
    if (!initial && isLoadingMoreCreated) return;

    final userId = _extractUserId();
    if (userId <= 0) {
      setState(() {
        errorMessage = 'User ID not found';
      });
      return;
    }

    setState(() {
      isLoadingMoreCreated = true;
    });

    try {
      final res = await ApiService.getUserCreatedRidesHistory(
        userId: userId,
        limit: _pageSize,
        offset: createdOffset,
      );

      if (res['success'] == true) {
        final list = (res['rides'] is List) ? List.from(res['rides'] as List) : <dynamic>[];
        final mapped = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        setState(() {
          createdRides = [...createdRides, ...mapped];
          createdOffset += mapped.length;
          hasMoreCreated = mapped.length >= _pageSize;
        });
      } else {
        setState(() {
          errorMessage = (res['error'] ?? 'Failed to load created rides history').toString();
          hasMoreCreated = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load created rides history: $e';
        hasMoreCreated = false;
      });
    } finally {
      setState(() {
        isLoadingMoreCreated = false;
      });
    }
  }

  Future<void> _loadMoreBooked({bool initial = false}) async {
    if (!hasMoreBooked) return;
    if (!initial && isLoadingMoreBooked) return;

    final userId = _extractUserId();
    if (userId <= 0) {
      setState(() {
        errorMessage = 'User ID not found';
      });
      return;
    }

    setState(() {
      isLoadingMoreBooked = true;
    });

    try {
      final res = await ApiService.getUserBookedRidesHistory(
        userId: userId,
        limit: _pageSize,
        offset: bookedOffset,
      );

      if (res['success'] == true) {
        final list = (res['bookings'] is List)
            ? List.from(res['bookings'] as List)
            : <dynamic>[];
        final mapped = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        setState(() {
          bookedRides = [...bookedRides, ...mapped];
          bookedOffset += mapped.length;
          hasMoreBooked = mapped.length >= _pageSize;
        });
      } else {
        setState(() {
          errorMessage = (res['error'] ?? 'Failed to load booked rides history').toString();
          hasMoreBooked = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load booked rides history: $e';
        hasMoreBooked = false;
      });
    } finally {
      setState(() {
        isLoadingMoreBooked = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Container(
          color: const Color(0xFF00897B),
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.directions_car), text: 'Created Rides'),
              Tab(icon: Icon(Icons.event_seat), text: 'My Bookings'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCreatedTab(),
              _buildBookedTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCreatedTab() {
    return RefreshIndicator(
      onRefresh: _loadRideHistory,
      child: isLoading
          ? ListView(children: const [SizedBox(height: 240), Center(child: CircularProgressIndicator())])
          : createdRides.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 48),
                    Center(
                      child: Text(
                        errorMessage ?? 'No created rides in history yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    for (final r in createdRides) _buildCreatedRideCard(r),
                    if (hasMoreCreated)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        child: OutlinedButton(
                          onPressed: isLoadingMoreCreated ? null : () => _loadMoreCreated(),
                          child: isLoadingMoreCreated
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Load more'),
                        ),
                      )
                    else
                      const SizedBox(height: 16),
                  ],
                ),
    );
  }

  Widget _buildBookedTab() {
    return RefreshIndicator(
      onRefresh: _loadRideHistory,
      child: isLoading
          ? ListView(children: const [SizedBox(height: 240), Center(child: CircularProgressIndicator())])
          : bookedRides.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 48),
                    Center(
                      child: Text(
                        errorMessage ?? 'No booked rides in history yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    for (final b in bookedRides) _buildBookedRideCard(b),
                    if (hasMoreBooked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        child: OutlinedButton(
                          onPressed: isLoadingMoreBooked ? null : () => _loadMoreBooked(),
                          child: isLoadingMoreBooked
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Load more'),
                        ),
                      ),
                  ],
                ),
    );
  }

  String _formatDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return 'Date N/A';
    try {
      return DateFormat('MMM dd, yyyy').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildIconInfoRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _routeTitleFromRide(Map<String, dynamic> ride) {
    try {
      final rn = (ride['route_names'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (rn.isNotEmpty) {
        return '${rn.first} → ${rn.last}';
      }
    } catch (_) {}
    final from = (ride['from_location'] ?? 'Unknown').toString();
    final to = (ride['to_location'] ?? 'Unknown').toString();
    return '$from → $to';
  }

  Widget _buildCreatedRideCard(Map<String, dynamic> ride) {
    final title = _routeTitleFromRide(ride);
    final date = _formatDate(ride['trip_date'] ?? ride['date']);
    final time = (ride['departure_time'] ?? '').toString();
    final status = (ride['status'] ?? '').toString();
    final hasActualPath = ride['has_actual_path'] == true;
    final isCompleted = status.toLowerCase() == 'completed';

    final dist = ride['distance'];
    final distanceText = (dist is num)
        ? '${dist.toStringAsFixed(1)} km'
        : (num.tryParse(dist?.toString() ?? '') != null)
            ? '${num.parse(dist.toString()).toStringAsFixed(1)} km'
            : 'N/A km';

    final seats = (ride['total_seats'] ?? '').toString();
    final seatsText = seats.trim().isEmpty ? 'Seats N/A' : '$seats seats';

    final priceRaw = ride['custom_price'] ?? ride['base_fare'];
    final price = int.tryParse(priceRaw?.toString() ?? '');
    final priceText = price == null ? 'Fare N/A' : 'Rs. $price';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          final tripId = (ride['trip_id'] ?? ride['id'] ?? '').toString();
          if (tripId.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trip id missing; cannot open details')),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreatedRideHistoryDetailScreen(
                userData: widget.userData,
                tripId: tripId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIconInfoRow(Icons.calendar_today, date),
                      _buildIconInfoRow(Icons.access_time, time.isEmpty ? 'N/A' : time),
                      _buildIconInfoRow(Icons.straighten, distanceText),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIconInfoRow(Icons.airline_seat_recline_normal, seatsText),
                      _buildIconInfoRow(Icons.payments_outlined, priceText),
                      _buildIconInfoRow(
                        Icons.people_alt_outlined,
                        'Bookings: ${(ride['booking_count'] ?? 0).toString()}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (isCompleted && hasActualPath) {
                        _askRecreateUseActualPath().then((useActual) {
                          if (!mounted) return;
                          _recreateTripFromRide(ride, useActualPath: useActual);
                        });
                        return;
                      }
                      _recreateTripFromRide(ride);
                    },
                    child: Text(
                      (isCompleted && hasActualPath) ? 'Recreate Ride (Choose Path)' : 'Recreate Ride',
                    ),
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookedRideCard(Map<String, dynamic> ride) {
    final title = _routeTitleFromRide(ride);
    final date = _formatDate(ride['trip_date'] ?? ride['date']);
    final time = (ride['departure_time'] ?? '').toString();
    final status = (ride['booking_status'] ?? ride['status'] ?? '').toString();
    final fare = (ride['total_fare'] ?? 0).toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          final tripId = (ride['trip_id'] ?? '').toString();
          if (tripId.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trip id missing; cannot open details')),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookedRideHistoryDetailScreen(userData: widget.userData, booking: ride),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIconInfoRow(Icons.calendar_today, date),
                        _buildIconInfoRow(Icons.access_time, time.isEmpty ? 'N/A' : time),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildIconInfoRow(Icons.payments_outlined, 'Rs. $fare'),
                        _buildIconInfoRow(
                          Icons.airline_seat_recline_normal,
                          'Seats: ${(ride['number_of_seats'] ?? 'N/A').toString()}',
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
    );
  }
}