import 'dart:async';

import 'dart:convert';

import 'dart:ui';



import 'package:flutter/foundation.dart';

import 'package:flutter_background_service/flutter_background_service.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:geolocator/geolocator.dart';

import 'package:latlong2/latlong.dart';

import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';



import '../constants.dart';

import 'offline_location_queue.dart';
import '../utils/map_util.dart';



class BackgroundLiveTrackingService {

  static const String persistedSessionKey = 'active_live_tracking_session_v1';

  static const String sendEnabledKey = 'active_live_tracking_send_enabled_v1';



  static const String notificationChannelId = 'live_tracking';

  static const int notificationId = 9922;



  static Future<void> initialize() async {

    final service = FlutterBackgroundService();



    const channel = AndroidNotificationChannel(

      notificationChannelId,

      'Live Tracking',

      description: 'This channel is used for live ride tracking.',

      importance: Importance.low,

    );



    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =

        FlutterLocalNotificationsPlugin();



    await flutterLocalNotificationsPlugin

        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()

        ?.createNotificationChannel(channel);



    await service.configure(

      androidConfiguration: AndroidConfiguration(

        onStart: _onStart,

        autoStart: false,

        isForegroundMode: true,

        notificationChannelId: notificationChannelId,

        initialNotificationTitle: 'Live Tracking',

        initialNotificationContent: 'Starting...',

        foregroundServiceNotificationId: notificationId,

      ),

      iosConfiguration: IosConfiguration(

        autoStart: false,

        onForeground: _onStart,

      ),

    );

  }



  static Future<void> start() async {

    final service = FlutterBackgroundService();

    final running = await service.isRunning();

    if (!running) {

      await service.startService();

    } else {

      service.invoke('refresh');

    }

  }



  static Future<void> stop() async {

    final service = FlutterBackgroundService();

    final running = await service.isRunning();

    if (!running) return;

    service.invoke('stopService');

  }



  static Future<void> setSendEnabled(bool enabled) async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(sendEnabledKey, enabled);

  }



  static Future<void> clearSendEnabled() async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(sendEnabledKey);

  }

}



@pragma('vm:entry-point')

