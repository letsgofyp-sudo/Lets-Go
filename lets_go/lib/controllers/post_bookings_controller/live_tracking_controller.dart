import 'dart:async';

import 'dart:io';



import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';

import 'package:latlong2/latlong.dart';

import 'package:permission_handler/permission_handler.dart';



import '../../utils/road_polyline_service.dart';
import '../../utils/map_util.dart';

import '../../services/api_service.dart';

import '../../services/background_live_tracking_service.dart';

import '../../services/offline_location_queue.dart';



class LiveTrackingController {

  final String tripId;

  final int currentUserId;

  final int? bookingId;

  final bool isDriver;



  VoidCallback? onStateChanged;



  bool isLoading = false;

  String? errorMessage;

  bool rideStarted = false;

  bool pickupVerified = false;

  String? tripStatus;

  String? bookingStatus;

  String? bookingRideStatus;



  String? activePickupCode;

  DateTime? pickupExpiresAt;

  int? pickupMaxAttempts;

  int? pickupRemainingAttempts;

  bool isGeneratingCode = false;

  bool isVerifyingCode = false;



  LatLng? driverPosition;

  LatLng? myPosition;

  List<Map<String, dynamic>> passengers = [];



  List<LatLng> driverPathPolyline = [];



  double? driverSpeedKph;

  int? driverEtaSecondsToFinal;

  int? passengerEtaSecondsToDropoff;



  bool? isDriverDeviating;

  double? driverDeviationMeters;



  bool driverSignalLost = false;

  int? driverLastSeenSeconds;



  // Trip layout for map rendering

  List<Map<String, dynamic>> routeStops = [];

  List<LatLng> routePolyline = [];



  DateTime? tripDepartureDateTime;



  // Pickup / dropoff points for all passengers (driver view)

  List<LatLng> allPickupPoints = [];

  List<LatLng> allDropoffPoints = [];



  // Pickup / dropoff points for the current passenger (passenger view)

  LatLng? passengerPickupPoint;

  LatLng? passengerDropoffPoint;



  int? passengerFromStopOrder;

  int? passengerToStopOrder;



  List<Map<String, dynamic>> confirmedPassengerBookings = [];

  int? selectedBookingId;



  Timer? _pollTimer;

  StreamSubscription<Position>? _positionSubscription;

  Timer? _sendTimer;

  Position? _latestPosition;

  LatLng? _lastSentPoint;

  bool _locationStarted = false;



  bool _flushInProgress = false;

  DateTime? _lastFlushAt;



  LiveTrackingController({

    required this.tripId,

    required this.currentUserId,

    this.bookingId,

    required this.isDriver,

  });



  Future<void> refreshTripLayout() async {

    await _loadTripLayout();

  }



  void setSelectedBookingId(int? id) {

    selectedBookingId = id;

    onStateChanged?.call();

  }



  Future<void> _ensureAndStartLocation() async {

    if (_locationStarted) return;

    _locationStarted = true;

    try {

      await _ensureLocationPermission();

      await _startPositionStream();

      _startPeriodicLocationSend();

    } catch (e) {

      _locationStarted = false;

      rethrow;

    }

  }



  double? _asDouble(dynamic v) {

    if (v == null) return null;

    if (v is num) return v.toDouble();

    if (v is String) return double.tryParse(v);

    return null;

  }



  int? _asIntSafe(dynamic v) {

    if (v == null) return null;

    if (v is int) return v;

    if (v is num) return v.toInt();

    if (v is String) return int.tryParse(v);

    return null;

  }



  int? _asInt(dynamic v) {

    if (v == null) return null;

    if (v is int) return v;

    if (v is num) return v.toInt();

    if (v is String) return int.tryParse(v);

    return null;

  }



  double? _stopLat(Map<String, dynamic> stop) {

    return _asDouble(stop['lat'] ?? stop['latitude'] ?? stop['stop_lat'] ?? stop['stop_latitude']);

  }



  double? _stopLng(Map<String, dynamic> stop) {

    return _asDouble(stop['lng'] ?? stop['lon'] ?? stop['longitude'] ?? stop['stop_lng'] ?? stop['stop_longitude']);

  }



