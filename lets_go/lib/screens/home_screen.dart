import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/live_tracking_session_manager.dart';
import '../utils/image_utils.dart';
import '../utils/map_util.dart';
import 'post_booking_screens/driver_live_tracking_screen.dart';
import 'post_booking_screens/driver_payment_confirmation_screen.dart';
import 'post_booking_screens/passenger_live_tracking_screen.dart';
import 'post_booking_screens/passenger_payment_screen.dart';
import 'ride_booking_screens/ride_booking_details_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const HomeScreen({
    super.key,
    required this.userData,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> rides = [];
  List<Map<String, dynamic>> _pendingNewRides = [];
  int _pendingNewRidesCount = 0;
  Timer? _newRidesPollTimer;
  bool isLoading = true;
  String? errorMessage;

  final AppLinks _appLinks = AppLinks();

  StreamSubscription? _tripShareLinkSub;
  bool _didCheckInitialTripShareLink = false;

  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _minSeatsController = TextEditingController();

  String? _genderPreference;
  String? _negotiableFilter;
  String? _timeFrom;
  String? _timeTo;
  String? _sort;

  Map<String, dynamic>? _selectedFromStop;
  Map<String, dynamic>? _selectedToStop;

  bool _didAttemptResumeLiveTracking = false;

  int _notificationUnreadCount = 0;
  Timer? _notificationPollTimer;

  @override
  void initState() {
    super.initState();
    _maybeResumeLiveTracking();
    _loadRides();
    _listenForTripShareLinks();
    _refreshNotificationUnreadCount();
    _notificationPollTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refreshNotificationUnreadCount(silent: true),
    );

    _newRidesPollTimer = Timer.periodic(
      const Duration(seconds: 35),
      (_) => _checkForNewRides(silent: true),
    );
  }

  @override
  void dispose() {
    _tripShareLinkSub?.cancel();
    _notificationPollTimer?.cancel();
    _newRidesPollTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _minSeatsController.dispose();
    super.dispose();
  }

  String _rideKey(Map<String, dynamic> ride) {
    final raw = ride['trip_id'] ?? ride['id'] ?? '';
    return raw.toString();
  }

  Future<void> _checkForNewRides({bool silent = false}) async {
    try {
      if (!mounted) return;
      if (isLoading) return;

      final userId = _extractUserId();
      final hasAnyCriteria = _hasAnySearchCriteria();
      final latest = hasAnyCriteria
          ? await ApiService.searchTrips(
              userId: userId,
              fromStopId: _selectedFromStopId(),
              toStopId: _selectedToStopId(),
              from: _fromController.text,
              to: _toController.text,
              minSeats: int.tryParse(_minSeatsController.text.trim()),
              genderPreference: _genderPreference,
              negotiable: _negotiableFilter == null
                  ? null
                  : (_negotiableFilter == 'negotiable' ? true : false),
              timeFrom: _timeFrom,
              timeTo: _timeTo,
              sort: _sort,
            )
          : await ApiService.getAllTrips(userId: userId);

      final currentKeys = rides.map(_rideKey).where((e) => e.isNotEmpty).toSet();
      final newOnes = latest.where((r) {
        final k = _rideKey(r);
        return k.isNotEmpty && !currentKeys.contains(k);
      }).toList();

      if (newOnes.length <= 10) {
        if (!silent && mounted) {
          setState(() {
            _pendingNewRides = [];
            _pendingNewRidesCount = 0;
          });
        } else if (_pendingNewRidesCount != 0 && mounted) {
          setState(() {
            _pendingNewRides = [];
            _pendingNewRidesCount = 0;
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _pendingNewRides = latest;
        _pendingNewRidesCount = newOnes.length;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _refreshNotificationUnreadCount({bool silent = false}) async {
    try {
      final uidRaw = widget.userData['id'];
      final uid = uidRaw is int ? uidRaw : int.tryParse(uidRaw?.toString() ?? '') ?? 0;
      if (uid <= 0) return;
      final c = await ApiService.getNotificationUnreadCount(userId: uid);
      if (!mounted) return;
      if (silent && c == _notificationUnreadCount) return;
      setState(() => _notificationUnreadCount = c);
    } catch (_) {}
  }

  String? _extractTripShareToken(Uri uri) {
    try {
      final seg = uri.pathSegments;
      int i = seg.indexOf('share');
      if (i < 0) i = seg.indexOf('share-app');
      if (i >= 0 && i + 1 < seg.length && seg.contains('trips')) {
        final token = seg[i + 1].trim();
        if (token.isNotEmpty) return token;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openTripFromShareToken(String token) async {
    final userId = _extractUserId();
    if (userId <= 0) return;

    final tripId = await ApiService.resolveTripShareTokenToTripId(token);
    if (!mounted) return;
    if (tripId == null || tripId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid or expired link')),
      );
      return;
    }

    final ok = await ApiService.isTripAvailableForUser(userId: userId, tripId: tripId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not available for you')),
      );
      return;
    }

    Map<String, dynamic> rideData = <String, dynamic>{'trip_id': tripId};
    try {
      final detail = await ApiService.getRideBookingDetails(tripId);
      if (detail.isNotEmpty) {
        rideData = {
          ...detail,
          if (!detail.containsKey('trip_id')) 'trip_id': tripId,
        };
      }
    } catch (_) {
      // ignore
    }
    if (!mounted) return;

    Navigator.pushNamed(
      context,
      '/ride-view-edit',
      arguments: {
        'ride': rideData,
        'isEditMode': false,
        'userData': widget.userData,
      },
    );
  }

  void _listenForTripShareLinks() {
    if (_tripShareLinkSub != null) return;

    () async {
      if (_didCheckInitialTripShareLink) return;
      _didCheckInitialTripShareLink = true;

      try {
        final initial = await _appLinks.getInitialLink();
        if (!mounted) return;
        String? token;
        if (initial != null) {
          token = _extractTripShareToken(initial);
        }

        token ??= await _takePendingTripShareToken();
        if (!mounted) return;
        if (token != null) {
          await _openTripFromShareToken(token);
        }
      } catch (_) {
        // ignore
      }
    }();

    _tripShareLinkSub = _appLinks.uriLinkStream.listen(
      (uri) async {
        final token = _extractTripShareToken(uri);
        if (token == null) return;
        await _openTripFromShareToken(token);
      },
      onError: (_) {},
    );
  }

  Future<String?> _takePendingTripShareToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString('pending_trip_share_token') ?? '').trim();
      if (token.isEmpty) return null;
      await prefs.remove('pending_trip_share_token');
      return token;
    } catch (_) {
      return null;
    }
  }

  int _extractUserId() {
    return int.tryParse(widget.userData['id']?.toString() ?? '') ??
        int.tryParse(widget.userData['user_id']?.toString() ?? '') ??
        0;
  }

  int? _selectedFromStopId() {
    final raw = _selectedFromStop?['id'];
    final id = int.tryParse(raw?.toString() ?? '');
    if (id == null || id <= 0) return null;
    return id;
  }

  int? _selectedToStopId() {
    final raw = _selectedToStop?['id'];
    final id = int.tryParse(raw?.toString() ?? '');
    if (id == null || id <= 0) return null;
    return id;
  }

  Future<LatLng?> _getCurrentLatLng() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openStopPicker({required bool isFrom}) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final searchController = TextEditingController();
        final mapController = MapController();
        Timer? debounce;
        bool isInit = false;

        bool isLoadingStops = false;
        LatLng center = const LatLng(31.5204, 74.3587);
        LatLng? currentLocation;
        LatLng? pinned;
        List<Map<String, dynamic>> results = [];

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> suggest({String? query, LatLng? point}) async {
              setModalState(() {
                isLoadingStops = true;
              });
              try {
                final p = point;
                final data = await ApiService.suggestStops(
                  query: query,
                  lat: p?.latitude,
                  lng: p?.longitude,
                  radiusKm: 8,
                  limit: 3,
                );
                setModalState(() {
                  results = data;
                });
              } catch (_) {
                // ignore
              } finally {
                setModalState(() {
                  isLoadingStops = false;
                });
              }
            }

            Future<void> initOnce() async {
              if (isInit) return;
              isInit = true;
              final current = await _getCurrentLatLng();
              if (current != null) {
                setModalState(() {
                  center = current;
                  currentLocation = current;
                });

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  try {
                    mapController.move(current, 13);
                  } catch (_) {}
                });
              }
              await suggest(query: '', point: current ?? center);
            }

            // kick off init
            // ignore: discarded_futures
            initOnce();

            final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isFrom ? 'Select pickup stop' : 'Select drop-off stop',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search stop (typos ok)',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          debounce?.cancel();
                          debounce = Timer(const Duration(milliseconds: 250), () {
                            // if user typed manually, prefer text search but keep location bias if pinned
                            // ignore: discarded_futures
                            suggest(query: value, point: pinned ?? center);
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: FlutterMap(
                                  mapController: mapController,
                                  options: MapOptions(
                                    initialCenter: center,
                                    initialZoom: 13,
                                    onTap: (tapPos, point) {
                                      setModalState(() {
                                        pinned = point;
                                      });
                                      // ignore: discarded_futures
                                      suggest(query: searchController.text, point: point);
                                    },
                                  ),
                                  children: [
                                    MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
                                    MarkerLayer(
                                      markers: [
                                        if (currentLocation != null)
                                          Marker(
                                            point: currentLocation!,
                                            width: 36,
                                            height: 36,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withAlpha(38),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: const Center(
                                                child: Icon(Icons.my_location, color: Colors.blue, size: 20),
                                              ),
                                            ),
                                          ),
                                        if (pinned != null)
                                          Marker(
                                            point: pinned!,
                                            width: 40,
                                            height: 40,
                                            child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Container(
                              height: 160,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  if (isLoadingStops)
                                    const LinearProgressIndicator(minHeight: 2),
                                  Expanded(
                                    child: results.isEmpty
                                        ? const Center(child: Text('No stops found'))
                                        : ListView.separated(
                                            itemCount: results.length > 3 ? 3 : results.length,
                                            separatorBuilder: (_, __) => const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final s = results[index];
                                              final name = (s['stop_name'] ?? '').toString();
                                              final routeName = (s['route_name'] ?? '').toString();
                                              final distanceM = s['distance_m'];
                                              final distanceText = distanceM == null
                                                  ? ''
                                                  : ' • ${(double.tryParse(distanceM.toString()) ?? 0).round()}m';
                                              return ListTile(
                                                dense: true,
                                                title: Text(name.isEmpty ? 'Stop' : name),
                                                subtitle: Text(routeName.isEmpty ? '' : '$routeName$distanceText'),
                                                onTap: () {
                                                  Navigator.pop(context, s);
                                                },
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || picked == null) return;
    setState(() {
      if (isFrom) {
        _selectedFromStop = picked;
        _fromController.text = (picked['stop_name'] ?? '').toString();
      } else {
        _selectedToStop = picked;
        _toController.text = (picked['stop_name'] ?? '').toString();
      }
    });
    await _loadRides();
  }


  Future<void> _maybeResumeLiveTracking() async {
    if (_didAttemptResumeLiveTracking) return;
    _didAttemptResumeLiveTracking = true;

    try {
      final session = await LiveTrackingSessionManager.instance.readPersistedSession();
      if (!mounted || session == null) return;

      final userId = int.tryParse(widget.userData['id']?.toString() ?? '') ??
          int.tryParse(widget.userData['user_id']?.toString() ?? '') ??
          0;
      if (userId == 0) return;

      if (session['user_id'] != userId) {
        return;
      }

      final tripId = session['trip_id']?.toString();
      final isDriver = session['is_driver'] == true;
      final bookingId = session['booking_id'];

      if (tripId == null || tripId.isEmpty) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isDriver) {
          () async {
            try {
              final layout = await ApiService.getRideBookingDetails(tripId);
              final trip = (layout['trip'] is Map)
                  ? Map<String, dynamic>.from(layout['trip'] as Map)
                  : <String, dynamic>{};
              final tripStatus = (trip['trip_status'] ?? trip['status'] ?? '').toString().toUpperCase();

              if (tripStatus == 'COMPLETED') {
                final res = await ApiService.getTripPayments(
                  tripId: tripId,
                  driverId: userId,
                );
                final list = (res['payments'] is List) ? List.from(res['payments'] as List) : <dynamic>[];
                final hasPending = res['success'] == true &&
                    list
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e))
                        .any((p) => (p['payment_status'] ?? '').toString().toUpperCase() != 'COMPLETED');

                if (!mounted) return;

                if (hasPending) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DriverPaymentConfirmationScreen(
                        tripId: tripId,
                        driverId: userId,
                      ),
                    ),
                  );
                } else {
                  await LiveTrackingSessionManager.instance.stopSession();
                }
                return;
              }

              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverLiveTrackingScreen(
                    tripId: tripId,
                    driverId: userId,
                  ),
                ),
              );
            } catch (_) {
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverLiveTrackingScreen(
                    tripId: tripId,
                    driverId: userId,
                  ),
                ),
              );
            }
          }();
        } else {
          if (bookingId is! int) return;
          () async {
            try {
              final res = await ApiService.getBookingPaymentDetails(
                bookingId: bookingId,
                role: 'PASSENGER',
                userId: userId,
              );
              final b = (res['booking'] is Map) ? Map<String, dynamic>.from(res['booking'] as Map) : <String, dynamic>{};
              final bookingStatus = (b['booking_status'] ?? '').toString().toUpperCase();
              final paymentStatus = (b['payment_status'] ?? '').toString().toUpperCase();

              final shouldGoToPayment = bookingStatus == 'COMPLETED' && paymentStatus != 'COMPLETED';
              if (!mounted) return;

              if (shouldGoToPayment) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PassengerPaymentScreen(
                      tripId: tripId,
                      passengerId: userId,
                      bookingId: bookingId,
                    ),
                  ),
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PassengerLiveTrackingScreen(
                      tripId: tripId,
                      passengerId: userId,
                      bookingId: bookingId,
                    ),
                  ),
                );
              }
            } catch (_) {
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PassengerLiveTrackingScreen(
                    tripId: tripId,
                    passengerId: userId,
                    bookingId: bookingId,
                  ),
                ),
              );
            }
          }();
        }
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadRides() async {
    try {
      if (!mounted) return;
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final userId = _extractUserId();
      final hasAnyCriteria = _hasAnySearchCriteria();

      final ridesData = hasAnyCriteria
          ? await ApiService.searchTrips(
              userId: userId,
              fromStopId: _selectedFromStopId(),
              toStopId: _selectedToStopId(),
              from: _fromController.text,
              to: _toController.text,
              minSeats: int.tryParse(_minSeatsController.text.trim()),
              genderPreference: _genderPreference,
              negotiable: _negotiableFilter == null
                  ? null
                  : (_negotiableFilter == 'negotiable' ? true : false),
              timeFrom: _timeFrom,
              timeTo: _timeTo,
              sort: _sort,
            )
          : await ApiService.getAllTrips(userId: userId);
      
      if (!mounted) return;
      setState(() {
        rides = ridesData;
        _pendingNewRides = [];
        _pendingNewRidesCount = 0;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Failed to load rides: $e';
        isLoading = false;
      });
    }
  }

  bool _hasAnySearchCriteria() {
    if (_selectedFromStopId() != null) return true;
    if (_selectedToStopId() != null) return true;
    if (_fromController.text.trim().isNotEmpty) return true;
    if (_toController.text.trim().isNotEmpty) return true;
    if (_minSeatsController.text.trim().isNotEmpty) return true;
    if (_genderPreference != null && _genderPreference!.trim().isNotEmpty) return true;
    if (_negotiableFilter != null && _negotiableFilter!.trim().isNotEmpty) return true;
    if (_timeFrom != null && _timeFrom!.trim().isNotEmpty) return true;
    if (_timeTo != null && _timeTo!.trim().isNotEmpty) return true;
    if (_sort != null && _sort!.trim().isNotEmpty) return true;
    return false;
  }

  Future<void> _pickTime({
    required bool isFrom,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    setState(() {
      if (isFrom) {
        _timeFrom = '$hh:$mm';
      } else {
        _timeTo = '$hh:$mm';
      }
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _genderPreference,
                    decoration: const InputDecoration(
                      labelText: 'Gender preference',
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any')),
                      DropdownMenuItem(value: 'Any', child: Text('Any only')),
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                    ],
                    onChanged: (value) {
                      setModalState(() {
                        _genderPreference = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _negotiableFilter,
                    decoration: const InputDecoration(
                      labelText: 'Negotiation',
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any')),
                      DropdownMenuItem(value: 'negotiable', child: Text('Negotiation allowed')),
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed price')),
                    ],
                    onChanged: (value) {
                      setModalState(() {
                        _negotiableFilter = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minSeatsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minimum seats',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(isFrom: true),
                          child: Text(_timeFrom == null || _timeFrom!.isEmpty ? 'Time from' : _timeFrom!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(isFrom: false),
                          child: Text(_timeTo == null || _timeTo!.isEmpty ? 'Time to' : _timeTo!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _sort,
                    decoration: const InputDecoration(
                      labelText: 'Sort',
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Default (Soonest)')),
                      DropdownMenuItem(value: 'soonest', child: Text('Soonest')),
                      DropdownMenuItem(value: 'latest', child: Text('Latest')),
                      DropdownMenuItem(value: 'price_asc', child: Text('Price (low to high)')),
                      DropdownMenuItem(value: 'price_desc', child: Text('Price (high to low)')),
                      DropdownMenuItem(value: 'seats_desc', child: Text('Most seats')),
                    ],
                    onChanged: (value) {
                      setModalState(() {
                        _sort = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _genderPreference = null;
                              _negotiableFilter = null;
                              _minSeatsController.clear();
                              _timeFrom = null;
                              _timeTo = null;
                              _sort = null;
                            });
                            Navigator.of(context).pop();
                            _loadRides();
                          },
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {});
                            Navigator.of(context).pop();
                            _loadRides();
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _refreshRides() async {
    await _loadRides();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Refresh',
          onPressed: _refreshRides,
          icon: Image.asset(
            'assets/images/white-only-transparent-icon.png',
            width: 28,
            height: 28,
          ),
        ),
        title: const Text('Available Rides', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.pushNamed(context, '/notifications', arguments: widget.userData);
              await _refreshNotificationUnreadCount();
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications),
                if (_notificationUnreadCount > 0)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.directions_car),
            onPressed: () {
              Navigator.pushNamed(context, '/my-rides', arguments: widget.userData);
            },
            tooltip: 'My Rides',
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.pushNamed(context, '/profile', arguments: widget.userData);
            },
            tooltip: 'My Profile',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pendingNewRidesCount > 10)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_pendingNewRides.isEmpty) return;
                    setState(() {
                      rides = _pendingNewRides;
                      _pendingNewRides = [];
                      _pendingNewRidesCount = 0;
                    });
                  },
                  icon: const Icon(Icons.new_releases_outlined),
                  label: Text('See $_pendingNewRidesCount new rides'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromController,
                    textInputAction: TextInputAction.next,
                    readOnly: true,
                    decoration: const InputDecoration(
                      hintText: 'From',
                      prefixIcon: Icon(Icons.trip_origin),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onTap: () => _openStopPicker(isFrom: true),
                    onSubmitted: (_) => _loadRides(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _toController,
                    textInputAction: TextInputAction.search,
                    readOnly: true,
                    decoration: const InputDecoration(
                      hintText: 'To',
                      prefixIcon: Icon(Icons.flag),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onTap: () => _openStopPicker(isFrom: false),
                    onSubmitted: (_) => _loadRides(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune),
                  tooltip: 'Filters',
                ),
                IconButton(
                  onPressed: _loadRides,
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshRides,
              child: _buildBody(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'support_fab_home',
        onPressed: () {
          Navigator.pushNamed(context, '/support-chat', arguments: widget.userData);
        },
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.support_agent),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: TextStyle(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRides,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No rides available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting filters or searching different stops.',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rides.length,
      itemBuilder: (context, index) {
        final ride = rides[index];
        return _buildRideCard(ride);
      },
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final departureTime = DateTime.parse(ride['departure_time']);
    final isToday = departureTime.isAfter(DateTime.now().subtract(const Duration(days: 1)));

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    final rawScore = ride['recommendation_score'] ?? ride['score'] ?? ride['ranking_score'];
    double? score = toDouble(rawScore);
    // Backend score is expected 0..1, but defensively handle 0..100.
    if (score != null && score > 1.0) {
      score = score / 100.0;
    }
    final int? scorePercent = (score == null)
        ? null
        : (score.clamp(0.0, 1.0) * 100).round();
    final bool isHighlyRecommended = (scorePercent != null) && scorePercent >= 90;

    String? vehicleThumbUrl() {
      try {
        final direct = ride['vehicle_photo_front'] ??
            ride['vehicle_front_photo_url'] ??
            ride['vehicle_front_image'] ??
            ride['vehicle_image_url'] ??
            ride['vehicle_image'];
        final ensured = ImageUtils.ensureValidImageUrl(direct?.toString());
        if (ensured != null && ImageUtils.isValidImageUrl(ensured)) return ensured;

        final vehicle = ride['vehicle'];
        if (vehicle is Map) {
          final raw = vehicle['photo_front'] ?? vehicle['front_image'] ?? vehicle['image_url'];
          final ensured2 = ImageUtils.ensureValidImageUrl(raw?.toString());
          if (ensured2 != null && ImageUtils.isValidImageUrl(ensured2)) return ensured2;
        }
      } catch (_) {}
      return null;
    }
    final vThumb = vehicleThumbUrl();
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RideBookingDetailsScreen(
                userData: widget.userData,
                tripId: ride['trip_id'] ?? ride['id'] ?? '',
              ),
            ),
          ).then((_) => _refreshRides());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with time and status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMM dd, HH:mm').format(departureTime),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (scorePercent != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$scorePercent%',
                            style: TextStyle(
                              color: Colors.blue.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (scorePercent != null) const SizedBox(width: 8),
                      if (isHighlyRecommended)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Recommended',
                            style: TextStyle(
                              color: Colors.teal.shade900,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (isHighlyRecommended) const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isToday ? Colors.orange.shade100 : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isToday ? 'Today' : DateFormat('MMM dd').format(departureTime),
                          style: TextStyle(
                            color: isToday ? Colors.orange.shade800 : Colors.green.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Route information
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride['origin'] ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 2,
                              height: 20,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ride['destination'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward,
                    color: Colors.teal,
                    size: 24,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Driver and vehicle info
              Row(
                children: [
                  Builder(
                    builder: (context) {
                      final photo = (ride['driver_profile_photo_url'] ?? '').toString();
                      final hasPhoto = photo.isNotEmpty;
                      return CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.teal.shade100,
                        backgroundImage: hasPhoto ? NetworkImage(photo) : null,
                        child: hasPhoto
                            ? null
                            : Text(
                                (ride['driver_name'] ?? 'D')[0].toUpperCase(),
                                style: TextStyle(
                                  color: Colors.teal.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride['driver_name'] ?? 'Unknown Driver',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          ride['vehicle_model'] ?? 'Unknown Vehicle',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (vThumb != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        vThumb,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 44,
                            height: 44,
                            color: Colors.grey.shade200,
                            child: Icon(
                              Icons.directions_car,
                              color: Colors.grey.shade600,
                              size: 22,
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.directions_car,
                        color: Colors.grey.shade600,
                        size: 22,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Seats and price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.event_seat,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ride['available_seats']} seats available',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Rs. ${ride['price_per_seat']?.toStringAsFixed(0) ?? '0'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),

              // Gender preference
              if (ride['gender_preference'] != null && ride['gender_preference'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ride['gender_preference']} only',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}