void _onStart(ServiceInstance service) async {

  DartPluginRegistrant.ensureInitialized();



  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =

      FlutterLocalNotificationsPlugin();



  const InitializationSettings initSettings = InitializationSettings(

    android: AndroidInitializationSettings('ic_stat_lets_go'),

  );



  try {

    await flutterLocalNotificationsPlugin.initialize(initSettings);

  } catch (_) {}



  StreamSubscription<Position>? positionSubscription;

  Timer? timer;

  Position? latest;

  LatLng? lastSentPoint;



  Future<Map<String, dynamic>?> readSession() async {

    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(BackgroundLiveTrackingService.persistedSessionKey);

    if (raw == null || raw.isEmpty) return null;

    try {

      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {

        return Map<String, dynamic>.from(decoded);

      }

    } catch (_) {}

    return null;

  }



  Future<bool> isSendEnabled() async {

    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(BackgroundLiveTrackingService.sendEnabledKey) ?? false;

  }



  Future<void> disableSendingAndStop() async {

    try {

      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(BackgroundLiveTrackingService.sendEnabledKey, false);

      await prefs.remove(BackgroundLiveTrackingService.persistedSessionKey);

    } catch (_) {}

    service.stopSelf();

  }



  Future<void> startStreamIfNeeded() async {

    if (positionSubscription != null) return;



    final perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {

      return;

    }



    const settings = LocationSettings(

      accuracy: LocationAccuracy.high,

      distanceFilter: 0,

    );



    positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(

      (pos) {

        latest = pos;

      },

      onError: (_) {},

    );

  }



  Future<void> sendOnce() async {

    final session = await readSession();

    if (session == null) {

      await disableSendingAndStop();

      return;

    }



    final enabled = await isSendEnabled();

    if (!enabled) {

      return;

    }



    final tripId = session['trip_id']?.toString();

    final userId = session['user_id'];

    final isDriver = session['is_driver'];



    if (tripId == null || tripId.isEmpty || userId is! int || isDriver is! bool) {

      return;

    }



    final bookingIdRaw = session['booking_id'];

    int? bookingId;

    if (bookingIdRaw is int) {

      bookingId = bookingIdRaw;

    } else if (bookingIdRaw is num) {

      bookingId = bookingIdRaw.toInt();

    } else if (bookingIdRaw is String) {

      bookingId = int.tryParse(bookingIdRaw);

    }



    final pos = latest;

    if (pos == null) {

      return;

    }



    final endpoint = '$url/lets_go/trips/$tripId/location/update/';



    final role = isDriver ? 'DRIVER' : 'PASSENGER';

    final current = LatLng(pos.latitude, pos.longitude);
    final prev = lastSentPoint;

    final toSend = <LatLng>[];
    if (prev != null) {
      toSend.addAll(MapUtil.densifyBetween(prev, current, maxStepMeters: 25));
    } else {
      toSend.add(current);
    }



    Future<void> flushQueue() async {
      try {

        final batch = await OfflineLocationQueue.peekBatch(

          tripId: tripId,

          userId: userId,

          role: role,

          bookingId: isDriver ? null : bookingId,

          limit: 10,

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



          final current = LatLng(lat, lng);
          final prev = lastSentPoint;

          final points = <LatLng>[];
          if (prev != null) {
            points.addAll(MapUtil.densifyBetween(prev, current, maxStepMeters: 25));
          } else {
            points.add(current);
          }



          bool ok = true;
          for (final p in points) {
            final replayBody = <String, dynamic>{
              'user_id': userId,
              'role': role,
              'lat': p.latitude,
              'lng': p.longitude,
              if (!isDriver && bookingId != null) 'booking_id': bookingId,
              if (speed != null) 'speed': speed,
            };

            final resp = await http
                .post(
                  Uri.parse(endpoint),
                  headers: const {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                  },
                  body: jsonEncode(replayBody),
                )
                .timeout(const Duration(seconds: 12));

            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              lastSentPoint = p;
            } else {
              ok = false;
              break;
            }
          }



          if (ok) {
            sent += 1;
          } else {
            break;
          }

        }



        if (sent > 0) {

          await OfflineLocationQueue.dropBatch(

            tripId: tripId,

            userId: userId,

            role: role,

            bookingId: isDriver ? null : bookingId,

            count: sent,

          );

        }

      } catch (_) {

        // keep queued points

      }

    }



    http.Response? resp;

    try {

      await flushQueue();

      for (final p in toSend) {
        final body = <String, dynamic>{
          'user_id': userId,
          'role': role,
          'lat': p.latitude,
          'lng': p.longitude,
          if (!isDriver && bookingId != null) 'booking_id': bookingId,
          if (pos.speed.isFinite) 'speed': pos.speed,
        };

        resp = await http
            .post(
              Uri.parse(endpoint),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 12));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          lastSentPoint = p;
        } else {
          break;
        }
      }

      final r = resp;
      if (r == null) return;

      // If backend accepted but ignored (trip ended / passenger not on board), stop.
      if (r.statusCode >= 200 && r.statusCode < 300) {
        try {
          final decoded = jsonDecode(r.body);
          if (decoded is Map && decoded['ignored'] == true) {
            await OfflineLocationQueue.clearAll();
            await disableSendingAndStop();
            return;
          }
        } catch (_) {}
      }

      // Stop tracking if backend says ride ended / not authorized.
      if (r.statusCode == 400 || r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 404 || r.statusCode == 410) {
        await OfflineLocationQueue.clearAll();
        await disableSendingAndStop();
        return;
      }

      if (r.statusCode < 200 || r.statusCode >= 300) {
        await OfflineLocationQueue.enqueue(
          tripId: tripId,
          userId: userId,
          role: isDriver ? 'DRIVER' : 'PASSENGER',
          bookingId: isDriver ? null : bookingId,
          lat: pos.latitude,
          lng: pos.longitude,
          speed: pos.speed.isFinite ? pos.speed : null,
        );
        return;
      }

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          await flutterLocalNotificationsPlugin.show(
            BackgroundLiveTrackingService.notificationId,
            'Live Tracking',
            'Sending location…',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                BackgroundLiveTrackingService.notificationChannelId,
                'Live Tracking',
                icon: 'ic_stat_lets_go',
                ongoing: true,
                priority: Priority.low,
                importance: Importance.low,
              ),
            ),
          );
        }
      }

    } catch (e) {

      try {

        await OfflineLocationQueue.enqueue(

          tripId: tripId,

          userId: userId,

          role: isDriver ? 'DRIVER' : 'PASSENGER',

          bookingId: isDriver ? null : bookingId,

          lat: pos.latitude,

          lng: pos.longitude,

          speed: pos.speed.isFinite ? pos.speed : null,

        );

      } catch (_) {}



      if (kDebugMode) {

        debugPrint('[BackgroundLiveTracking] send error: $e');

      }

    }



    final s = resp;

    if (s != null) {

      if (s.statusCode == 400 ||

          s.statusCode == 401 ||

          s.statusCode == 403 ||

          s.statusCode == 404 ||

          s.statusCode == 410) {

        await OfflineLocationQueue.clearAll();

        await disableSendingAndStop();

        return;

      }

    }

  }



  service.on('stopService').listen((_) async {

    timer?.cancel();

    timer = null;

    await positionSubscription?.cancel();

    positionSubscription = null;

    await disableSendingAndStop();

  });



  service.on('refresh').listen((_) async {

    await sendOnce();

  });



  if (service is AndroidServiceInstance) {

    service.setAsForegroundService();

  }



  await startStreamIfNeeded();

  timer = Timer.periodic(const Duration(seconds: 3), (_) async {

    await startStreamIfNeeded();

    await sendOnce();

  });

}