  Future<void> init() async {

    debugPrint('[LiveTracking] init: tripId=$tripId currentUserId=$currentUserId isDriver=$isDriver bookingId=$bookingId');



    // Do NOT send live location until the user explicitly starts the ride.

    // This also protects against a previously persisted session where background sending

    // was left enabled.

    try {

      await BackgroundLiveTrackingService.setSendEnabled(false);

      await BackgroundLiveTrackingService.stop();

    } catch (_) {}



    // Fire-and-forget load of trip layout for richer map display.

    _loadTripLayout();

    _startPollingLiveState();

  }



  void detachUi() {

    onStateChanged = null;

  }



  Future<void> startRide() async {

    try {

      debugPrint('[LiveTracking] startRide called (isDriver=$isDriver, tripId=$tripId, bookingId=$bookingId)');

      isLoading = true;

      errorMessage = null;

      onStateChanged?.call();



      final gate = await ApiService.getVerificationGateStatus(currentUserId);

      if (gate['blocked'] == true) {

        errorMessage = (gate['message'] ?? 'Verification pending.').toString();

        return;

      }



      if (isDriver) {

        final res = await ApiService.startTripRide(

          tripId: tripId,

          driverId: currentUserId,

        );

        debugPrint('[LiveTracking] startTripRide response: $res');

        rideStarted = res['success'] == true;

        if (!rideStarted) {

          errorMessage = (res['error'] ?? 'Unable to start ride.').toString();

        }

        if (res['trip_status'] != null) {

          tripStatus = res['trip_status']?.toString();

        }

      } else {

        if (bookingId == null) {

          errorMessage = 'Missing booking id';

        } else {

          final res = await ApiService.startBookingRide(

            bookingId: bookingId!,

            passengerId: currentUserId,

          );

          debugPrint('[LiveTracking] startBookingRide response: $res');

          rideStarted = res['success'] == true;

          if (!rideStarted) {

            errorMessage = (res['error'] ?? 'Unable to start ride.').toString();

          }

          if (res['trip_status'] != null) {

            tripStatus = res['trip_status']?.toString();

          }

        }

      }



      if (rideStarted) {

        await _ensureAndStartLocation();

        await _ensureBackgroundTrackingPermissions();

        await BackgroundLiveTrackingService.setSendEnabled(true);

        await BackgroundLiveTrackingService.start();



        // Send one immediate location update so the backend starts recording the actual traveled path right away.

        try {

          Position? pos;

          try {

            pos = await Geolocator.getLastKnownPosition();

          } catch (_) {}

          pos ??= await Geolocator.getCurrentPosition(

            locationSettings: const LocationSettings(

              accuracy: LocationAccuracy.high,

            ),

          ).timeout(const Duration(seconds: 8));



          await ApiService.updateLiveLocation(

            tripId: tripId,

            userId: currentUserId,

            role: isDriver ? 'DRIVER' : 'PASSENGER',

            bookingId: isDriver ? null : bookingId,

            lat: pos.latitude,

            lng: pos.longitude,

            speed: pos.speed.isFinite ? pos.speed : null,

          );



          myPosition = LatLng(pos.latitude, pos.longitude);

          _lastSentPoint = myPosition;

        } catch (_) {}

      }

    } catch (e) {

      errorMessage = e.toString();

    } finally {

      isLoading = false;

      onStateChanged?.call();

    }

  }



  Future<void> _ensureLocationPermission() async {

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {

      permission = await Geolocator.requestPermission();

    }

    if (permission == LocationPermission.deniedForever ||

        permission == LocationPermission.denied) {

      throw Exception('Location permission denied');

    }

  }



  Future<void> _ensureBackgroundTrackingPermissions() async {

    if (!Platform.isAndroid) return;



    try {

      await Permission.notification.request();

    } catch (_) {}



    try {

      final status = await Permission.locationAlways.status;

      if (status.isDenied) {

        await Permission.locationAlways.request();

      }

    } catch (_) {}

  }



  Future<void> _startPositionStream() async {

    final settings = const LocationSettings(

      accuracy: LocationAccuracy.high,

      distanceFilter: 0,

    );



    _positionSubscription =

        Geolocator.getPositionStream(locationSettings: settings).listen(

      (pos) {

        _latestPosition = pos;

        myPosition = LatLng(pos.latitude, pos.longitude);

        _sendLocationUpdate(pos);

      },

      onError: (e) {

        errorMessage = e.toString();

        onStateChanged?.call();

      },

    );

  }



