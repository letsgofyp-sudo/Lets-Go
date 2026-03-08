import 'dart:convert';



import 'package:shared_preferences/shared_preferences.dart';



import '../controllers/post_bookings_controller/driver_live_tracking_controller.dart';

import '../controllers/post_bookings_controller/live_tracking_controller.dart';

import '../controllers/post_bookings_controller/passenger_live_tracking_controller.dart';

import 'background_live_tracking_service.dart';

import 'offline_location_queue.dart';



class LiveTrackingSessionManager {

  LiveTrackingSessionManager._();



  static final LiveTrackingSessionManager instance = LiveTrackingSessionManager._();



  static const String _prefsKey = 'active_live_tracking_session_v1';



  LiveTrackingController? _controller;

  Map<String, dynamic>? _session;



  LiveTrackingController? get controller => _controller;



  bool get hasActiveSession => _controller != null && _session != null;



  bool _isSameSession(Map<String, dynamic> a, Map<String, dynamic> b) {

    return a['trip_id'] == b['trip_id'] &&

        a['user_id'] == b['user_id'] &&

        a['is_driver'] == b['is_driver'] &&

        a['booking_id'] == b['booking_id'];

  }



  Future<Map<String, dynamic>?> readPersistedSession() async {

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.isEmpty) return null;

    try {

      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {

        return Map<String, dynamic>.from(decoded);

      }

    } catch (_) {}

    return null;

  }



  Future<void> _persistSession(Map<String, dynamic>? session) async {

    final prefs = await SharedPreferences.getInstance();

    if (session == null) {

      await prefs.remove(_prefsKey);

      return;

    }

    await prefs.setString(_prefsKey, jsonEncode(session));

  }



  Future<void> stopSession({bool clearPersisted = true}) async {

    _controller?.dispose();

    _controller = null;

    _session = null;



    try {

      await BackgroundLiveTrackingService.setSendEnabled(false);

      await BackgroundLiveTrackingService.stop();

    } catch (_) {}



    try {

      await OfflineLocationQueue.clearAll();

    } catch (_) {}



    if (clearPersisted) {

      await _persistSession(null);

    }

  }



  Future<LiveTrackingController> getOrStartSession({

    required String tripId,

    required int currentUserId,

    required bool isDriver,

    int? bookingId,

  }) async {

    final desired = <String, dynamic>{

      'trip_id': tripId,

      'user_id': currentUserId,

      'is_driver': isDriver,

      'booking_id': bookingId,

    };



    if (_controller != null && _session != null && _isSameSession(_session!, desired)) {

      return _controller!;

    }



    await stopSession(clearPersisted: false);



    _session = desired;

    if (isDriver) {

      _controller = DriverLiveTrackingController(

        tripId: tripId,

        driverId: currentUserId,

      );

    } else {

      if (bookingId == null) {

        _controller = LiveTrackingController(

          tripId: tripId,

          currentUserId: currentUserId,

          bookingId: bookingId,

          isDriver: isDriver,

        );

      } else {

        _controller = PassengerLiveTrackingController(

          tripId: tripId,

          passengerId: currentUserId,

          bookingId: bookingId,

        );

      }

    }



    await _persistSession(desired);

    _controller!.init();



    return _controller!;

  }



  Future<LiveTrackingController?> restorePersistedSession() async {

    final persisted = await readPersistedSession();

    if (persisted == null) return null;



    final tripId = persisted['trip_id']?.toString();

    final userId = persisted['user_id'];

    final isDriver = persisted['is_driver'];



    if (tripId == null || userId is! int || isDriver is! bool) {

      return null;

    }



    final bookingId = persisted['booking_id'];



    return getOrStartSession(

      tripId: tripId,

      currentUserId: userId,

      isDriver: isDriver,

      bookingId: bookingId is int ? bookingId : null,

    );

  }

}

