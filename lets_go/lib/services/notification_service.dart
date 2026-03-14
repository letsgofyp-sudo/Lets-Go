import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import '../constants.dart';

import '../screens/chat_screens/driver_individual_chat_screen.dart';
import '../screens/chat_screens/passenger_chat_screen.dart';
import '../screens/post_booking_screens/driver_live_tracking_screen.dart';
import '../screens/post_booking_screens/driver_payment_confirmation_screen.dart';
import '../screens/post_booking_screens/passenger_live_tracking_screen.dart';
import '../screens/post_booking_screens/passenger_payment_screen.dart';
import '../screens/ride_booking_screens/driver_requests_screen.dart';
import '../screens/ride_booking_screens/negotiation_details_screen.dart';
import '../screens/support_chat_screen.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/live_tracking_session_manager.dart';
import '../utils/auth_session.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  DartPluginRegistrant.ensureInitialized();
  // ignore: avoid_print
  debugPrint('[NotificationService] Background notification response: actionId=${response.actionId} input=${response.input} payloadLen=${response.payload?.length ?? 0}');
  NotificationService.handleNotificationResponse(response);
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.handleFcmBackgroundMessage(message);
}

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _androidChannelId = 'ride_requests_v3';
  static const bool _debugLogs = true;

  static void _dbg(String message) {
    if (!_debugLogs) return;
    debugPrint('[NotificationService][DBG] $message');
  }

  static Uint8List? _cachedAppLogoBytes;
  static Uint8List? _cachedAdminIconBytes;
  static final Map<String, Uint8List> _cachedRemoteIconBytes = <String, Uint8List>{};
  static bool _localNotificationsInitialized = false;

  static dynamic _navigatorKey;
  static String? _pendingNavigationPayload;

  static String _clip(String s, int max) {
    if (s.length <= max) return s;
    return s.substring(0, max);
  }

  static void setNavigatorKey(dynamic key) {
    _navigatorKey = key;
    final pending = _pendingNavigationPayload;
    if (pending != null) {
      _pendingNavigationPayload = null;
      _handleNotificationTap(pending);
    }
  }

  static Future<void> trySyncGuestFcmTokenNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString('fcm_token') ?? '').trim();
      if (token.isEmpty) return;
      await _syncGuestFcmTokenIfAny(token);
    } catch (_) {}
  }

  // Initialize the notification service
  static Future<void> initialize() async {
    _dbg('initialize() start');
    // Request notification permissions
    // ignore: avoid_print
    debugPrint('[NotificationService] Requesting notification permissions...');
    await _requestPermissions();
    // ignore: avoid_print
    debugPrint('[NotificationService] Permissions request completed');
    
    // Initialize local notifications
    _dbg('initialize() -> _initializeLocalNotifications()');
    await _initializeLocalNotifications();
    
    // Ensure FCM auto-init is enabled and get/save FCM token
    _dbg('initialize() -> _getAndSaveFcmToken()');
    await _getAndSaveFcmToken();
    
    // Set up foreground message handler
    _dbg('initialize() -> _setupForegroundMessageHandler()');
    _setupForegroundMessageHandler();
    
    // Set up background message handler
    _dbg('initialize() -> FirebaseMessaging.onBackgroundMessage(...)');
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _dbg('onMessageOpenedApp: dataKeys=${message.data.keys.toList()}');
      _navigateFromData(message.data);
    });

    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _dbg('getInitialMessage(): dataKeys=${initial.data.keys.toList()}');
      _navigateFromData(initial.data);
    } else {
      _dbg('getInitialMessage(): null');
    }

    _dbg('initialize() done');
  }

  static Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _initializeLocalNotifications();
      final androidDetails = AndroidNotificationDetails(
        _androidChannelId,
        'Ride Request Notifications',
        channelDescription: 'This channel is used for ride request notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        showWhen: false,
        icon: 'ic_stat_lets_go',
        largeIcon: const DrawableResourceAndroidBitmap('ic_stat_lets_go'),
      );
      final details = NotificationDetails(android: androidDetails);
      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload == null ? null : jsonEncode(payload),
      );
    } catch (e) {
      _dbg('showLocalNotification failed: $e');
    }
  }

  static Future<void> _requestPermissions() async {
    _dbg('_requestPermissions() start');
    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    // ignore: avoid_print
    debugPrint('[NotificationService] Permission settings: authorizationStatus=${settings.authorizationStatus}');
    _dbg('_requestPermissions() done: status=${settings.authorizationStatus}');
  }

  static Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) {
      _dbg('_initializeLocalNotifications(): already initialized');
      return;
    }

    _dbg('_initializeLocalNotifications() start');
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_stat_lets_go');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _dbg('onDidReceiveNotificationResponse: actionId=${response.actionId} inputLen=${response.input?.length ?? 0} payloadLen=${response.payload?.length ?? 0}');
        handleNotificationResponse(response);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    try {
      final android = _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      try {
        _dbg('_initializeLocalNotifications(): delete old channels (if any)');
        await android?.deleteNotificationChannel('ride_requests');
        await android?.deleteNotificationChannel('ride_requests_v2');
        await android?.deleteNotificationChannel('ride_requests_v3');
        _dbg('_initializeLocalNotifications(): delete old channels done');
      } catch (e) {
        _dbg('_initializeLocalNotifications(): deleteNotificationChannel failed: $e');
      }
      _dbg('_initializeLocalNotifications(): createNotificationChannel id=$_androidChannelId');
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          _androidChannelId,
          'Ride Request Notifications',
          description: 'This channel is used for ride request notifications',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      _dbg('_initializeLocalNotifications(): createNotificationChannel done');
    } catch (_) {}

    _localNotificationsInitialized = true;
    _dbg('_initializeLocalNotifications() done');
  }

  static Future<AndroidBitmap<Object>?> _getAppLogoLargeIcon() async {
    _dbg('_getAppLogoLargeIcon() start');
    try {
      final cached = _cachedAppLogoBytes;
      if (cached != null && cached.isNotEmpty) {
        _dbg('_getAppLogoLargeIcon(): using cached bytes len=${cached.length}');
        return ByteArrayAndroidBitmap(cached);
      }

      const candidates = <String>[
        'assets/images/ride-sharing-logo-black-and-white.png',
        'assets/images/app_logo.png',
      ];

      Uint8List? out;
      for (final path in candidates) {
        try {
          final data = await rootBundle.load(path);
          final bytes = await _toCircularPngBytes(data.buffer.asUint8List());
          if (bytes.isEmpty) continue;
          out = bytes;
          _dbg('_getAppLogoLargeIcon(): loaded $path len=${bytes.length}');
          break;
        } catch (_) {}
      }

      if (out == null || out.isEmpty) {
        _dbg('_getAppLogoLargeIcon(): asset bytes empty');
        return null;
      }

      _cachedAppLogoBytes = out;
      return ByteArrayAndroidBitmap(out);
    } catch (e) {
      _dbg('_getAppLogoLargeIcon(): failed: $e');
      return null;
    }
  }

  static Future<Uint8List> _toCircularPngBytes(Uint8List bytes) async {
    try {
      if (bytes.isEmpty) return bytes;

      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final minDim = image.width < image.height ? image.width : image.height;
      final left = ((image.width - minDim) / 2).toDouble();
      final top = ((image.height - minDim) / 2).toDouble();
      final src = Rect.fromLTWH(left, top, minDim.toDouble(), minDim.toDouble());

      const size = 256;
      final dst = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      canvas.clipPath(Path()..addOval(dst));
      canvas.drawImageRect(image, src, dst, paint);

      final picture = recorder.endRecording();
      final outImage = await picture.toImage(size, size);
      final byteData = await outImage.toByteData(format: ImageByteFormat.png);
      final outBytes = byteData?.buffer.asUint8List();
      if (outBytes == null || outBytes.isEmpty) return bytes;
      return outBytes;
    } catch (e) {
      _dbg('_toCircularPngBytes(): failed: $e');
      return bytes;
    }
  }

  static Future<AndroidBitmap<Object>?> _getAdminSupportLargeIcon() async {
    try {
      final cached = _cachedAdminIconBytes;
      if (cached != null && cached.isNotEmpty) {
        return ByteArrayAndroidBitmap(cached);
      }

      const candidates = <String>[
        'assets/images/admin_support.png',
        'assets/images/admin_icon.png',
        'assets/images/support_icon.png',
      ];

      for (final path in candidates) {
        try {
          final data = await rootBundle.load(path);
          final bytes = await _toCircularPngBytes(data.buffer.asUint8List());
          if (bytes.isEmpty) continue;
          _cachedAdminIconBytes = bytes;
          _dbg('_getAdminSupportLargeIcon(): loaded $path len=${bytes.length}');
          return ByteArrayAndroidBitmap(bytes);
        } catch (_) {}
      }
    } catch (e) {
      _dbg('_getAdminSupportLargeIcon(): failed: $e');
    }
    return null;
  }

  static Future<AndroidBitmap<Object>?> _getRemoteLargeIcon(String url) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return null;

    final cached = _cachedRemoteIconBytes[normalized];
    if (cached != null && cached.isNotEmpty) {
      _dbg('_getRemoteLargeIcon(): cache hit url=$normalized len=${cached.length}');
      return ByteArrayAndroidBitmap(cached);
    }

    try {
      final resp = await http.get(Uri.parse(normalized)).timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final bytes = await _toCircularPngBytes(Uint8List.fromList(resp.bodyBytes));
        if (bytes.isNotEmpty) {
          _cachedRemoteIconBytes[normalized] = bytes;
          _dbg('_getRemoteLargeIcon(): downloaded ok url=$normalized len=${bytes.length}');
          return ByteArrayAndroidBitmap(bytes);
        }
      }
      _dbg('_getRemoteLargeIcon(): http status=${resp.statusCode} url=$normalized');
    } catch (e) {
      _dbg('_getRemoteLargeIcon(): failed url=$normalized err=$e');
    }

    return null;
  }

  static Future<AndroidBitmap<Object>?> _getLargeIconForData(
    Map<String, dynamic> data,
    String type,
  ) async {
    final typeNorm = type.trim().toLowerCase();
    final senderType = (data['sender_type'] ?? data['initiator'] ?? data['source'] ?? '').toString().trim().toLowerCase();
    final isAdminInitiated = senderType == 'admin' || senderType == 'administration'
        || typeNorm == 'support_admin' || typeNorm == 'user_status_updated' || typeNorm == 'change_request_reviewed';
    final isSystemInitiated = senderType == 'system' || senderType == 'bot'
        || typeNorm == 'support_bot' || typeNorm == 'notification_summary';

    final senderPhotoUrl = (data['sender_photo_url'] ?? '').toString();
    if (senderPhotoUrl.isNotEmpty) {
      final remote = await _getRemoteLargeIcon(senderPhotoUrl);
      if (remote != null) return remote;
    }

    if (isAdminInitiated) {
      final admin = await _getAdminSupportLargeIcon();
      return admin ?? _getAppLogoLargeIcon();
    }

    if (isSystemInitiated) {
      return _getAppLogoLargeIcon();
    }

    // For admin/system notifications, do NOT fall back to generic photo_url because it can
    // be the receiver's profile photo depending on sender implementation.
    if (typeNorm != 'support_admin' && typeNorm != 'support_bot') {
      final photoUrl = (data['photo_url'] ?? '').toString();
      if (photoUrl.isNotEmpty) {
        final remote = await _getRemoteLargeIcon(photoUrl);
        if (remote != null) return remote;
      }
    }

    return _getAppLogoLargeIcon();
  }

  static Future<void> _syncGuestFcmTokenIfAny(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gid = int.tryParse((prefs.getString('guest_user_id') ?? '').toString()) ?? 0;
      if (gid <= 0) return;
      await ApiService.createGuestSupportUser(
        existingGuestUserId: gid,
        fcmToken: token,
      );
    } catch (_) {}
  }

  static Future<void> _getAndSaveFcmToken() async {
    try {
      _dbg('_getAndSaveFcmToken() start');
      // Make sure FCM is allowed to auto-initialize
      await _fcm.setAutoInitEnabled(true);
      _dbg('_getAndSaveFcmToken(): setAutoInitEnabled(true)');

      // Get the token each time the app loads, with a couple of retries in case
      // Firebase is still initializing or network is briefly unavailable.
      String? token = await _fcm.getToken();
      // DEBUG: log initial token fetch
      // ignore: avoid_print
      debugPrint('[NotificationService] FCM getToken initial: $token');
      if (token == null) {
        await Future.delayed(const Duration(seconds: 2));
        token = await _fcm.getToken();
        // ignore: avoid_print
        debugPrint('[NotificationService] FCM getToken retry#1: $token');
      }
      if (token == null) {
        await Future.delayed(const Duration(seconds: 3));
        token = await _fcm.getToken();
        // ignore: avoid_print
        debugPrint('[NotificationService] FCM getToken retry#2: $token');
      }

      if (token != null) {
        // Save to local storage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
        // ignore: avoid_print
        debugPrint('[NotificationService] Saved FCM token to SharedPreferences (len=${token.length})');
        _dbg('_getAndSaveFcmToken(): saved token len=${token.length}');

        // Best-effort sync to backend so Django/Supabase always have the latest token
        // (especially important after reinstall where old tokens become UNREGISTERED).
        await _syncFcmTokenToBackend(token);
        await _syncGuestFcmTokenIfAny(token);
      } else {
        // ignore: avoid_print
        debugPrint('[NotificationService] FCM token is STILL null after retries; not saving');
        _dbg('_getAndSaveFcmToken(): token null after retries');
      }
      
      // Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) async {
        _dbg('onTokenRefresh: newTokenLen=${newToken.length}');
        // Cache new token locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', newToken);
        // ignore: avoid_print
        debugPrint('[NotificationService] onTokenRefresh: updated token in SharedPreferences (len=${newToken.length})');

        try {
          await _syncFcmTokenToBackend(newToken);
        } catch (e) {
          _dbg('onTokenRefresh: _syncFcmTokenToBackend failed: $e');
        }

        try {
          await _syncGuestFcmTokenIfAny(newToken);
        } catch (_) {}
      });

      _dbg('_getAndSaveFcmToken() done');
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      _dbg('_getAndSaveFcmToken() exception: $e');
    }
  }

  static Future<void> _syncFcmTokenToBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userIdStr = prefs.getString('logged_in_user_id');
      if (userIdStr == null || userIdStr.isEmpty) {
        _dbg('_syncFcmTokenToBackend: no logged_in_user_id; skip');
        return;
      }

      final userId = int.tryParse(userIdStr) ?? userIdStr;
      final uri = Uri.parse('$url/lets_go/update_fcm_token/');
      final payload = jsonEncode({'user_id': userId, 'fcm_token': token});

      _dbg('_syncFcmTokenToBackend: POST $uri userId=$userIdStr tokenLen=${token.length}');
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: payload)
          .timeout(const Duration(seconds: 8));
      _dbg('_syncFcmTokenToBackend: status=${resp.statusCode} bodyLen=${resp.body.length}');
    } catch (e) {
      _dbg('_syncFcmTokenToBackend failed: $e');
    }
  }

  static void _setupForegroundMessageHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // ignore: avoid_print
      debugPrint('[NotificationService] FCM foreground message received: dataKeys=${message.data.keys.toList()} hasNotification=${message.notification != null}');
      _dbg('onMessage: messageId=${message.messageId} dataKeys=${message.data.keys.toList()}');
      _showNotification(message);
    });
  }

  @pragma('vm:entry-point')
  static Future<void> handleFcmBackgroundMessage(RemoteMessage message) async {
    DartPluginRegistrant.ensureInitialized();
    // ignore: avoid_print
    debugPrint('[NotificationService] FCM background message received: dataKeys=${message.data.keys.toList()} hasNotification=${message.notification != null}');
    _dbg('onBackgroundMessage: messageId=${message.messageId} dataKeys=${message.data.keys.toList()}');
    try {
      await Firebase.initializeApp();
      _dbg('onBackgroundMessage: Firebase.initializeApp() ok');
    } catch (_) {}
    try {
      await _initializeLocalNotifications();
      _dbg('onBackgroundMessage: _initializeLocalNotifications() ok');
      await _showNotification(message);
    } catch (e) {
      _dbg('onBackgroundMessage: failed to show local notification: $e');
    }
  }

  static Future<void> _showNotification(RemoteMessage message) async {
    try {
      await _initializeLocalNotifications();

      final data = message.data;
      final typeRaw = (data['type'] ?? data['notification_type'] ?? '').toString();
      final type = typeRaw.trim().toLowerCase();

      String title = (data['title'] ?? '').toString().trim();
      String body = (data['body'] ?? '').toString().trim();

      final senderName = (data['sender_name'] ?? data['name'] ?? '').toString().trim();
      final messageText = (data['message_text'] ?? '').toString().trim();

      // Prefer Firebase notification fields if present.
      final nTitle = (message.notification?.title ?? '').toString().trim();
      final nBody = (message.notification?.body ?? '').toString().trim();
      if (nTitle.isNotEmpty) title = nTitle;
      if (nBody.isNotEmpty) body = nBody;

      // Support: make titles deterministic
      if (type == 'support_admin') {
        title = senderName.isNotEmpty ? senderName : (title.isNotEmpty ? title : 'Admin Support');
        if (messageText.isNotEmpty) body = _clip(messageText, 180);
      }
      if (type == 'support_bot') {
        title = title.isNotEmpty ? title : 'Support Bot';
        if (messageText.isNotEmpty) body = _clip(messageText, 180);
      }

      if (title.isEmpty) title = 'Lets Go';
      if (body.isEmpty) body = 'You have a new notification';

      final actions = _buildAndroidActionsForData(data);
      final largeIcon = await _getLargeIconForData(data, type);

      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        _androidChannelId,
        'Ride Request Notifications',
        channelDescription: 'This channel is used for ride request notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        showWhen: false,
        icon: 'ic_stat_lets_go',
        largeIcon: largeIcon ?? const DrawableResourceAndroidBitmap('ic_stat_lets_go'),
        actions: actions,
      );

      final platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

      await _flutterLocalNotificationsPlugin.show(
        message.hashCode,
        title,
        body,
        platformChannelSpecifics,
        payload: jsonEncode(data),
      );

      _dbg('_showNotification: show() ok id=${message.hashCode} type=$type');
    } catch (e) {
      _dbg('_showNotification: failed: $e');
    }
  }

  static List<AndroidNotificationAction> _buildAndroidActionsForData(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['notification_type'] ?? '').toString();
    final typeNorm = type.trim().toLowerCase();
    final action = (data['action'] ?? '').toString();

    _dbg('_buildAndroidActionsForData: type=$type action=$action dataKeys=${data.keys.toList()}');

    if (typeNorm == 'chat_message' || typeNorm == 'chat_broadcast') {
      return <AndroidNotificationAction>[
        AndroidNotificationAction(
          'reply',
          'Reply',
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Type your message'),
          ],
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'mark_read',
          'Mark read',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'open',
          'Open',
          showsUserInterface: true,
        ),
      ];
    }

    if (typeNorm == 'support_admin' || typeNorm == 'support_bot') {
      return <AndroidNotificationAction>[
        AndroidNotificationAction(
          'reply',
          'Reply',
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Type your message'),
          ],
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'mark_read',
          'Mark read',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'open',
          'Open',
          showsUserInterface: true,
        ),
      ];
    }

    if (typeNorm == 'ride_request') {
      return <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'driver_accept',
          'Accept',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'driver_counter',
          'Counter',
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Enter counter fare (PKR per seat)'),
          ],
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'driver_reject',
          'Reject',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'driver_block',
          'Block',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'driver_blacklist',
          'Blocklist',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'open',
          'View',
          showsUserInterface: true,
        ),
      ];
    }

    if (typeNorm == 'booking_update') {
      if (action == 'driver_counter') {
        return <AndroidNotificationAction>[
          AndroidNotificationAction(
            'passenger_counter',
            'Counter',
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'Enter counter fare (PKR per seat)'),
            ],
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'passenger_withdraw',
            'Withdraw',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'open',
            'View',
            showsUserInterface: true,
          ),
        ];
      }

      if (action == 'passenger_counter') {
        return <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'driver_accept',
            'Accept',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'driver_counter',
            'Counter',
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'Enter counter fare (PKR per seat)'),
            ],
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'driver_reject',
            'Reject',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'driver_block',
            'Block',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'driver_blacklist',
            'Blocklist',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'open',
            'View',
            showsUserInterface: true,
          ),
        ];
      }

      return const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'open',
          'View',
          showsUserInterface: true,
        ),
      ];
    }

    if (typeNorm == 'payment_submitted') {
      return const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'open',
          'View',
          showsUserInterface: true,
        ),
      ];
    }

    if (typeNorm == 'driver_task_pickup') {
      return const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'driver_reached_pickup',
          'Reached',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'open',
          'Open',
          showsUserInterface: true,
        ),
      ];
    }

    if (typeNorm == 'driver_task_dropoff') {
      return const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'driver_reached_dropoff',
          'Reached',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'open',
          'Open',
          showsUserInterface: true,
        ),
      ];
    }

    if (typeNorm == 'ride_started' ||
        typeNorm == 'passenger_started' ||
        typeNorm == 'pickup_code_verified' ||
        typeNorm == 'trip_completed' ||
        typeNorm == 'passenger_dropped_off' ||
        typeNorm == 'driver_near_pickup' ||
        typeNorm == 'near_destination' ||
        typeNorm == 'driver_reached_pickup' ||
        typeNorm == 'driver_reached_dropoff' ||
        typeNorm == 'driver_dropoff_completed' ||
        typeNorm == 'pre_ride_reminder_driver' ||
        typeNorm == 'pre_ride_reminder_passenger' ||
        typeNorm == 'booking_cancelled_by_passenger' ||
        typeNorm == 'trip_cancelled_by_driver') {
      return const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'open',
          'Open',
          showsUserInterface: true,
        ),
      ];
    }

    return const <AndroidNotificationAction>[];
  }

  static Future<void> handleNotificationResponse(NotificationResponse response) async {
    DartPluginRegistrant.ensureInitialized();
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      _dbg('handleNotificationResponse: empty payload; actionId=${response.actionId}');
      return;
    }

    // ignore: avoid_print
    debugPrint('[NotificationService] handleNotificationResponse: actionId=${response.actionId} input=${response.input}');

    String? payloadType;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        payloadType = (decoded['type'] ?? decoded['notification_type'] ?? '').toString();
      }
    } catch (_) {}
    _dbg('handleNotificationResponse: actionId=${response.actionId} payloadType=$payloadType payloadLen=${payload.length}');

    if (response.actionId == 'reply') {
      final replyText = response.input;
      if (replyText == null || replyText.trim().isEmpty) {
        _dbg('handleNotificationResponse: reply action but empty input');
        return;
      }
      await _handleInlineReply(payload, replyText.trim());
      return;
    }

    if (response.actionId == 'mark_read') {
      await _handleMarkRead(payload);
      return;
    }

    if (response.actionId != null && response.actionId!.isNotEmpty && response.actionId != 'open') {
      await _handleGenericAction(payload, response.actionId!, response.input);
      return;
    }

    _handleNotificationTap(payload);
  }

  static Future<void> _handleGenericAction(String payload, String actionId, String? input) async {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else {
        _dbg('_handleGenericAction: payload decoded but not a map');
        return;
      }
    } catch (_) {
      _dbg('_handleGenericAction: payload jsonDecode failed');
      return;
    }

    final type = (data['type'] ?? '').toString();
    final tripId = (data['trip_id'] ?? '').toString();
    final bookingId = int.tryParse((data['booking_id'] ?? '').toString()) ?? 0;
    final session = await AuthSession.load();
    final uid = int.tryParse((session?['id'] ?? '').toString()) ?? 0;

    _dbg('_handleGenericAction: sessionLoaded=${session != null} uid=$uid sessionKeys=${session?.keys.toList() ?? []}');

    // ignore: avoid_print
    debugPrint('[NotificationService] Generic action: type=$type actionId=$actionId tripId=$tripId bookingId=$bookingId uid=$uid input=$input');

    int? parsePkr(String? v) {
      if (v == null) return null;
      final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
      final parsed = int.tryParse(cleaned);
      if (parsed == null || parsed <= 0) return null;
      return parsed;
    }

    if (type == 'ride_request') {
      if (tripId.isEmpty || bookingId == 0 || uid == 0) {
        _dbg('_handleGenericAction(ride_request): missing fields tripId=$tripId bookingId=$bookingId uid=$uid');
        return;
      }
      if (actionId == 'driver_accept') {
        _dbg('API start: respondBookingRequest accept tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'accept',
            driverId: uid,
          );
          _dbg('API ok: respondBookingRequest accept');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_accept failed: $e');
          _dbg('API fail: respondBookingRequest accept err=$e');
        }
        return;
      }
      if (actionId == 'driver_counter') {
        final fare = parsePkr(input);
        if (fare == null) {
          _dbg('driver_counter(ride_request): invalid fare input=$input');
          return;
        }
        _dbg('API start: respondBookingRequest counter (ride_request) fare=$fare tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'counter',
            driverId: uid,
            counterFare: fare,
            reason: 'Counter from notification',
          );
          _dbg('API ok: respondBookingRequest counter (ride_request)');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_counter (ride_request) failed: $e');
          _dbg('API fail: respondBookingRequest counter (ride_request) err=$e');
        }
        return;
      }
      if (actionId == 'driver_reject') {
        _dbg('API start: respondBookingRequest reject tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'reject',
            driverId: uid,
            reason: 'Rejected from notification',
          );
          _dbg('API ok: respondBookingRequest reject');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_reject failed: $e');
          _dbg('API fail: respondBookingRequest reject err=$e');
        }
        return;
      }
      if (actionId == 'driver_block') {
        _dbg('API start: respondBookingRequest block tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'block',
            driverId: uid,
            reason: 'Blocked from notification',
          );
          _dbg('API ok: respondBookingRequest block');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_block failed: $e');
          _dbg('API fail: respondBookingRequest block err=$e');
        }
        return;
      }
      if (actionId == 'driver_blacklist') {
        _dbg('API start: respondBookingRequest blacklist tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'blacklist',
            driverId: uid,
            reason: 'Blacklisted from notification',
          );
          _dbg('API ok: respondBookingRequest blacklist');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_blacklist failed: $e');
          _dbg('API fail: respondBookingRequest blacklist err=$e');
        }
        return;
      }
    }

    if (type == 'booking_update') {
      if (tripId.isEmpty || bookingId == 0 || uid == 0) {
        _dbg('_handleGenericAction(booking_update): missing fields tripId=$tripId bookingId=$bookingId uid=$uid');
        return;
      }
      if (actionId == 'passenger_accept') {
        _dbg('API start: passengerRespondBooking accept tripId=$tripId bookingId=$bookingId passengerId=$uid');
        try {
          await ApiService.passengerRespondBooking(
            tripId: tripId,
            bookingId: bookingId,
            action: 'accept',
            passengerId: uid,
          );
          _dbg('API ok: passengerRespondBooking accept');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] passenger_accept failed: $e');
          _dbg('API fail: passengerRespondBooking accept err=$e');
        }
        return;
      }
      if (actionId == 'passenger_counter') {
        final fare = parsePkr(input);
        if (fare == null) {
          _dbg('passenger_counter: invalid fare input=$input');
          return;
        }
        _dbg('API start: passengerRespondBooking counter fare=$fare tripId=$tripId bookingId=$bookingId passengerId=$uid');
        try {
          await ApiService.passengerRespondBooking(
            tripId: tripId,
            bookingId: bookingId,
            action: 'counter',
            passengerId: uid,
            counterFare: fare,
            note: 'Counter from notification',
          );
          _dbg('API ok: passengerRespondBooking counter');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] passenger_counter failed: $e');
          _dbg('API fail: passengerRespondBooking counter err=$e');
        }
        return;
      }
      if (actionId == 'passenger_withdraw') {
        _dbg('API start: passengerRespondBooking withdraw tripId=$tripId bookingId=$bookingId passengerId=$uid');
        try {
          await ApiService.passengerRespondBooking(
            tripId: tripId,
            bookingId: bookingId,
            action: 'withdraw',
            passengerId: uid,
          );
          _dbg('API ok: passengerRespondBooking withdraw');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] passenger_withdraw failed: $e');
          _dbg('API fail: passengerRespondBooking withdraw err=$e');
        }
        return;
      }

      if (actionId == 'driver_accept') {
        _dbg('API start: respondBookingRequest accept (booking_update) tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'accept',
            driverId: uid,
          );
          _dbg('API ok: respondBookingRequest accept (booking_update)');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_accept (booking_update) failed: $e');
          _dbg('API fail: respondBookingRequest accept (booking_update) err=$e');
        }
        return;
      }
      if (actionId == 'driver_reject') {
        _dbg('API start: respondBookingRequest reject (booking_update) tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'reject',
            driverId: uid,
            reason: 'Rejected from notification',
          );
          _dbg('API ok: respondBookingRequest reject (booking_update)');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_reject (booking_update) failed: $e');
          _dbg('API fail: respondBookingRequest reject (booking_update) err=$e');
        }
        return;
      }
      if (actionId == 'driver_counter') {
        final fare = parsePkr(input);
        if (fare == null) {
          _dbg('driver_counter: invalid fare input=$input');
          return;
        }
        _dbg('API start: respondBookingRequest counter fare=$fare tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'counter',
            driverId: uid,
            counterFare: fare,
            reason: 'Counter from notification',
          );
          _dbg('API ok: respondBookingRequest counter');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_counter failed: $e');
          _dbg('API fail: respondBookingRequest counter err=$e');
        }
        return;
      }
      if (actionId == 'driver_block') {
        _dbg('API start: respondBookingRequest block (booking_update) tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'block',
            driverId: uid,
            reason: 'Blocked from notification',
          );
          _dbg('API ok: respondBookingRequest block (booking_update)');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_block (booking_update) failed: $e');
          _dbg('API fail: respondBookingRequest block (booking_update) err=$e');
        }
        return;
      }
      if (actionId == 'driver_blacklist') {
        _dbg('API start: respondBookingRequest blacklist (booking_update) tripId=$tripId bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.respondBookingRequest(
            tripId: tripId,
            bookingId: bookingId,
            action: 'blacklist',
            driverId: uid,
            reason: 'Blacklisted from notification',
          );
          _dbg('API ok: respondBookingRequest blacklist (booking_update)');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_blacklist (booking_update) failed: $e');
          _dbg('API fail: respondBookingRequest blacklist (booking_update) err=$e');
        }
        return;
      }
    }

    if (type == 'driver_task_pickup') {
      if (tripId.isEmpty || bookingId == 0 || uid == 0) {
        _dbg('_handleGenericAction(driver_task_pickup): missing fields tripId=$tripId bookingId=$bookingId uid=$uid');
        return;
      }
      if (actionId == 'driver_reached_pickup') {
        _dbg('API start: driverMarkReachedPickup bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.driverMarkReachedPickup(
            bookingId: bookingId,
            driverId: uid,
          );
          _dbg('API ok: driverMarkReachedPickup');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_reached_pickup failed: $e');
          _dbg('API fail: driverMarkReachedPickup err=$e');
        }
        return;
      }
    }

    if (type == 'driver_task_dropoff') {
      if (tripId.isEmpty || bookingId == 0 || uid == 0) {
        _dbg('_handleGenericAction(driver_task_dropoff): missing fields tripId=$tripId bookingId=$bookingId uid=$uid');
        return;
      }
      if (actionId == 'driver_reached_dropoff') {
        _dbg('API start: driverMarkReachedDropoff bookingId=$bookingId driverId=$uid');
        try {
          await ApiService.driverMarkReachedDropoff(
            bookingId: bookingId,
            driverId: uid,
          );
          _dbg('API ok: driverMarkReachedDropoff');
        } catch (e) {
          // ignore: avoid_print
          debugPrint('[NotificationService] driver_reached_dropoff failed: $e');
          _dbg('API fail: driverMarkReachedDropoff err=$e');
        }
        return;
      }
    }

    _dbg('_handleGenericAction: no matching handler for type=$type actionId=$actionId');
  }

  static void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (_navigatorKey == null) {
      _pendingNavigationPayload = payload;
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        _navigateFromData(decoded);
      }
    } catch (_) {
    }
  }

  static void _navigateFromData(Map<String, dynamic> data) async {
    if (_navigatorKey == null) {
      _pendingNavigationPayload = jsonEncode(data);
      return;
    }

    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    final session = await AuthSession.load();
    Map<String, dynamic> userData = session ?? <String, dynamic>{};
    if (session == null) {
      final guestId = int.tryParse((data['guest_user_id'] ?? '').toString()) ?? 0;
      if (guestId > 0) {
        userData = <String, dynamic>{
          'guest_user_id': guestId,
        };
      }
    }
    final type = (data['type'] ?? data['notification_type'] ?? '').toString();

    if (type == 'notification_summary') {
      final session = await AuthSession.load();
      final args = session ?? <String, dynamic>{};
      _navigatorKey.currentState?.pushNamed('/notifications', arguments: args);
      return;
    }

    if (type == 'chat_message' || type == 'chat_broadcast') {
      final tripId = (data['trip_id'] ?? '').toString();
      final otherId = int.tryParse((data['sender_id'] ?? '').toString()) ?? 0;
      final otherName = (data['sender_name'] ?? 'User').toString();
      final senderRole = (data['sender_role'] ?? '').toString().toLowerCase();
      if (tripId.isEmpty || otherId == 0) return;

      final otherInfo = <String, dynamic>{
        'id': otherId,
        'name': otherName,
      };

      // The sender_role in payload is the OTHER party.
      // If sender is passenger, receiver is driver -> open driver individual chat.
      // If sender is driver, receiver is passenger -> open passenger chat.
      if (senderRole == 'passenger') {
        nav.push(
          MaterialPageRoute(
            builder: (_) => DriverIndividualChatScreen(
              userData: userData,
              tripId: tripId,
              chatRoomId: tripId,
              passengerInfo: otherInfo,
            ),
          ),
        );
      } else {
        nav.push(
          MaterialPageRoute(
            builder: (_) => PassengerChatScreen(
              userData: userData,
              tripId: tripId,
              chatRoomId: tripId,
              driverInfo: otherInfo,
            ),
          ),
        );
      }
      return;
    }

    if (type == 'support_admin' || type == 'support_bot') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => SupportChatScreen(userData: userData),
        ),
      );
      return;
    }

    if (type == 'ride_request') {
      final tripId = (data['trip_id'] ?? '').toString();
      if (tripId.isEmpty) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => DriverRequestsScreen(
            userData: userData,
            tripId: tripId,
          ),
        ),
      );
      return;
    }

    if (type == 'booking_update') {
      final tripId = (data['trip_id'] ?? '').toString();
      final bookingId = int.tryParse((data['booking_id'] ?? '').toString()) ?? 0;
      if (tripId.isEmpty || bookingId == 0) return;

      nav.push(
        MaterialPageRoute(
          builder: (_) => NegotiationDetailsScreen(
            userData: userData,
            booking: <String, dynamic>{
              'trip_id': tripId,
              'id': bookingId,
              'booking_id': bookingId,
            },
          ),
        ),
      );
      return;
    }

    final role = (userData['role'] ?? userData['user_type'] ?? userData['type'] ?? '')
        .toString()
        .toLowerCase();
    final isDriver = role.contains('driver');

    if (type == 'driver_near_pickup' ||
        type == 'near_destination' ||
        type == 'driver_reached_pickup' ||
        type == 'driver_task_pickup' ||
        type == 'driver_task_dropoff') {
      final tripId = (data['trip_id'] ?? '').toString();
      final bookingId = int.tryParse((data['booking_id'] ?? '').toString()) ?? 0;
      if (tripId.isEmpty) return;

      if (isDriver) {
        final driverId = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
        if (driverId == 0) return;
        nav.push(
          MaterialPageRoute(
            builder: (_) => DriverLiveTrackingScreen(
              tripId: tripId,
              driverId: driverId,
            ),
          ),
        );
      } else {
        final passengerId = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
        if (passengerId == 0 || bookingId == 0) return;
        nav.push(
          MaterialPageRoute(
            builder: (_) => PassengerLiveTrackingScreen(
              tripId: tripId,
              passengerId: passengerId,
              bookingId: bookingId,
            ),
          ),
        );
      }
      return;
    }

    if (type == 'driver_reached_dropoff' || type == 'driver_dropoff_completed') {
      final tripId = (data['trip_id'] ?? '').toString();
      final bookingId = int.tryParse((data['booking_id'] ?? '').toString()) ?? 0;
      if (tripId.isEmpty) return;
      final uid = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
      if (uid == 0) return;

      if (isDriver) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => DriverPaymentConfirmationScreen(
              tripId: tripId,
              driverId: uid,
            ),
          ),
        );
      } else if (bookingId > 0) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => PassengerPaymentScreen(
              tripId: tripId,
              passengerId: uid,
              bookingId: bookingId,
            ),
          ),
        );
      }
      return;
    }

    if (type == 'passenger_started' || type == 'pre_ride_reminder_driver') {
      final tripId = (data['trip_id'] ?? '').toString();
      if (tripId.isEmpty) return;
      final driverId = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
      if (driverId == 0) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => DriverLiveTrackingScreen(
            tripId: tripId,
            driverId: driverId,
          ),
        ),
      );
      return;
    }

    if (type == 'ride_started' || type == 'pre_ride_reminder_passenger') {
      final tripId = (data['trip_id'] ?? '').toString();
      final bookingId = int.tryParse((data['booking_id'] ?? '').toString()) ?? 0;
      if (tripId.isEmpty || bookingId == 0) return;
      final passengerId = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
      if (passengerId == 0) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => PassengerLiveTrackingScreen(
            tripId: tripId,
            passengerId: passengerId,
            bookingId: bookingId,
          ),
        ),
      );
      return;
    }

    if (type == 'pickup_code_verified') {
      final tripId = (data['trip_id'] ?? '').toString();
      if (tripId.isEmpty) return;

      if (isDriver) {
        final driverId = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
        if (driverId == 0) return;
        nav.push(
          MaterialPageRoute(
            builder: (_) => DriverLiveTrackingScreen(
              tripId: tripId,
              driverId: driverId,
            ),
          ),
        );
        return;
      }

      final bookingId = int.tryParse((data['booking_id'] ?? '').toString()) ?? 0;
      final passengerId = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
      if (bookingId == 0 || passengerId == 0) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => PassengerLiveTrackingScreen(
            tripId: tripId,
            passengerId: passengerId,
            bookingId: bookingId,
          ),
        ),
      );
      return;
    }

    if (type == 'payment_submitted') {
      final tripId = (data['trip_id'] ?? '').toString();
      if (tripId.isEmpty) return;
      final driverId = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
      if (driverId == 0) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => DriverPaymentConfirmationScreen(
            tripId: tripId,
            driverId: driverId,
          ),
        ),
      );
      return;
    }

    if (type == 'trip_completed' || type == 'passenger_dropped_off') {
      final tripId = (data['trip_id'] ?? '').toString();
      final bookingId = int.tryParse((data['booking_id'] ?? '').toString()) ?? 0;
      if (tripId.isEmpty) return;
      final uid = int.tryParse((userData['id'] ?? '').toString()) ?? 0;
      if (uid == 0) return;

      // Driver should always go to DriverPaymentConfirmationScreen.
      // Passenger goes to PassengerPaymentScreen (requires booking_id).
      if (isDriver) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => DriverPaymentConfirmationScreen(
              tripId: tripId,
              driverId: uid,
            ),
          ),
        );
      } else if (bookingId > 0) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => PassengerPaymentScreen(
              tripId: tripId,
              passengerId: uid,
              bookingId: bookingId,
            ),
          ),
        );
      }
      return;
    }

    if (type == 'booking_cancelled_by_passenger' || type == 'trip_cancelled_by_driver') {
      nav.pushNamed('/my-rides', arguments: userData);
      return;
    }
  }

  static Future<void> _handleInlineReply(String payload, String replyText) async {
    _dbg('_handleInlineReply() start replyLen=${replyText.length}');
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else {
        _dbg('_handleInlineReply(): payload decoded but not a map');
        return;
      }
    } catch (_) {
      _dbg('_handleInlineReply(): payload jsonDecode failed');
      return;
    }

    final type = (data['type'] ?? '').toString();
    final session = await AuthSession.load();
    final senderId = int.tryParse((session?['id'] ?? '').toString()) ?? 0;
    final senderName = (session?['name'] ?? session?['full_name'] ?? '').toString();
    final senderRole = (session?['role'] ?? session?['user_type'] ?? session?['type'] ?? '')
        .toString()
        .toLowerCase();

    final guestUserIdFromPayload = int.tryParse((data['guest_user_id'] ?? '').toString()) ?? 0;
    int guestUserId = guestUserIdFromPayload;
    String? fcmToken;
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((session == null || senderId == 0) && guestUserId <= 0) {
        guestUserId = int.tryParse((prefs.getString('guest_user_id') ?? '').toString()) ?? 0;
      }
      final cached = (prefs.getString('fcm_token') ?? '').trim();
      if (cached.isNotEmpty) fcmToken = cached;
    } catch (_) {}

    _dbg('_handleInlineReply(): type=$type senderId=$senderId senderRole=$senderRole sessionLoaded=${session != null}');

    if (type == 'chat_message' || type == 'chat_broadcast') {
      final tripId = (data['trip_id'] ?? '').toString();
      final otherId = int.tryParse((data['sender_id'] ?? '').toString()) ?? 0;
      if (tripId.isEmpty || senderId == 0 || otherId == 0) {
        _dbg('_handleInlineReply(chat): missing fields tripId=$tripId senderId=$senderId otherId=$otherId');
        return;
      }

      _dbg('API start: ChatService.sendMessage chatRoomId=$tripId senderId=$senderId otherId=$otherId');
      try {
        await ChatService.sendMessage(
          chatRoomId: tripId,
          senderId: senderId,
          senderName: senderName.isEmpty ? 'User' : senderName,
          senderRole: senderRole.contains('driver') ? 'driver' : 'passenger',
          messageText: replyText,
          messageType: 'text',
          isBroadcast: false,
          targetUserIds: [otherId],
        );
        _dbg('API ok: ChatService.sendMessage');
      } catch (e) {
        _dbg('API fail: ChatService.sendMessage err=$e');
      }
    }

    if (type == 'support_admin') {
      if (senderId == 0 && guestUserId == 0) {
        _dbg('_handleInlineReply(support_admin): senderId==0 and guestUserId==0');
        return;
      }
      _dbg('API start: ApiService.sendSupportAdminMessage userId=$senderId guestUserId=$guestUserId');
      try {
        await ApiService.sendSupportAdminMessage(
          userId: senderId,
          guestUserId: guestUserId > 0 ? guestUserId : null,
          messageText: replyText,
          fcmToken: guestUserId > 0 ? fcmToken : null,
        );
        _dbg('API ok: ApiService.sendSupportAdminMessage');
      } catch (e) {
        _dbg('API fail: ApiService.sendSupportAdminMessage err=$e');
      }
    }

    if (type == 'support_bot') {
      if (senderId == 0 && guestUserId == 0) {
        _dbg('_handleInlineReply(support_bot): senderId==0 and guestUserId==0');
        return;
      }
      _dbg('API start: ApiService.sendSupportBotMessage userId=$senderId guestUserId=$guestUserId');
      try {
        await ApiService.sendSupportBotMessage(
          userId: senderId,
          guestUserId: guestUserId > 0 ? guestUserId : null,
          messageText: replyText,
          fcmToken: guestUserId > 0 ? fcmToken : null,
        );
        _dbg('API ok: ApiService.sendSupportBotMessage');
      } catch (e) {
        _dbg('API fail: ApiService.sendSupportBotMessage err=$e');
      }
    }

    _dbg('_handleInlineReply() done');
  }

  static Future<void> _handleMarkRead(String payload) async {
    _dbg('_handleMarkRead() start');
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else {
        _dbg('_handleMarkRead(): payload decoded but not a map');
        return;
      }
    } catch (_) {
      _dbg('_handleMarkRead(): payload jsonDecode failed');
      return;
    }

    final type = (data['type'] ?? '').toString();
    final session = await AuthSession.load();
    final userId = int.tryParse((session?['id'] ?? '').toString()) ?? 0;
    final guestUserIdFromPayload = int.tryParse((data['guest_user_id'] ?? '').toString()) ?? 0;
    int guestUserId = guestUserIdFromPayload;
    try {
      if ((session == null || userId == 0) && guestUserId <= 0) {
        final prefs = await SharedPreferences.getInstance();
        guestUserId = int.tryParse((prefs.getString('guest_user_id') ?? '').toString()) ?? 0;
      }
    } catch (_) {}

    _dbg('_handleMarkRead(): type=$type userId=$userId guestUserId=$guestUserId');

    if (type == 'chat_message' || type == 'chat_broadcast') {
      if (userId == 0) {
        _dbg('_handleMarkRead(chat): userId==0 sessionLoaded=${session != null}');
        return;
      }
      final messageId = int.tryParse((data['message_id'] ?? '').toString()) ?? 0;
      if (messageId == 0) {
        _dbg('_handleMarkRead(chat): messageId==0');
        return;
      }
      _dbg('API start: ChatService.markMessageAsRead messageId=$messageId userId=$userId');
      try {
        await ChatService.markMessageAsRead(messageId: messageId, userId: userId);
        _dbg('API ok: ChatService.markMessageAsRead');
      } catch (e) {
        _dbg('API fail: ChatService.markMessageAsRead err=$e');
      }
    }

    if (type == 'support_admin') {
      try {
        await ApiService.getSupportAdminUpdates(
          userId: userId,
          guestUserId: guestUserId > 0 ? guestUserId : null,
          sinceId: 0,
        );
        _dbg('API ok: ApiService.getSupportAdminUpdates');
      } catch (_) {}
    }

    if (type == 'support_bot') {
      try {
        await ApiService.getSupportBotUpdates(
          userId: userId,
          guestUserId: guestUserId > 0 ? guestUserId : null,
          sinceId: 0,
        );
        _dbg('API ok: ApiService.getSupportBotUpdates');
      } catch (_) {}
    }

    _dbg('_handleMarkRead() done');
  }

  // Call this when user logs out
  static Future<void> onUserLogout() async {
    try {
      // Clear local session-related storage but keep the device's FCM
      // token cached so that a future explicit login (in the same app
      // session) can immediately re-register this device with the
      // backend.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('logged_in_user_id');

      // Stop any live tracking session so UI overlays (SOS) and background
      // sender do not continue after logout.
      await LiveTrackingSessionManager.instance.stopSession(clearPersisted: true);
      
      // Clear all notifications
      await _flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('Error during logout cleanup: $e');
    }
  }
}