  void _startPeriodicLocationSend() {

    _sendTimer?.cancel();

    _sendTimer = Timer.periodic(const Duration(seconds: 3), (_) async {

      final pos = _latestPosition;

      if (pos == null) return;

      await _sendLocationUpdate(pos);

    });

  }



  Future<void> _sendLocationUpdate(Position pos) async {

    try {

      if (!rideStarted) {

        return;

      }



      // Android uses the background foreground-service sender. On iOS we send from foreground.

      if (Platform.isAndroid) {

        return;

      }



      await _flushOfflineQueueIfAny();



      try {

        final current = LatLng(pos.latitude, pos.longitude);
        final prev = _lastSentPoint;

        final toSend = <LatLng>[];
        if (prev != null) {
          toSend.addAll(MapUtil.densifyBetween(prev, current, maxStepMeters: 25));
        } else {
          toSend.add(current);
        }

        for (final p in toSend) {
          await ApiService.updateLiveLocation(
            tripId: tripId,
            userId: currentUserId,
            role: isDriver ? 'DRIVER' : 'PASSENGER',
            bookingId: isDriver ? null : bookingId,
            lat: p.latitude,
            lng: p.longitude,
            speed: pos.speed.isFinite ? pos.speed : null,
          );
          _lastSentPoint = p;
        }

      } catch (_) {

        await OfflineLocationQueue.enqueue(

          tripId: tripId,

          userId: currentUserId,

          role: isDriver ? 'DRIVER' : 'PASSENGER',

          bookingId: isDriver ? null : bookingId,

          lat: pos.latitude,

          lng: pos.longitude,

          speed: pos.speed.isFinite ? pos.speed : null,

        );

      }

    } catch (_) {}

  }



