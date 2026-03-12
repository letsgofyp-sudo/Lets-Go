import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../controllers/ride_posting_controllers/my_rides_controller.dart';
import '../../services/api_service.dart';
import '../../services/live_tracking_session_manager.dart';
import 'booking_detail_screen.dart';
import '../ride_booking_screens/driver_requests_screen.dart';
import '../post_booking_screens/driver_live_tracking_screen.dart';
import '../post_booking_screens/driver_payment_confirmation_screen.dart';
import '../post_booking_screens/passenger_live_tracking_screen.dart';
import '../post_booking_screens/passenger_payment_screen.dart';
import '../ride_booking_screens/ride_booking_details_screen.dart';
import 'package:share_plus/share_plus.dart';

class MyRidesScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const MyRidesScreen({super.key, required this.userData});

  @override
  State<MyRidesScreen> createState() => _MyRidesScreenState();
}

class _MyRidesScreenState extends State<MyRidesScreen> with SingleTickerProviderStateMixin {
  late MyRidesController _controller;
  late TabController _tabController;
  
  // Separate lists for different ride types
  List<Map<String, dynamic>> createdRides = [];
  List<Map<String, dynamic>> requestedRides = [];

  Map<String, dynamic>? _persistedLiveTrackingSession;

  bool _canCreateRide = false;
  bool _isCheckingCreateRideEligibility = false;
  String? _createRideBlockMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Ensure FAB and other tab-dependent UI update when tab changes
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    _initializeController();
    _loadPersistedLiveTrackingSession();
    _refreshCreateRideEligibility();
  }

  bool _hasDrivingLicense(Map<String, dynamic> user) {
    final candidates = [
      user['driving_license_no'],
      user['driving_license_number'],
      user['license_no'],
      user['driving_license'],
    ];
    for (final v in candidates) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return true;
    }
    return false;
  }

  Future<void> _refreshCreateRideEligibility() async {
    if (_isCheckingCreateRideEligibility) return;
    final userId = _extractUserId();
    if (userId <= 0) {
      if (!mounted) return;
      setState(() {
        _canCreateRide = false;
        _createRideBlockMessage = 'Missing user id';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isCheckingCreateRideEligibility = true;
      _createRideBlockMessage = null;
    });

    try {
      final status = (widget.userData['status'] ?? '').toString().trim().toUpperCase();
      if (status != 'VERIFIED') {
        if (!mounted) return;
        setState(() {
          _canCreateRide = false;
          _createRideBlockMessage = 'Your profile is not verified yet.';
        });
        return;
      }

      if (!_hasDrivingLicense(widget.userData)) {
        if (!mounted) return;
        setState(() {
          _canCreateRide = false;
          _createRideBlockMessage = 'Driving license is required to create rides.';
        });
        return;
      }

      final vehicles = await ApiService.getUserVehicles(userId);
      final anyVerified = vehicles.any((v) {
        final s = (v['status'] ?? '').toString().trim().toUpperCase();
        return s == 'VERIFIED';
      });

      if (!mounted) return;
      setState(() {
        _canCreateRide = anyVerified;
        _createRideBlockMessage = anyVerified
            ? null
            : 'At least one verified vehicle is required to create rides.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canCreateRide = false;
        _createRideBlockMessage = 'Unable to check ride creation eligibility.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingCreateRideEligibility = false;
        });
      }
    }
  }

  int? _extractBookingNumericId(Map<String, dynamic> booking) {
    final rawNumericId = booking['id'] ?? booking['db_id'];
    final rawCodeId = booking['booking_id'];
    if (rawNumericId is int) return rawNumericId;
    if (rawNumericId is String) return int.tryParse(rawNumericId);
    if (rawCodeId is int) return rawCodeId;
    if (rawCodeId is String) return int.tryParse(rawCodeId);
    return null;
  }

  Future<void> _showShareSheetForRide(Map<String, dynamic> ride, {required bool isCreatedRide}) async {
    final userId = _extractUserId();
    final tripId = (ride['trip_id'] ?? ride['trip']?['trip_id'] ?? ride['id'] ?? '').toString();
    if (tripId.trim().isEmpty) return;

    final role = isCreatedRide ? 'driver' : 'passenger';
    final bookingId = isCreatedRide ? null : _extractBookingNumericId(ride);

    String shareUrl = '';
    try {
      final res = await ApiService.createTripShareUrl(
        tripId: tripId,
        role: role,
        bookingId: bookingId,
      );
      if (res['success'] == true) {
        shareUrl = (res['share_url'] ?? '').toString();
      }
    } catch (_) {}

    final urlToShare = shareUrl.trim();
    if (urlToShare.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to generate share link')),
      );
      return;
    }

    if (!mounted) return;
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
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Missing user id')),
                    );
                    return;
                  }
                  final ok = await ApiService.isTripAvailableForUser(
                    userId: userId,
                    tripId: tripId,
                  );
                  if (!mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Not available for you')),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RideBookingDetailsScreen(
                        userData: widget.userData,
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

  int _extractUserId() {
    return int.tryParse(widget.userData['id']?.toString() ?? '') ??
        int.tryParse(widget.userData['user_id']?.toString() ?? '') ??
        0;
  }


  Future<void> _loadPersistedLiveTrackingSession() async {
    try {
      final session = await LiveTrackingSessionManager.instance.readPersistedSession();
      if (!mounted) return;
      setState(() {
        _persistedLiveTrackingSession = session;
      });
    } catch (_) {
      // ignore
    }
  }

  bool _isPersistedPassengerLiveSessionForBooking(Map<String, dynamic> booking) {
    final session = _persistedLiveTrackingSession;
    if (session == null) return false;

    final tripId = (booking['trip_id'] ?? booking['trip']?['trip_id'])?.toString();
    if (tripId == null || tripId.isEmpty) return false;

    final rawNumericId = booking['id'] ?? booking['db_id'];
    final rawCodeId = booking['booking_id'];
    int? bookingId;
    if (rawNumericId is int) {
      bookingId = rawNumericId;
    } else if (rawNumericId is String) {
      bookingId = int.tryParse(rawNumericId);
    } else if (rawCodeId is int) {
      bookingId = rawCodeId;
    } else if (rawCodeId is String) {
      bookingId = int.tryParse(rawCodeId);
    }
    if (bookingId == null) return false;

    final userId = int.tryParse(widget.userData['id']?.toString() ?? '') ??
        int.tryParse(widget.userData['user_id']?.toString() ?? '') ??
        0;
    if (userId == 0) return false;

    return session['trip_id']?.toString() == tripId &&
        session['user_id'] == userId &&
        session['is_driver'] == false &&
        session['booking_id'] == bookingId;
  }

  num? _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  String _formatPkrNoDecimals(dynamic v) {
    final n = _asNum(v);
    if (n == null) return 'N/A';
    return n.round().toString();
  }

  num? _distanceKmForRide(Map<String, dynamic> ride) {
    // Direct distance field if present
    final direct = _asNum(ride['distance']);
    if (direct != null) return direct;

    // Trip-level total distance
    final trip = ride['trip'];
    if (trip is Map<String, dynamic>) {
      final tripDistance =
          _asNum(trip['total_distance_km'] ?? trip['distance_km'] ?? trip['distance']);
      if (tripDistance != null) return tripDistance;
    }

    // Fare data if embedded in trip or ride
    final fareData = (trip is Map<String, dynamic> && trip['fare_data'] is Map)
        ? Map<String, dynamic>.from(trip['fare_data'])
        : (ride['fare_data'] is Map
            ? Map<String, dynamic>.from(ride['fare_data'])
            : const <String, dynamic>{});
    final fareDistance = _asNum(fareData['total_distance_km']);
    if (fareDistance != null) return fareDistance;

    return null;
  }

  // Safely get origin name for a ride card/dialog
  String _originName(Map<String, dynamic> ride) {
    try {
      final rn = (ride['route_names'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (rn.isNotEmpty) return rn.first;
    } catch (_) {}
    final from = ride['from_location'] ?? ride['trip']?['from_location'];
    if (from is String && from.isNotEmpty && from.toLowerCase() != 'unknown') return from;
    // Fallback: parse description "A → ... → B" and take first
    final desc = ride['description']?.toString();
    if (desc != null && desc.trim().isNotEmpty) {
      final parts = desc.split(RegExp(r"\s*[→>-]+\s*"));
      if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
        return parts.first.trim();
      }
    }
    return 'Unknown';
  }

  // Safely get destination name for a ride card/dialog
  String _destinationName(Map<String, dynamic> ride) {
    try {
      final rn = (ride['route_names'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (rn.isNotEmpty) return rn.last;
    } catch (_) {}
    final to = ride['to_location'] ?? ride['trip']?['to_location'];
    if (to is String && to.isNotEmpty && to.toLowerCase() != 'unknown') return to;
    // Fallback: parse description and take last
    final desc = ride['description']?.toString();
    if (desc != null && desc.trim().isNotEmpty) {
      final parts = desc.split(RegExp(r"\s*[→>-]+\s*"));
      if (parts.isNotEmpty && parts.last.trim().isNotEmpty) {
        return parts.last.trim();
      }
    }
    return 'Unknown';
  }

  // Build a safe title for the ride row
  String _buildRouteTitle(Map<String, dynamic> ride) {
    final from = _originName(ride);
    final to = _destinationName(ride);
    return '$from → $to';
  }

  void _initializeController() {
    _controller = MyRidesController(
      onStateChanged: () {
        if (!mounted) return;
        setState(() {});
      },
      onError: (message) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
      onSuccess: (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.green),
          );
        }
      },
      onInfo: (message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.blue),
          );
        }
      },
    );

    // Load user's rides
    final userId = _extractUserId();
    if (userId > 0) {
      _controller.loadUserRides(userId);
    }
    
    // Add listener to update ride lists when data changes
    _controller.onStateChanged = () {
      if (!mounted) return;
      _separateRides();
      setState(() {});
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Separate rides into created and requested/booked
  void _separateRides() {
    debugPrint('DEBUG: _separateRides called');
    createdRides.clear();
    requestedRides.clear();
    
    debugPrint('DEBUG: _controller.userRides length: ${_controller.userRides.length}');
    debugPrint('DEBUG: _controller.userBookings length: ${_controller.userBookings.length}');
    
    // Add created rides (where user is the driver)
    createdRides.addAll(_controller.userRides);
    
    // Add booking requests (where user is the passenger)
    requestedRides.addAll(_controller.userBookings);
    
    debugPrint('DEBUG: After separation - createdRides: ${createdRides.length}, requestedRides: ${requestedRides.length}');
    
    if (_controller.userBookings.isNotEmpty) {
      debugPrint('DEBUG: First booking data structure: ${_controller.userBookings.first.keys.toList()}');
    }
  }

  bool _canStartDriverRide(Map<String, dynamic> ride) {
    final status = (ride['status'] ?? '').toString().toLowerCase();
    final bookingCount = (ride['booking_count'] ?? 0) as int;
    // Allow start only for upcoming/pending rides that have at least one confirmed booking
    if (bookingCount <= 0) return false;
    if (status == 'pending' || status == 'active' || status == 'scheduled') {
      return true;
    }
    return false;
  }

  bool _canResumeDriverRide(Map<String, dynamic> ride) {
    final status = (ride['status'] ?? '').toString().toLowerCase();
    return status == 'inprocess' || status == 'in_process' || status == 'in progress' || status == 'in_progress';
  }

  bool _canOpenDriverPayments(Map<String, dynamic> ride) {
    final status = (ride['status'] ?? '').toString().toLowerCase();
    final bookingCount = (ride['booking_count'] ?? 0) as int;
    return status == 'completed' && bookingCount > 0;
  }

  bool _canStartPassengerRide(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (booking['payment_status'] ?? '').toString().toLowerCase();
    // Treat "booked" / "confirmed" as ready-to-start passenger bookings
    final can = status == 'booked' ||
        status == 'confirmed' ||
        (status == 'completed' && paymentStatus.isNotEmpty && paymentStatus != 'completed');
    if (can) {
      debugPrint('[MyRides] _canStartPassengerRide: true for booking status=$status id=${booking['id'] ?? booking['booking_id'] ?? booking['db_id']}');
    } else {
      debugPrint('[MyRides] _canStartPassengerRide: false for status=$status');
    }
    return can;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'pending':
        return Colors.green;
      case 'inprocess':
      case 'in_process':
        return Colors.orange;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
      case 'canceled':
        return Colors.red;
      case 'rejected':
        return Colors.red.shade700;
      case 'expired':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplayText(String status) {
    switch (status.toLowerCase()) {
      case 'inprocess':
      case 'in_process':
        return 'IN PROCESS';
      case 'cancelled':
      case 'canceled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  // Navigate to ride view/edit screen
  void _navigateToRideView(Map<String, dynamic> ride, bool isEditMode) {
    () async {
      final tripId = (ride['trip_id'] ?? ride['id'] ?? '').toString();
      if (tripId.isEmpty) {
        Navigator.pushNamed(
          context,
          '/ride-view-edit',
          arguments: {
            'ride': ride,
            'isEditMode': isEditMode,
            'userData': widget.userData,
          },
        );
        return;
      }

      // Show a lightweight loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      Map<String, dynamic> merged = Map<String, dynamic>.from(ride);
      try {
        // Fetch heavy fields (stop_breakdown, fare_calculation) only when needed
        final detail = await ApiService.getRideBookingDetails(tripId);

        // Preserve polylines if provided at the top-level of the payload.
        if (detail['route_points'] != null) {
          merged['route_points'] = detail['route_points'];
        }
        if (detail['actual_path'] != null) {
          merged['actual_path'] = detail['actual_path'];
        }
        // Merge core trip fields
        if (detail['trip'] is Map<String, dynamic>) {
          final t = Map<String, dynamic>.from(detail['trip']);
          final existingTrip = (merged['trip'] is Map<String, dynamic>)
              ? Map<String, dynamic>.from(merged['trip'] as Map)
              : <String, dynamic>{};
          merged['trip'] = {
            ...existingTrip,
            ...t,
          };

          // Also preserve polylines if they are on the trip object.
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

          // Prefer nested trip sub-objects when present
          if (t['route'] is Map<String, dynamic>) {
            merged['route'] = {
              ...(merged['route'] is Map<String, dynamic> ? Map<String, dynamic>.from(merged['route'] as Map) : <String, dynamic>{}),
              ...Map<String, dynamic>.from(t['route']),
            };
          }
          if (t['vehicle'] is Map<String, dynamic>) {
            merged['vehicle'] = {
              ...(merged['vehicle'] is Map<String, dynamic> ? Map<String, dynamic>.from(merged['vehicle'] as Map) : <String, dynamic>{}),
              ...Map<String, dynamic>.from(t['vehicle']),
            };
          }
          if (t['driver'] is Map<String, dynamic>) {
            merged['driver'] = {
              ...(merged['driver'] is Map<String, dynamic> ? Map<String, dynamic>.from(merged['driver'] as Map) : <String, dynamic>{}),
              ...Map<String, dynamic>.from(t['driver']),
            };
          }

          merged['gender_preference'] = merged['gender_preference'] ?? t['gender_preference'];
          merged['is_negotiable'] = merged['is_negotiable'] ?? t['is_negotiable'];
        }

        // Merge top-level driver / vehicle if provided separately
        if (detail['driver'] is Map<String, dynamic>) {
          merged['driver'] = {
            ...(merged['driver'] is Map<String, dynamic> ? Map<String, dynamic>.from(merged['driver'] as Map) : <String, dynamic>{}),
            ...Map<String, dynamic>.from(detail['driver']),
          };
        }
        if (detail['vehicle'] is Map<String, dynamic>) {
          merged['vehicle'] = {
            ...(merged['vehicle'] is Map<String, dynamic> ? Map<String, dynamic>.from(merged['vehicle'] as Map) : <String, dynamic>{}),
            ...Map<String, dynamic>.from(detail['vehicle']),
          };
        }

        // Merge route (for map and readable origin/destination)
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
        if (detail['fare_data'] != null) {
          merged['fare_data'] = detail['fare_data'];
        }
        if (detail['booking_info'] != null) {
          merged['booking_info'] = detail['booking_info'];
        }
      } catch (e) {
        // Optionally log e
      } finally {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/ride-view-edit',
        arguments: {
          'ride': merged,
          'isEditMode': isEditMode,
          'userData': widget.userData,
        },
      );
    }();
  }

  // Show delete confirmation dialog
  void _showDeleteConfirmation(Map<String, dynamic> ride) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Ride'),
        content: Text(
          'Are you sure you want to delete this ride from ${_originName(ride)} to ${_destinationName(ride)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.deleteRide(ride['trip_id']);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Build ride card
  Widget _buildRideCard(Map<String, dynamic> ride, bool isCreatedRide) {
    final status = ride['status'] ?? 'active';
    final canEdit = ride['can_edit'] ?? false;
    final canCancel = ride['can_cancel'] ?? false;

    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final bool hasPersistedPassengerSession =
        !isCreatedRide && _isPersistedPassengerLiveSessionForBooking(ride);
    
    // For created rides, allow delete only if no bookings exist
    final canDelete = isCreatedRide && 
                     (ride['can_delete'] ?? false) && 
                     (ride['booking_count'] ?? 0) == 0 &&
                     status.toLowerCase() != 'completed' &&
                     status.toLowerCase() != 'cancelled';

    final canEditEffective = isCreatedRide ? (canEdit && canDelete) : canEdit;
    final canCancelEffective = isCreatedRide ? (canCancel && !canDelete) : canCancel;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status
            Row(
              children: [
                Expanded(
                  child: Text(
                    _buildRouteTitle(ride),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Share',
                  onPressed: () => _showShareSheetForRide(ride, isCreatedRide: isCreatedRide),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusDisplayText(status),
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
            // Ride details
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        Icons.calendar_today,
                        ride['trip_date'] != null 
                          ? DateFormat('MMM dd, yyyy').format(DateTime.parse(ride['trip_date']))
                          : ride['trip']?['trip_date'] != null
                            ? DateFormat('MMM dd, yyyy').format(DateTime.parse(ride['trip']['trip_date']))
                            : 'Date N/A',
                      ),
                      _buildInfoRow(
                        Icons.access_time,
                        ride['departure_time'] ?? ride['trip']?['departure_time'] ?? 'N/A',
                      ),
                      _buildInfoRow(
                        Icons.straighten,
                        _distanceKmForRide(ride) != null
                            ? '${_distanceKmForRide(ride)!.toStringAsFixed(1)} km'
                            : 'N/A km',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        Icons.airline_seat_recline_normal,
                        () {
                          if (isCreatedRide) {
                            final total = ride['total_seats'] ?? ride['trip']?['total_seats'] ?? 'N/A';
                            return '$total seats';
                          }
                          final total = asInt(
                            ride['number_of_seats'] ??
                                ride['seats_booked'] ??
                                ride['seats'] ??
                                ride['total_seats'],
                          );
                          final male = asInt(ride['male_seats']);
                          final female = asInt(ride['female_seats']);
                          if ((male + female) > 0) {
                            return '$total seats (M:$male F:$female)';
                          }
                          if (total > 0) {
                            return '$total seats';
                          }
                          final fallback = ride['number_of_seats'] ?? ride['seats_booked'] ?? ride['seats'] ?? 'N/A';
                          return '$fallback seats';
                        }(),
                      ),
                      _buildInfoRow(
                        Icons.attach_money,
                        '₨${_formatPkrNoDecimals(ride['custom_price'] ?? ride['total_fare'])}',
                      ),
                      _buildInfoRow(
                        Icons.person,
                        ride['gender_preference'] ?? ride['trip']?['gender_preference'] ?? 'Any',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ride['description']?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                ride['description'] ?? '',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Action buttons based on ride type
            if (isCreatedRide) ...[
              // Buttons for created rides (driver view)
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                  if (_canStartDriverRide(ride) || _canResumeDriverRide(ride) || _canOpenDriverPayments(ride))
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          final tripId = (ride['trip_id'] ?? ride['id']).toString();
                          final userId = int.tryParse(widget.userData['id']?.toString() ?? '') ?? 0;
                          if (tripId.isEmpty || userId == 0) return;

                          if (_canOpenDriverPayments(ride)) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DriverPaymentConfirmationScreen(
                                  tripId: tripId,
                                  driverId: userId,
                                ),
                              ),
                            );
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DriverLiveTrackingScreen(
                                tripId: tripId,
                                driverId: userId,
                              ),
                            ),
                          ).then((_) => _loadPersistedLiveTrackingSession());
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          minimumSize: const Size(44, 40),
                        ),
                        child: Tooltip(
                          message: _canOpenDriverPayments(ride)
                              ? 'Payments'
                              : (_canResumeDriverRide(ride) ? 'Resume Ride' : 'Start Ride'),
                          child: Icon(
                            _canOpenDriverPayments(ride)
                                ? Icons.payments_outlined
                                : (_canResumeDriverRide(ride)
                                    ? Icons.play_circle_outline
                                    : Icons.directions_bus),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  if (_canStartDriverRide(ride) || _canResumeDriverRide(ride) || _canOpenDriverPayments(ride)) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final tripId = (ride['trip_id'] ?? ride['id']).toString();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DriverRequestsScreen(
                              userData: widget.userData,
                              tripId: tripId,
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal,
                        minimumSize: const Size(44, 40),
                      ),
                      child: const Tooltip(
                        message: 'Requests',
                        child: Icon(Icons.handshake, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _navigateToRideView(ride, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        minimumSize: const Size(44, 40),
                      ),
                      child: const Tooltip(
                        message: 'View',
                        child: Icon(Icons.visibility, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (canEdit)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _navigateToRideView(ride, true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          minimumSize: const Size(44, 40),
                        ),
                        child: const Tooltip(
                          message: 'Edit',
                          child: Icon(Icons.edit, size: 20),
                        ),
                      ),
                    ),
                  if (canEditEffective) const SizedBox(width: 8),
                  if (canCancelEffective)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showCancelConfirmation(ride),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          minimumSize: const Size(44, 40),
                        ),
                        child: const Tooltip(
                          message: 'Cancel',
                          child: Icon(Icons.cancel, size: 20),
                        ),
                      ),
                    ),
                  if (canCancelEffective) const SizedBox(width: 8),
                  if (canDelete)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showDeleteConfirmation(ride),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          minimumSize: const Size(44, 40),
                        ),
                        child: const Tooltip(
                          message: 'Delete',
                          child: Icon(Icons.delete, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
            ] else ...[
              // Buttons for requested/booked rides (passenger view)
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                  if (_canStartPassengerRide(ride) || hasPersistedPassengerSession)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final tripId = (ride['trip_id'] ?? ride['trip']?['trip_id'])?.toString() ?? '';

                          // Prefer the numeric internal id for booking; many APIs expose a
                          // human-readable booking_id string like "B254-..." which cannot be
                          // parsed to int and should NOT be used as the primary identifier.
                          final rawNumericId = ride['id'] ?? ride['db_id'];
                          final rawCodeId = ride['booking_id'];

                          int? bookingId;
                          if (rawNumericId is int) {
                            bookingId = rawNumericId;
                          } else if (rawNumericId is String) {
                            bookingId = int.tryParse(rawNumericId);
                          } else if (rawCodeId is int) {
                            bookingId = rawCodeId;
                          } else if (rawCodeId is String) {
                            bookingId = int.tryParse(rawCodeId);
                          }

                          final rawId = rawNumericId ?? rawCodeId;
                          final userId = int.tryParse(widget.userData['id']?.toString() ?? '') ?? 0;
                          debugPrint('[MyRides] StartRide tapped: tripId=$tripId bookingRaw=$rawId parsedBookingId=$bookingId userId=$userId');
                          if (tripId.isEmpty || bookingId == null || userId == 0) {
                            debugPrint('[MyRides] StartRide aborted: missing identifiers');
                            return;
                          }

                          () async {
                            try {
                              final res = await ApiService.getBookingPaymentDetails(
                                bookingId: bookingId!,
                                role: 'PASSENGER',
                                userId: userId,
                              );
                              final b = (res['booking'] is Map) ? Map<String, dynamic>.from(res['booking'] as Map) : <String, dynamic>{};
                              final bookingStatus = (b['booking_status'] ?? '').toString().toUpperCase();
                              final paymentStatus = (b['payment_status'] ?? '').toString().toUpperCase();

                              final shouldGoToPayment = bookingStatus == 'COMPLETED' && paymentStatus != 'COMPLETED';
                              if (!mounted) return;

                              if (shouldGoToPayment) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PassengerPaymentScreen(
                                      tripId: tripId,
                                      passengerId: userId,
                                      bookingId: bookingId!,
                                    ),
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PassengerLiveTrackingScreen(
                                      tripId: tripId,
                                      passengerId: userId,
                                      bookingId: bookingId!,
                                    ),
                                  ),
                                ).then((_) => _loadPersistedLiveTrackingSession());
                              }
                            } catch (_) {
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PassengerLiveTrackingScreen(
                                    tripId: tripId,
                                    passengerId: userId,
                                    bookingId: bookingId!,
                                  ),
                                ),
                              ).then((_) => _loadPersistedLiveTrackingSession());
                            }
                          }();
                        },
                        icon: Icon(
                          hasPersistedPassengerSession ? Icons.play_circle_fill : Icons.play_circle_outline,
                          size: 16,
                        ),
                        label: Text(
                          (() {
                            final bookingStatus = (ride['status'] ?? '').toString().toUpperCase();
                            final paymentStatus = (ride['payment_status'] ?? '').toString().toUpperCase();
                            final needsPayment = bookingStatus == 'COMPLETED' &&
                                paymentStatus.isNotEmpty &&
                                paymentStatus != 'COMPLETED';
                            if (needsPayment) return 'Complete Payment';
                            return hasPersistedPassengerSession ? 'Resume Ride' : 'Start Ride';
                          })(),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                        ),
                      ),
                    ),
                  if (_canStartPassengerRide(ride) || hasPersistedPassengerSession) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showBookingDetails(ride),
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: const Text('View Details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Negotiation button removed; access via Booking Details app bar
                  if (_canCancelBooking(status))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showCancelBookingConfirmation(ride),
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Cancel Request'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  // Build info row
  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  // Check if booking can be cancelled (not in process stage)
  bool _canCancelBooking(String status) {
    final lowerStatus = status.toLowerCase();
    return lowerStatus == 'pending' || 
           lowerStatus == 'active' || 
           lowerStatus == 'requested' ||
           lowerStatus == 'booked';
  }

  // Show booking details dialog
  void _showBookingDetails(Map<String, dynamic> booking) {
    () async {
      final tripId = (booking['trip_id'] ?? booking['trip']?['trip_id'])?.toString();
      Map<String, dynamic> merged = Map<String, dynamic>.from(booking);

      // If we have a trip id, fetch heavy details first
      if (tripId != null && tripId.isNotEmpty) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
        try {
          final detail = await ApiService.getRideBookingDetails(tripId);
          // Merge trip core fields
          if (detail['trip'] is Map<String, dynamic>) {
            final existingTrip = (merged['trip'] is Map<String, dynamic>)
                ? Map<String, dynamic>.from(merged['trip'] as Map)
                : <String, dynamic>{};
            merged['trip'] = {
              ...existingTrip,
              ...Map<String, dynamic>.from(detail['trip']),
            };
          }

          // Merge driver and vehicle for detailed booking view
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

          // Helper fields for fare and stop breakdown
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
          // ignore network errors and proceed with summary
        }
        if (mounted) Navigator.of(context).pop();
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookingDetailScreen(
            booking: merged,
            userData: widget.userData,
          ),
        ),
      );
    }();
  }

  // Show cancel booking confirmation dialog
  void _showCancelBookingConfirmation(Map<String, dynamic> ride) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking Request'),
        content: Text(
          'Are you sure you want to cancel your booking request for the ride from ${_originName(ride)} to ${_destinationName(ride)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelBookingRequest(ride);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
  }

  // Cancel booking request
  void _cancelBookingRequest(Map<String, dynamic> booking) {
    final rawId = booking['id'] ?? booking['db_id'] ?? booking['booking_id'];
    int? bookingId;
    if (rawId is int) {
      bookingId = rawId;
    } else if (rawId is String) {
      bookingId = int.tryParse(rawId);
    }

    if (bookingId == null) {
      debugPrint('WARN: Cannot cancel booking, invalid booking identifiers: id=${booking['id']} booking_id=${booking['booking_id']}');
      return;
    }

    _controller.cancelBooking(bookingId, 'Cancelled by passenger');
  }

  // Show cancel confirmation dialog
  void _showCancelConfirmation(Map<String, dynamic> ride) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride'),
        content: Text(
          'Are you sure you want to cancel this ride from ${_originName(ride)} to ${_destinationName(ride)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _controller.cancelRide(ride['trip_id']);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );
  }

  // Build empty state for created rides
  Widget _buildEmptyCreatedRides() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No rides created yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first ride to get started',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              if (!_canCreateRide) {
                final msg = _createRideBlockMessage ?? 'You are not eligible to create rides.';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg)),
                );
                return;
              }
              Navigator.pushReplacementNamed(
                context,
                '/create_ride',
                arguments: widget.userData,
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Create Ride'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Build empty state for requested rides
  Widget _buildEmptyRequestedRides() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_seat_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No ride requests yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Book a ride to see your requests here',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/home');
            },
            icon: const Icon(Icons.search),
            label: const Text('Find Rides'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Build ride list for a specific tab
  Widget _buildRideList(List<Map<String, dynamic>> rides, bool isCreatedRides) {
    if (rides.isEmpty) {
      return isCreatedRides ? _buildEmptyCreatedRides() : _buildEmptyRequestedRides();
    }

    return RefreshIndicator(
      onRefresh: () async {
        final userId = _extractUserId();
        if (userId > 0) {
          await _controller.loadUserRides(userId);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rides.length,
        itemBuilder: (context, index) {
          final ride = rides[index];
          return _buildRideCard(ride, isCreatedRides);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rides'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final userId = int.tryParse(widget.userData['id']?.toString() ?? '')
                  ?? int.tryParse(widget.userData['user_id']?.toString() ?? '')
                  ?? 0;
              if (userId > 0) {
                _controller.loadUserRides(userId);
              }
            },
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.directions_car),
              text: 'Created Rides',
            ),
            Tab(
              icon: Icon(Icons.event_seat),
              text: 'My Bookings',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Created Rides Tab
                      _buildRideList(createdRides, true),
                      // Requested/Booked Rides Tab
                      _buildRideList(requestedRides, false),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          final isCreatedTab = _tabController.index == 0;
          final fab = isCreatedTab
              ? FloatingActionButton.extended(
                  onPressed: () {
                          if (!_canCreateRide) {
                            final msg = _createRideBlockMessage ?? 'You are not eligible to create rides.';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                            return;
                          }
                          Navigator.pushReplacementNamed(
                            context,
                            '/create_ride',
                            arguments: widget.userData,
                          );
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Create Ride'),
                  backgroundColor: _canCreateRide ? Colors.green : Colors.grey,
                  foregroundColor: Colors.white,
                )
              : FloatingActionButton.extended(
                  onPressed: () {
                          Navigator.pushReplacementNamed(context, '/home');
                        },
                  icon: const Icon(Icons.search),
                  label: const Text('Find Rides'),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                );
          return fab;
        },
      ),
    );
  }
}