  Future<void> _flushOfflineQueueIfAny() async {

    if (_flushInProgress) return;

    final last = _lastFlushAt;

    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 4)) {

      return;

    }

    _flushInProgress = true;

    _lastFlushAt = DateTime.now();

    try {

      final role = isDriver ? 'DRIVER' : 'PASSENGER';

      final batch = await OfflineLocationQueue.peekBatch(

        tripId: tripId,

        userId: currentUserId,

        role: role,

        bookingId: isDriver ? null : bookingId,

        limit: 12,

      );

      if (batch.isEmpty) return;



      int sent = 0;

      for (final it in batch) {

        final latRaw = it['lat'];

        final lngRaw = it['lng'];

        final lat = latRaw is num ? latRaw.toDouble() : double.tryParse(latRaw?.toString() ?? '');

        final lng = lngRaw is num ? lngRaw.toDouble() : double.tryParse(lngRaw?.toString() ?? '');

        if (lat == null || lng == null) continue;



        final sRaw = it['s'];

        final speed = sRaw is num ? sRaw.toDouble() : double.tryParse(sRaw?.toString() ?? '');



        await ApiService.updateLiveLocation(

          tripId: tripId,

          userId: currentUserId,

          role: role,

          bookingId: isDriver ? null : bookingId,

          lat: lat,

          lng: lng,

          speed: speed,

        );

        sent += 1;

      }



      if (sent > 0) {

        await OfflineLocationQueue.dropBatch(

          tripId: tripId,

          userId: currentUserId,

          role: role,

          bookingId: isDriver ? null : bookingId,

          count: sent,

        );

      }

    } catch (_) {

      // Keep queued points if flushing fails.

    } finally {

      _flushInProgress = false;

    }

  }



  Future<void> _loadTripLayout() async {

    try {

      debugPrint('[LiveTracking] _loadTripLayout: fetching layout for tripId=$tripId');

      final data = await ApiService.getRideBookingDetails(tripId);

      debugPrint('[LiveTracking] _loadTripLayout: keys=${data.keys.toList()}');



      try {

        final trip = data['trip'];

        if (trip is Map<String, dynamic>) {

          final dateStrRaw = trip['trip_date']?.toString();

          final timeStrRaw = trip['departure_time']?.toString();

          if (dateStrRaw != null &&

              dateStrRaw.isNotEmpty &&

              timeStrRaw != null &&

              timeStrRaw.isNotEmpty) {

            String datePart = dateStrRaw;

            if (datePart.contains('T')) {

              datePart = datePart.split('T').first;

            } else if (datePart.contains(' ')) {

              datePart = datePart.split(' ').first;

            }

            if (datePart.length > 10) {

              datePart = datePart.substring(0, 10);

            }



            String timePart = timeStrRaw;

            if (timePart.contains('.')) {

              timePart = timePart.split('.').first;

            }

            // Normalize HH:mm or HH:mm:ss

            if (timePart.length == 5) {

              timePart = '$timePart:00';

            }

            if (timePart.length > 8) {

              timePart = timePart.substring(0, 8);

            }



            tripDepartureDateTime = DateTime.tryParse('${datePart}T$timePart');

          }

        }

      } catch (_) {}



      // Trip / route stops

      final trip = data['trip'] as Map<String, dynamic>?;

      final routeFromTrip = trip != null ? trip['route'] as Map<String, dynamic>? : null;

      final routeTopLevel = data['route'] as Map<String, dynamic>?;



      final dynamic rawStops = (routeTopLevel != null

              ? (routeTopLevel['stops'] ?? routeTopLevel['route_stops'])

              : null) ??

          (routeFromTrip != null

              ? (routeFromTrip['stops'] ?? routeFromTrip['route_stops'])

              : null) ??

          data['route_stops'];



      final stopsList = <Map<String, dynamic>>[];

      if (rawStops is List) {

        for (final item in rawStops) {

          if (item is Map<String, dynamic>) {

            stopsList.add(Map<String, dynamic>.from(item));

          }

        }

      }



      stopsList.sort((a, b) {

        final ao = _asInt(a['stop_order'] ?? a['order']);

        final bo = _asInt(b['stop_order'] ?? b['order']);

        if (ao == null && bo == null) return 0;

        if (ao == null) return 1;

        if (bo == null) return -1;

        return ao.compareTo(bo);

      });



      routeStops = stopsList;

      debugPrint('[LiveTracking] _loadTripLayout: routeStops=${routeStops.length}');

      final polyPoints = <LatLng>[];

      for (final s in stopsList) {

        final lat = _stopLat(s);

        final lng = _stopLng(s);

        if (lat == null || lng == null) continue;

        if (lat == 0.0 && lng == 0.0) continue;

        final pt = LatLng(lat, lng);

        if (polyPoints.isEmpty) {

          polyPoints.add(pt);

          continue;

        }

        final last = polyPoints.last;

        if (last.latitude == pt.latitude && last.longitude == pt.longitude) {

          continue;

        }

        polyPoints.add(pt);

      }

      routePolyline = polyPoints;



      try {

        final road = await _fetchRoadPolyline(polyPoints);

        if (road.length >= 2) {

          routePolyline = road;

        }

      } catch (_) {}



      debugPrint('[LiveTracking] _loadTripLayout: routePolyline points=${routePolyline.length}');



      // Bookings / pickup & dropoff points

      final rawBookingList = (data['bookings'] ?? data['passengers'] ?? data['trip_bookings']);

      final bookings = rawBookingList is List ? rawBookingList : <dynamic>[];

      debugPrint('[LiveTracking] _loadTripLayout: bookings=${bookings.length}');



      confirmedPassengerBookings = bookings

          .whereType<Map>()

          .map((e) => Map<String, dynamic>.from(e))

          .where((m) => (m['booking_id'] ?? m['id']) != null)

          .toList();



      if (isDriver && selectedBookingId == null && confirmedPassengerBookings.isNotEmpty) {

        final firstId = _asInt(confirmedPassengerBookings.first['booking_id'] ?? confirmedPassengerBookings.first['id']);

        selectedBookingId = firstId;

      }



      allPickupPoints = [];

      allDropoffPoints = [];

      passengerPickupPoint = null;

      passengerDropoffPoint = null;

      passengerFromStopOrder = null;

      passengerToStopOrder = null;



      LatLng? pointForStopOrder(int? stopOrder) {

        if (stopOrder == null) return null;

        for (final stop in stopsList) {

          final order = _asInt(stop['stop_order'] ?? stop['order']);

          if (order != null && order == stopOrder) {

            final lat = _stopLat(stop);

            final lng = _stopLng(stop);

            if (lat == null || lng == null) return null;

            return LatLng(lat, lng);

          }

        }

        return null;

      }



      for (final b in bookings) {

        if (b is! Map<String, dynamic>) continue;

        final bookingMap = Map<String, dynamic>.from(b);



        final fromOrder = _asInt(

          bookingMap['from_stop_order'] ??

              bookingMap['from_order'] ??

              bookingMap['from_stop'] ??

              bookingMap['pickup_stop_order'] ??

              bookingMap['pickup_order'] ??

              bookingMap['pickup_stop'],

        );

        final toOrder = _asInt(

          bookingMap['to_stop_order'] ??

              bookingMap['to_order'] ??

              bookingMap['to_stop'] ??

              bookingMap['dropoff_stop_order'] ??

              bookingMap['dropoff_order'] ??

              bookingMap['dropoff_stop'],

        );



        final pickup = pointForStopOrder(fromOrder);

        final dropoff = pointForStopOrder(toOrder);



        if (pickup != null) {

          allPickupPoints.add(pickup);

        }

        if (dropoff != null) {

          allDropoffPoints.add(dropoff);

        }



        // If this is the current passenger's booking, remember their points

        if (!isDriver && bookingId != null) {

          final id = _asInt(

            bookingMap['booking_id'] ??

                bookingMap['id'] ??

                bookingMap['booking_pk'] ??

                bookingMap['bookingId'] ??

                bookingMap['pk'],

          );

          final passengerUserId = _asInt(

            bookingMap['user_id'] ??

                bookingMap['passenger_id'] ??

                bookingMap['passenger'] ??

                bookingMap['passengerId'],

          );



          final bool isCurrentBooking = (id != null && id == bookingId) ||

              (passengerFromStopOrder == null && passengerUserId != null && passengerUserId == currentUserId);



          if (isCurrentBooking) {

            debugPrint(

              '[LiveTracking] _loadTripLayout: matched current passenger booking (bookingId=$bookingId rawId=$id passengerUserId=$passengerUserId from=$fromOrder to=$toOrder)',

            );

            passengerFromStopOrder = fromOrder;

            passengerToStopOrder = toOrder;

            if (pickup != null) {

              passengerPickupPoint = pickup;

            }

            if (dropoff != null) {

              passengerDropoffPoint = dropoff;

            }

          }

        }

      }



      onStateChanged?.call();

    } catch (_) {

      // Trip layout is best-effort; failures shouldn't break live tracking.

      debugPrint('[LiveTracking] _loadTripLayout: failed to parse layout');

    }

  }



  Future<List<LatLng>> _fetchRoadPolyline(List<LatLng> waypoints) async {

    // Keep planned route consistent with other map screens by using ORS.
    if (waypoints.length < 2) return <LatLng>[];
    try {
      final road = await RoadPolylineService.fetchRoadPolyline(waypoints);
      return road.length >= 2 ? road : <LatLng>[];
    } catch (_) {
      return <LatLng>[];
    }

  }


  void _startPollingLiveState() {

    _pollTimer?.cancel();

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {

      try {

        debugPrint('[LiveTracking] polling live state for tripId=$tripId');

        if (!isDriver && bookingId == null) {

          return;

        }

        final data = await ApiService.getLiveLocationAuthorized(

          tripId: tripId,

          role: isDriver ? 'DRIVER' : 'PASSENGER',

          userId: currentUserId,

          bookingId: isDriver ? null : bookingId,

        );

        if (data['success'] != true) {

          final status = data['status'];

          if (status == 401 || status == 403 || status == 404 || status == 410) {

            errorMessage = data['error']?.toString();

            rideStarted = false;

            stopSendingLocation();

            _pollTimer?.cancel();

            _pollTimer = null;

            onStateChanged?.call();

            return;

          }

          errorMessage = data['error']?.toString();

          onStateChanged?.call();

          return;

        }



        if (data['success'] == true) {

          if (data['trip_status'] != null) {

            tripStatus = data['trip_status']?.toString();

          }



          if (data['pickup_verified'] != null) {

            pickupVerified = data['pickup_verified'] == true;

          }



          if (data['booking_status'] != null) {

            bookingStatus = data['booking_status']?.toString();

          }

          if (data['booking_ride_status'] != null) {

            bookingRideStatus = data['booking_ride_status']?.toString();

          }



          if (!isDriver) {

            final shouldBeStarted = bookingRideStatus == 'RIDE_STARTED';

            if (rideStarted != shouldBeStarted) {

              rideStarted = shouldBeStarted;

            }

            if (rideStarted) {

              await _ensureAndStartLocation();

              await _ensureBackgroundTrackingPermissions();

              await BackgroundLiveTrackingService.setSendEnabled(true);

              await BackgroundLiveTrackingService.start();

            }

          }



          if (!isDriver) {

            if (bookingRideStatus == 'DROPPED_OFF' || bookingRideStatus == 'DROPPED_EARLY') {

              rideStarted = false;

              stopSendingLocation();

              _pollTimer?.cancel();

              _pollTimer = null;

            }

          }



          if (tripStatus == 'CANCELLED') {

            rideStarted = false;

            stopSendingLocation();

            _pollTimer?.cancel();

            _pollTimer = null;

            onStateChanged?.call();

            return;

          }



          if (tripStatus == 'COMPLETED') {

            // Trip ended by driver. Do not force the passenger booking into a

            // "reached" state; passenger can still explicitly mark drop-off.

            if (isDriver) {
              // Driver is done once the trip is completed.
              rideStarted = false;
              stopSendingLocation();
              _pollTimer?.cancel();
              _pollTimer = null;
              onStateChanged?.call();
              return;
            }

            // Passenger should keep seeing the live map until they explicitly
            // mark drop-off. Do not stop polling just because the driver ended.
            onStateChanged?.call();

          }



          if (!isDriver && bookingStatus == 'CANCELLED') {

            rideStarted = false;

            stopSendingLocation();

            _pollTimer?.cancel();

            _pollTimer = null;

            onStateChanged?.call();

            return;

          }



          if (isDriver && tripStatus == 'IN_PROGRESS') {

            rideStarted = true;

            await _ensureAndStartLocation();

            await _ensureBackgroundTrackingPermissions();

            await BackgroundLiveTrackingService.setSendEnabled(true);

            await BackgroundLiveTrackingService.start();

          }

          final state = data['live_state'] as Map<String, dynamic>? ?? {};

          final driver = state['driver'] as Map<String, dynamic>?;

          final list = state['passengers'] as List<dynamic>? ?? [];

          final rawPath = state['driver_path'];

          final runtime = data['runtime'] as Map<String, dynamic>?;

          final driverMeta = data['driver_meta'] as Map<String, dynamic>?;

          debugPrint('[LiveTracking] poll: driver=$driver passengers=${list.length}');



          if (driver != null &&

              driver['lat'] != null &&

              driver['lng'] != null) {

            driverPosition = LatLng(

              (driver['lat'] as num).toDouble(),

              (driver['lng'] as num).toDouble(),

            );

          }



          try {

            final poly = <LatLng>[];

            if (rawPath is List) {

              for (final p in rawPath) {

                if (p is! Map) continue;

                final lat = _asDouble(p['lat']);

                final lng = _asDouble(p['lng']);

                if (lat == null || lng == null) continue;

                poly.add(LatLng(lat, lng));

              }

            }

            driverPathPolyline = poly;

          } catch (_) {

            driverPathPolyline = [];

          }



          try {

            driverSpeedKph = _asDouble(runtime?['driver_speed_kph']);

            driverEtaSecondsToFinal = _asIntSafe(runtime?['driver_eta_seconds_to_final']);

            passengerEtaSecondsToDropoff = _asIntSafe(runtime?['passenger_eta_seconds_to_dropoff']);

          } catch (_) {

            driverSpeedKph = null;

            driverEtaSecondsToFinal = null;

            passengerEtaSecondsToDropoff = null;

          }



          try {

            isDriverDeviating = (driverMeta?['is_deviating'] == true);

            driverDeviationMeters = _asDouble(driverMeta?['deviation_meters']);

            driverSignalLost = (driverMeta?['signal_lost'] == true);

            driverLastSeenSeconds = _asIntSafe(driverMeta?['last_seen_seconds']);

          } catch (_) {

            isDriverDeviating = null;

            driverDeviationMeters = null;

            driverSignalLost = false;

            driverLastSeenSeconds = null;

          }



          passengers = list

              .whereType<Map<String, dynamic>>()

              .map((e) => Map<String, dynamic>.from(e))

              .toList();



          onStateChanged?.call();

        }

      } catch (e) {

        errorMessage = e.toString();

        debugPrint('[LiveTracking] poll error: $e');

        onStateChanged?.call();

      }

    });

  }



  void stopSendingLocation() {

    _sendTimer?.cancel();

    _sendTimer = null;

    _positionSubscription?.cancel();

    _positionSubscription = null;

    _latestPosition = null;

    _locationStarted = false;



    () async {

      try {

        await BackgroundLiveTrackingService.setSendEnabled(false);

        await BackgroundLiveTrackingService.stop();

      } catch (_) {}

    }();

  }



  void dispose() {

    _pollTimer?.cancel();

    _pollTimer = null;

    stopSendingLocation();

  }



  Future<void> generatePickupCode() async {

    final targetBookingId = bookingId ?? selectedBookingId;

    if (!isDriver || targetBookingId == null) {

      debugPrint('[LiveTracking] generatePickupCode called in invalid context (isDriver=$isDriver, bookingId=$bookingId)');

      return;

    }



    try {

      isGeneratingCode = true;

      errorMessage = null;

      onStateChanged?.call();



      Position? pos;

      try {

        pos = await Geolocator.getLastKnownPosition();

      } catch (_) {}

      if (pos == null) {

        try {

          await _ensureLocationPermission();

          pos = await Geolocator.getCurrentPosition(

            locationSettings: const LocationSettings(

              accuracy: LocationAccuracy.high,

            ),

          ).timeout(const Duration(seconds: 8));

        } catch (_) {}

      }



      debugPrint('[LiveTracking] generatePickupCode: tripId=$tripId bookingId=$bookingId driverId=$currentUserId lat=${pos?.latitude} lng=${pos?.longitude}');



      final res = await ApiService.generatePickupCode(

        tripId: tripId,

        bookingId: targetBookingId,

        driverId: currentUserId,

        driverLat: pos?.latitude,

        driverLng: pos?.longitude,

      );



      if (res['success'] == true) {

        debugPrint('[LiveTracking] generatePickupCode success: $res');

        activePickupCode = res['code']?.toString();

        pickupMaxAttempts = res['max_attempts'] is int ? res['max_attempts'] as int : null;

        pickupRemainingAttempts = pickupMaxAttempts;

        final expires = res['expires_at']?.toString();

        if (expires != null) {

          try {

            pickupExpiresAt = DateTime.parse(expires);

          } catch (_) {

            pickupExpiresAt = null;

          }

        }

      } else {

        errorMessage = res['error']?.toString() ?? 'Failed to generate pickup code';

        debugPrint('[LiveTracking] generatePickupCode error: $errorMessage');

      }

    } catch (e) {

      errorMessage = e.toString();

    } finally {

      isGeneratingCode = false;

      onStateChanged?.call();

    }

  }



  Future<void> verifyPickupCode(String code) async {

    if (isDriver || bookingId == null) {

      debugPrint('[LiveTracking] verifyPickupCode called in invalid context (isDriver=$isDriver, bookingId=$bookingId)');

      return;

    }



    try {

      isVerifyingCode = true;

      errorMessage = null;

      onStateChanged?.call();



      Position? pos;

      try {

        pos = await Geolocator.getLastKnownPosition();

      } catch (_) {}



      final res = await ApiService.verifyPickupCode(

        bookingId: bookingId!,

        passengerId: currentUserId,

        code: code,

        passengerLat: pos?.latitude,

        passengerLng: pos?.longitude,

      );



      if (res['success'] == true) {

        debugPrint('[LiveTracking] verifyPickupCode success: $res');

        pickupVerified = true;

      } else {

        errorMessage = res['error']?.toString() ?? 'Pickup code verification failed';

        debugPrint('[LiveTracking] verifyPickupCode error: $errorMessage remaining=${res['remaining_attempts']}');

        if (res['remaining_attempts'] is int) {

          pickupRemainingAttempts = res['remaining_attempts'] as int;

        }

      }

    } catch (e) {

      errorMessage = e.toString();

    } finally {

      isVerifyingCode = false;

      onStateChanged?.call();

    }

  }

}

