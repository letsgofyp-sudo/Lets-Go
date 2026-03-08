import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/fare_calculator.dart';
import '../constants.dart';

class ApiService {
  // Headers for API requests
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    // Add authentication headers if needed
    // 'Authorization': 'Bearer $token',
  };

  static Future<int?> triggerAutoArchiveForDriver({
    required int userId,
    int limit = 5,
  }) async {
    if (userId <= 0) return null;
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/auto-archive/')
          .replace(queryParameters: {
        'limit': limit.toString(),
      });
      final response = await http
          .post(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));

      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (decoded is! Map<String, dynamic>) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (decoded['success'] != true) return null;

      final processed = decoded['processed'];
      if (processed is int) return processed;
      return int.tryParse(processed?.toString() ?? '');
    } catch (_) {
      return null;
    }

  }

  // ================= Notifications Inbox =================

  static Future<Map<String, dynamic>> listNotifications({
    int? userId,
    int? guestUserId,
    int limit = 50,
    int offset = 0,
  }) async {
    final qp = <String, String>{
      if (userId != null && userId > 0) 'user_id': userId.toString(),
      if (guestUserId != null && guestUserId > 0)
        'guest_user_id': guestUserId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    final uri = Uri.parse('$url/lets_go/notifications/').replace(queryParameters: qp);
    final response = await http.get(uri, headers: _headers);
    final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
    if (decoded is Map<String, dynamic>) return decoded;
    return {'success': response.statusCode >= 200 && response.statusCode < 300};
  }

  static Future<int> getNotificationUnreadCount({
    int? userId,
    int? guestUserId,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/notifications/unread-count/').replace(
        queryParameters: {
          if (userId != null && userId > 0) 'user_id': userId.toString(),
          if (guestUserId != null && guestUserId > 0)
            'guest_user_id': guestUserId.toString(),
        },
      );
      final response = await http.get(uri, headers: _headers);
      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (decoded is Map<String, dynamic>) {
        final v = decoded['unread_count'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<Map<String, dynamic>> markNotificationRead({
    required int notificationId,
  }) async {
    final uri = Uri.parse('$url/lets_go/notifications/$notificationId/read/');
    final response = await http.post(uri, headers: _headers);
    final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
    if (decoded is Map<String, dynamic>) return decoded;
    return {'success': response.statusCode >= 200 && response.statusCode < 300};
  }

  static Future<Map<String, dynamic>> dismissNotification({
    required int notificationId,
  }) async {
    final uri = Uri.parse('$url/lets_go/notifications/$notificationId/dismiss/');
    final response = await http.post(uri, headers: _headers);
    final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
    if (decoded is Map<String, dynamic>) return decoded;
    return {'success': response.statusCode >= 200 && response.statusCode < 300};
  }

  static Future<Map<String, dynamic>> markAllNotificationsRead({
    int? userId,
    int? guestUserId,
  }) async {
    final uri = Uri.parse('$url/lets_go/notifications/mark-all-read/');
    final response = await http.post(
      uri,
      headers: _headers,
      body: json.encode({
        if (userId != null && userId > 0) 'user_id': userId,
        if (guestUserId != null && guestUserId > 0) 'guest_user_id': guestUserId,
      }),
    );
    final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
    if (decoded is Map<String, dynamic>) return decoded;
    return {'success': response.statusCode >= 200 && response.statusCode < 300};
  }

  static Future<Map<String, dynamic>> resetRejectedUser({
    String? email,
    String? phoneNo,
    String? username,
  }) async {
    try {
      final endpoint = Uri.parse('$url/lets_go/reset_rejected_user/');
      final body = <String, String>{
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (phoneNo != null && phoneNo.trim().isNotEmpty) 'phone_no': phoneNo.trim(),
        if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
      };
      final response = await http.post(
        endpoint,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );
      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Get user's created rides history (archived after 24h finalization)
  static Future<Map<String, dynamic>> getUserCreatedRidesHistory({
    required int userId,
    int limit = 10,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$url/lets_go/users/$userId/rides/history/')
        .replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    final response = await http.get(uri, headers: _headers);
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Get user's booked rides history (archived after 24h finalization)
  static Future<Map<String, dynamic>> getUserBookedRidesHistory({
    required int userId,
    int limit = 10,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$url/lets_go/users/$userId/bookings/history/')
        .replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    final response = await http.get(uri, headers: _headers);
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<String?> resolveTripShareTokenToTripId(String token) async {
    final t = token.trim();
    if (t.isEmpty) return null;
    try {
      final endpoint = '$url/lets_go/trips/share/$t/live/';
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (decoded is! Map<String, dynamic>) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final tripId = (decoded['trip_id'] ?? '').toString().trim();
      if (tripId.isEmpty) return null;
      return tripId;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> createTripShareUrl({
    required String tripId,
    required String role,
    int? bookingId,
  }) async {
    try {
      final endpoint = '$url/lets_go/trips/$tripId/share/';
      final body = <String, dynamic>{
        'role': role,
      };
      if (bookingId != null && bookingId > 0) {
        body['booking_id'] = bookingId;
      }
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 12));

      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }

      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to create share link',
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to create share link',
        'status': response.statusCode,
      };
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Network timeout',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  static Future<bool> isTripAvailableForUser({
    required int userId,
    required String tripId,
  }) async {
    if (userId <= 0 || tripId.trim().isEmpty) return false;
    try {
      final list = await getAllTrips(
        userId: userId,
        limit: 200,
        offset: 0,
      );
      final t = tripId.trim();
      for (final r in list) {
        if ((r['trip_id'] ?? '').toString().trim() == t) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> createGuestSupportUser({
    int? existingGuestUserId,
    String? fcmToken,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/support/guest/');
      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode({
          if (existingGuestUserId != null && existingGuestUserId > 0)
            'guest_user_id': existingGuestUserId,
          if (fcmToken != null && fcmToken.trim().isNotEmpty) 'fcm_token': fcmToken.trim(),
        }),
      );
      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (decoded is Map<String, dynamic>) return decoded;
      return {'success': response.statusCode >= 200 && response.statusCode < 300};
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  static Future<List<Map<String, dynamic>>> getSupportBotMessages({
    required int userId,
  }) async {
    try {
      return await getSupportBotNewMessages(userId: userId, sinceId: 0);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getSupportBotNewMessages({
    required int userId,
    required int sinceId,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/support/bot/').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'since_id': sinceId.toString(),
        },
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      }
      throw Exception('Failed to load bot chat: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> getSupportBotUpdates({
    required int userId,
    int? guestUserId,
    required int sinceId,
  }) async {
    final uri = Uri.parse('$url/lets_go/support/bot/').replace(
      queryParameters: {
        if (guestUserId != null && guestUserId > 0)
          'guest_user_id': guestUserId.toString()
        else
          'user_id': userId.toString(),
        'since_id': sinceId.toString(),
      },
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load bot chat: ${response.statusCode}');
    }
    final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
    if (decoded is Map<String, dynamic>) return decoded;
    return {'success': true, 'messages': []};
  }

  static Future<List<Map<String, dynamic>>> sendSupportBotMessage({
    required int userId,
    int? guestUserId,
    required String messageText,
    String? fcmToken,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/support/bot/');
      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode({
          if (guestUserId != null && guestUserId > 0)
            'guest_user_id': guestUserId
          else
            'user_id': userId,
          'message_text': messageText,
          if (fcmToken != null && fcmToken.trim().isNotEmpty) 'fcm_token': fcmToken.trim(),
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      }
      throw Exception('Failed to send bot message: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getSupportAdminMessages({
    required int userId,
  }) async {
    try {
      return await getSupportAdminNewMessages(userId: userId, sinceId: 0);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getSupportAdminNewMessages({
    required int userId,
    required int sinceId,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/support/admin/').replace(
        queryParameters: {
          'user_id': userId.toString(),
          'since_id': sinceId.toString(),
        },
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      }
      throw Exception('Failed to load admin chat: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> getSupportAdminUpdates({
    required int userId,
    int? guestUserId,
    required int sinceId,
  }) async {
    final uri = Uri.parse('$url/lets_go/support/admin/').replace(
      queryParameters: {
        if (guestUserId != null && guestUserId > 0)
          'guest_user_id': guestUserId.toString()
        else
          'user_id': userId.toString(),
        'since_id': sinceId.toString(),
      },
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load admin chat: ${response.statusCode}');
    }
    final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
    if (decoded is Map<String, dynamic>) return decoded;
    return {'success': true, 'messages': []};
  }

  static Future<Map<String, dynamic>> sendSupportAdminMessage({
    required int userId,
    int? guestUserId,
    required String messageText,
    String? fcmToken,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/support/admin/');
      final response = await http.post(
        uri,
        headers: _headers,
        body: json.encode({
          if (guestUserId != null && guestUserId > 0)
            'guest_user_id': guestUserId
          else
            'user_id': userId,
          'message_text': messageText,
          if (fcmToken != null && fcmToken.trim().isNotEmpty) 'fcm_token': fcmToken.trim(),
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) return data;
        return {'success': true};
      }
      throw Exception('Failed to send admin message: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get route details with fare matrix
  static Future<Map<String, dynamic>> getRouteWithFareMatrix(
    int routeId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/routes/$routeId/'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Convert fare matrix to Flutter format
        data['fare_matrix'] = FareCalculator.convertFareMatrix(
          data['fare_matrix'] ?? [],
        );

        return data;
      } else {
        throw Exception('Failed to load route: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> getUserChangeRequests(
    int userId, {
    String? entityType,
    int? vehicleId,
    String? status,
    int limit = 20,
  }) async {
    try {
      final qp = <String, String>{};
      if (entityType != null && entityType.trim().isNotEmpty) {
        qp['entity_type'] = entityType.trim();
      }
      if (vehicleId != null) {
        qp['vehicle_id'] = vehicleId.toString();
      }
      if (status != null && status.trim().isNotEmpty) {
        qp['status'] = status.trim();
      }
      qp['limit'] = limit.toString();

      final uri = Uri.parse('$url/lets_go/users/$userId/change-requests/').replace(queryParameters: qp);
      final response = await http.get(uri, headers: _headers);

      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to load change requests',
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to load change requests',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getVerificationGateStatus(int userId) async {
    try {
      final user = await getUserProfile(userId);
      final userStatus = (user['status'] ?? '').toString().toUpperCase();
      if (userStatus == 'BANNED') {
        return {
          'blocked': true,
          'code': 'ACCOUNT_BANNED',
          'message': 'Your account is banned. You cannot perform this operation.',
        };
      }
      return {'blocked': false};
    } catch (_) {
      return {'blocked': false};
    }
  }

  static bool _hasAnyPendingFields(
    List<Map<String, dynamic>> changeRequests,
    List<String> keys,
  ) {
    for (final cr in changeRequests) {
      final rc = cr['requested_changes'];
      if (rc is! Map) continue;
      final req = Map<String, dynamic>.from(rc);
      for (final k in keys) {
        if (req.containsKey(k)) return true;
      }
    }
    return false;
  }

  static Future<List<Map<String, dynamic>>> _getPendingUserProfileChangeRequests(
    int userId,
  ) async {
    final cr = await getUserChangeRequests(
      userId,
      entityType: 'USER_PROFILE',
      status: 'PENDING',
      limit: 50,
    );
    final list = (cr['change_requests'] as List?) ?? [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>> getRideBookingGateStatus({
    required int userId,
  }) async {
    try {
      final user = await getUserProfile(userId);
      final userStatus = (user['status'] ?? '').toString().toUpperCase();
      if (userStatus == 'BANNED') {
        return {
          'blocked': true,
          'code': 'ACCOUNT_BANNED',
          'message': 'Your account is banned. You cannot perform this operation.',
        };
      }

      final pending = await _getPendingUserProfileChangeRequests(userId);

      final hasPendingGender = _hasAnyPendingFields(pending, ['gender']);
      final hasPendingUserData = _hasAnyPendingFields(pending, [
        'name',
        'address',
        'email',
        'phone_no',
        'phone_number',
      ]);
      final hasPendingCnic = _hasAnyPendingFields(pending, [
        'cnic_no',
        'cnic',
        'cnic_front_image_url',
        'cnic_back_image_url',
        'cnic_front_image',
        'cnic_back_image',
        'cnic_front',
        'cnic_back',
      ]);

      if (hasPendingUserData || hasPendingCnic || hasPendingGender) {
        return {
          'blocked': true,
          'code': 'VERIFICATION_PENDING',
          'message':
              'Your profile verification is pending (CNIC/Gender/Profile info). Please wait for admin verification before booking rides.',
        };
      }

      return {'blocked': false};
    } catch (_) {
      return {'blocked': false};
    }
  }

  static Future<Map<String, dynamic>> getRideCreateGateStatus({
    required int userId,
    required int vehicleId,
  }) async {
    try {
      final user = await getUserProfile(userId);
      final userStatus = (user['status'] ?? '').toString().toUpperCase();
      if (userStatus == 'BANNED') {
        return {
          'blocked': true,
          'code': 'ACCOUNT_BANNED',
          'message': 'Your account is banned. You cannot perform this operation.',
        };
      }

      final pending = await _getPendingUserProfileChangeRequests(userId);

      final hasPendingLicense = _hasAnyPendingFields(pending, [
        'driving_license_no',
        'driving_license_front_url',
        'driving_license_back_url',
        'driving_license_front',
        'driving_license_back',
      ]);
      final hasPendingGender = _hasAnyPendingFields(pending, ['gender']);
      final hasPendingUserData = _hasAnyPendingFields(pending, [
        'name',
        'address',
        'email',
        'phone_no',
        'phone_number',
      ]);
      final hasPendingCnic = _hasAnyPendingFields(pending, [
        'cnic_no',
        'cnic',
        'cnic_front_image_url',
        'cnic_back_image_url',
        'cnic_front_image',
        'cnic_back_image',
        'cnic_front',
        'cnic_back',
      ]);

      if (hasPendingUserData || hasPendingCnic || hasPendingGender) {
        return {
          'blocked': true,
          'code': 'VERIFICATION_PENDING',
          'message':
              'Your profile verification is pending (CNIC/Gender/Profile info). Please wait for admin verification before creating rides.',
        };
      }

      if (hasPendingLicense) {
        return {
          'blocked': true,
          'code': 'DRIVING_LICENSE_PENDING',
          'message':
              'Driving license verification is pending. You can book rides, but you cannot create rides until it is verified.',
        };
      }

      final vehicles = await getUserVehicles(userId);
      final selected = vehicles.firstWhere(
        (v) => (v['id']?.toString() ?? '') == vehicleId.toString(),
        orElse: () => <String, dynamic>{},
      );
      final st = (selected['status'] ?? '').toString().toUpperCase();
      if (st == 'PENDING') {
        return {
          'blocked': true,
          'code': 'VEHICLE_PENDING',
          'message':
              'Selected vehicle verification is pending. Please wait for admin verification before creating a ride with this vehicle.',
        };
      }

      return {'blocked': false};
    } catch (_) {
      return {'blocked': false};
    }
  }

  /// Logout current user session (best-effort, ignore errors)
  static Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$url/lets_go/logout/'),
        headers: _headers,
      );
    } catch (_) {
      // Ignore logout errors on client side
    }
  }

  /// Get confirmed passengers for a trip (driver chat members)
  static Future<List<Map<String, dynamic>>> getTripPassengers(
    String tripId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$url/lets_go/ride-booking/$tripId/passengers/'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['passengers'] ?? []);
      } else {
        throw Exception('Failed to load trip passengers: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get single vehicle details (lightweight, no binary)
  static Future<Map<String, dynamic>> getVehicleDetails(int vehicleId) async {
    try {
      final endpoint = '$url/lets_go/vehicles/$vehicleId/';
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          return Map<String, dynamic>.from(data);
        }
        return <String, dynamic>{};
      } else {
        try {
          final err = json.decode(response.body);
          throw Exception('Failed to load vehicle details: ${err['error'] ?? response.statusCode}');
        } catch (_) {
          throw Exception('Failed to load vehicle details: ${response.statusCode}');
        }
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get user profile by ID
  static Future<Map<String, dynamic>> getUserProfile(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/users/$userId/'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          // Support both {user: {...}} and raw user object
          if (data.containsKey('user') && data['user'] is Map<String, dynamic>) {
            return Map<String, dynamic>.from(data['user']);
          }
          return Map<String, dynamic>.from(data);
        }
        return <String, dynamic>{};
      } else {
        throw Exception('Failed to load user profile: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // ================= Driver Requests APIs =================
  static Future<List<Map<String, dynamic>>> listPendingRequests({
    required String tripId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/ride-booking/$tripId/requests/'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(
          data['requests'] ?? data['pending_requests'] ?? [],
        );
      } else {
        throw Exception('Failed to load pending requests: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  static Future<Map<String, dynamic>> getBookingRequestDetails({
    required String tripId,
    required int bookingId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/ride-booking/$tripId/requests/$bookingId/'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Map<String, dynamic>.from(data['booking'] ?? {});
      } else {
        throw Exception('Failed to load booking details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  static Future<Map<String, dynamic>> respondBookingRequest({
    required String tripId,
    required int bookingId,
    required String action, // 'accept' | 'reject' | 'counter'
    required int driverId,
    int? counterFare,
    String? reason,
  }) async {
    try {
      final endpoint = '$url/lets_go/ride-booking/$tripId/requests/$bookingId/respond/';
      final payload = <String, dynamic>{
        'action': action,
        'driver_id': driverId,
        if (counterFare != null) 'counter_fare': counterFare,
        if (reason != null) 'reason': reason,
      };
      final response = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: json.encode(payload),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final err = json.decode(response.body);
        throw Exception('Respond failed: ${err['error'] ?? response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // ================= Passenger Decision APIs =================
  static Future<Map<String, dynamic>> passengerRespondBooking({
    required String tripId,
    required int bookingId,
    required String action, // 'accept' | 'counter' | 'withdraw'
    required int passengerId,
    int? counterFare,
    String? note,
  }) async {
    try {
      final endpoint = '$url/lets_go/ride-booking/$tripId/requests/$bookingId/passenger-respond/';
      final payload = <String, dynamic>{
        'action': action,
        'passenger_id': passengerId,
        if (counterFare != null) 'counter_fare': counterFare,
        if (note != null && note.isNotEmpty) 'note': note,
      };
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 12));
      final data = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (data is Map<String, dynamic>) {
          return {
            'success': data.containsKey('success') ? data['success'] : true,
            ...data,
          };
        }
        return {'success': true};
      }
      return {
        'success': false,
        'error': data is Map<String, dynamic> ? (data['error'] ?? 'Unknown error') : 'Request failed',
        'status': response.statusCode,
      };
    } on TimeoutException {
      return {'success': false, 'error': 'Network timeout'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ================= Negotiation History APIs =================
  static Future<Map<String, dynamic>> getNegotiationHistory({
    required String tripId,
    required int bookingId,
  }) async {
    try {
      final endpoint = '$url/lets_go/ride-booking/$tripId/negotiation/$bookingId/';
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      final data = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && data is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data);
      }
      throw Exception(
        'Failed to load negotiation history: '
        '${data is Map<String, dynamic> ? (data['error'] ?? response.statusCode) : response.statusCode}',
      );
    } on TimeoutException {
      throw Exception('Network timeout while loading negotiation history');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // ================= Blocking / Blocklist APIs =================
  static Future<List<Map<String, dynamic>>> getBlockedUsers({
    required int userId,
  }) async {
    try {
      final endpoint = '$url/lets_go/users/$userId/blocked/';
      final response = await http.get(
        Uri.parse(endpoint),
        headers: _headers,
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) {
          final list = decoded['blocked'];
          if (list is List) {
            return list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        }
        return <Map<String, dynamic>>[];
      }
      if (decoded is Map<String, dynamic>) {
        throw Exception(decoded['error'] ?? 'Failed to load blocked users');
      }
      throw Exception('Failed to load blocked users');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> unblockUser({
    required int userId,
    required int blockedUserId,
  }) async {
    try {
      final endpoint = '$url/lets_go/users/$userId/blocked/$blockedUserId/unblock/';
      final response = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: json.encode({}),
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to unblock user',
          'status': response.statusCode,
        };
      }
      return {'success': false, 'error': 'Failed to unblock user', 'status': response.statusCode};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<List<Map<String, dynamic>>> searchUsersToBlock({
    required int userId,
    required String query,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return <Map<String, dynamic>>[];
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/blocked/search/')
          .replace(queryParameters: {'q': q});
      final response = await http
          .get(
            uri,
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) {
          final list = decoded['users'];
          if (list is List) {
            return list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        }
        return <Map<String, dynamic>>[];
      }
      if (decoded is Map<String, dynamic>) {
        throw Exception(decoded['error'] ?? 'Failed to search users');
      }
      throw Exception('Failed to search users');
    } on TimeoutException {
      throw Exception('Network timeout while searching users');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> blockUser({
    required int userId,
    required int blockedUserId,
    String? reason,
  }) async {
    try {
      final endpoint = '$url/lets_go/users/$userId/blocked/block/';
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: json.encode({
              'blocked_user_id': blockedUserId,
              if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));

      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }

      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to block user',
          'status': response.statusCode,
        };
      }
      return {'success': false, 'error': 'Failed to block user', 'status': response.statusCode};
    } on TimeoutException {
      return {'success': false, 'error': 'Network timeout'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ================= Password =================
  static Future<Map<String, dynamic>> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final endpoint = '$url/lets_go/users/$userId/password/change/';
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: json.encode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 12));

      final decoded = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to change password',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {'success': false, 'error': 'Failed to change password', 'status': response.statusCode};
    } on TimeoutException {
      return {'success': false, 'error': 'Network timeout'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> unblockPassengerForTrip({
    required String tripId,
    required int passengerId,
    required int driverId,
  }) async {
    try {
      final endpoint = '$url/lets_go/ride-booking/$tripId/blocked/$passengerId/unblock/';
      final response = await http.post(
        Uri.parse(endpoint),
        headers: _headers,
        body: json.encode({'driver_id': driverId}),
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to unblock passenger',
          'status': response.statusCode,
        };
      }
      return {'success': false, 'error': 'Failed to unblock passenger', 'status': response.statusCode};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Get trip details with available seats
  static Future<Map<String, dynamic>> getTripDetails(int tripId) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/trips/$tripId/'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['trip'] ?? {};
      } else {
        throw Exception('Failed to load trip: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get trip details by string trip_id (e.g., "T123-2025-01-01-09:00")
  static Future<Map<String, dynamic>> getTripDetailsById(String tripId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$url/lets_go/trips/$tripId/'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          return Map<String, dynamic>.from(data['trip'] ?? {});
        }
        return <String, dynamic>{};
      } else {
        throw Exception('Failed to load trip by id: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get available seats for a trip
  static Future<List<int>> getAvailableSeats(int tripId) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/trips/$tripId/available-seats/'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<int>.from(data['available_seats'] ?? []);
      } else {
        throw Exception(
          'Failed to load available seats: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Create a booking
  static Future<Map<String, dynamic>> createBooking(
    Map<String, dynamic> bookingData,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/bookings/'),
        headers: _headers,
        body: json.encode(bookingData),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          'Booking failed: ${errorData['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get user's booking history
  static Future<List<Map<String, dynamic>>> getUserBookings(int userId) async {
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/bookings/')
          .replace(queryParameters: {
        'mode': 'summary',
      });
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['bookings'] ?? []);
      } else {
        throw Exception('Failed to load bookings: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get route statistics
  static Future<Map<String, dynamic>> getRouteStatistics(int routeId) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/routes/$routeId/statistics/'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
          'Failed to load route statistics: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Search for routes
  static Future<List<Map<String, dynamic>>> searchRoutes({
    String? fromLocation,
    String? toLocation,
    DateTime? departureDate,
    int? minSeats,
    double? maxPrice,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (fromLocation != null) queryParams['from'] = fromLocation;
      if (toLocation != null) queryParams['to'] = toLocation;
      if (departureDate != null) {
        queryParams['date'] = departureDate.toIso8601String();
      }
      if (minSeats != null) queryParams['min_seats'] = minSeats.toString();
      if (maxPrice != null) queryParams['max_price'] = maxPrice.toString();

      final uri = Uri.parse(
        '$url/lets_go/routes/search/',
      ).replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['routes'] ?? []);
      } else {
        throw Exception('Failed to search routes: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get fare matrix for a route (cached version)
  static Future<Map<String, dynamic>> getCachedFareMatrix(int routeId) async {
    // TODO: Implement caching logic
    // For now, just call the API
    final routeData = await getRouteWithFareMatrix(routeId);
    return routeData['fare_matrix'] ?? {};
  }

  /// Update fare matrix cache
  static Future<void> updateFareMatrixCache(
    int routeId,
    Map<String, dynamic> fareMatrix,
  ) async {
    // TODO: Implement cache update logic
    // This could store the fare matrix in SharedPreferences or a local database
    // Cache update for route $routeId
  }

  /// Clear fare matrix cache
  static Future<void> clearFareMatrixCache() async {
    // TODO: Implement cache clearing logic
    // Clearing fare matrix cache
  }

  /// Get all available trips
  static Future<List<Map<String, dynamic>>> getAllTrips({
    int? userId,
    int? limit,
    int? offset,
  }) async {
    try {
      final qp = <String, String>{};
      if (userId != null && userId > 0) qp['user_id'] = userId.toString();
      if (limit != null) qp['limit'] = limit.toString();
      if (offset != null) qp['offset'] = offset.toString();

      final uri = Uri.parse('$url/lets_go/all_trips/').replace(queryParameters: qp.isEmpty ? null : qp);

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['trips'] ?? []);
      } else {
        throw Exception('Failed to load trips: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get detailed ride information
  static Future<Map<String, dynamic>> getRideDetails(int rideId) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/rides/$rideId/'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load ride details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get ride booking details
  static Future<Map<String, dynamic>> getRideBookingDetails(
    String tripId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$url/lets_go/ride-booking/$tripId/'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load ride details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Request ride booking with bargaining
  static Future<Map<String, dynamic>> requestRideBooking(
    Map<String, dynamic> bookingData,
  ) async {
    try {
      final endpoint = '$url/lets_go/ride-booking/${bookingData['trip_id']}/request/';
      debugPrint('[BOOKING] POST $endpoint');
      debugPrint('[BOOKING] payload: ${json.encode(bookingData)}');
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: json.encode(bookingData),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        // Normalize success for 200/201 even if backend doesn't include 'success'
        if (data is Map<String, dynamic>) {
          return {
            'success': data.containsKey('success') ? data['success'] : true,
            ...data,
          };
        }
        return {'success': true};
      } else {
        debugPrint('[BOOKING] error status: ${response.statusCode}');
        debugPrint('[BOOKING] error body: ${response.body}');
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Booking request failed',
          'status': response.statusCode,
        };
      }
    } on TimeoutException {
      // Surface a structured timeout error instead of throwing
      return {
        'success': false,
        'error': 'Network timeout',
      };
    } catch (e) {
      // Generic network or parsing error
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get user's vehicles
  static Future<List<Map<String, dynamic>>> getUserVehicles(int userId) async {
    try {
      final endpoint = '$url/lets_go/users/$userId/vehicles/';
      debugPrint('[VEHICLES] GET $endpoint');
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      debugPrint('[VEHICLES] status: ${response.statusCode}');
      // Avoid printing entire body if huge; log size
      debugPrint('[VEHICLES] body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          // API returned a raw list
          return List<Map<String, dynamic>>.from(data);
        }
        if (data is Map<String, dynamic>) {
          final list = data['vehicles'] ?? data['user_vehicles'] ?? data['data'];
          if (list is List) {
            return List<Map<String, dynamic>>.from(list);
          }
        }
        // Fallback: empty list
        return <Map<String, dynamic>>[];
      } else {
        // Try to extract server error message
        try {
          final err = json.decode(response.body);
          throw Exception('Failed to load user vehicles: ${err['error'] ?? response.statusCode}');
        } catch (_) {
          throw Exception('Failed to load user vehicles: ${response.statusCode}');
        }
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Create a new ride
  static Future<Map<String, dynamic>> createRide(
    Map<String, dynamic> rideData,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/create_trip/'),
        headers: _headers,
        body: json.encode(rideData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(
            'Ride creation failed: ${data['error'] ?? 'Unknown error'}',
          );
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          'Ride creation failed: ${errorData['error'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Search rides with filters
  static Future<List<Map<String, dynamic>>> searchRides({
    String? origin,
    String? destination,
    DateTime? date,
    int? minSeats,
    double? maxPrice,
    String? genderPreference,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (origin != null) queryParams['origin'] = origin;
      if (destination != null) queryParams['destination'] = destination;
      if (date != null) {
        queryParams['date'] = date.toIso8601String().split('T')[0];
      }
      if (minSeats != null) queryParams['min_seats'] = minSeats.toString();
      if (maxPrice != null) queryParams['max_price'] = maxPrice.toString();
      if (genderPreference != null) {
        queryParams['gender_preference'] = genderPreference;
      }

      final uri = Uri.parse(
        '$url/lets_go/rides/search/',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['rides'] ?? []);
      } else {
        throw Exception('Failed to search rides: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> searchTrips({
    int? userId,
    int? fromStopId,
    int? toStopId,
    String? from,
    String? to,
    DateTime? date,
    int? minSeats,
    double? maxPrice,
    String? genderPreference,
    bool? negotiable,
    String? timeFrom,
    String? timeTo,
    String? sort,
    int? limit,
    int? offset,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (userId != null && userId > 0) queryParams['user_id'] = userId.toString();
      if (fromStopId != null && fromStopId > 0) queryParams['from_stop_id'] = fromStopId.toString();
      if (toStopId != null && toStopId > 0) queryParams['to_stop_id'] = toStopId.toString();
      if (from != null && from.trim().isNotEmpty) queryParams['from'] = from.trim();
      if (to != null && to.trim().isNotEmpty) queryParams['to'] = to.trim();
      if (date != null) queryParams['date'] = date.toIso8601String().split('T')[0];
      if (minSeats != null) queryParams['min_seats'] = minSeats.toString();
      if (maxPrice != null) queryParams['max_price'] = maxPrice.toString();
      if (genderPreference != null && genderPreference.trim().isNotEmpty) {
        queryParams['gender_preference'] = genderPreference.trim();
      }
      if (negotiable != null) queryParams['negotiable'] = negotiable.toString();
      if (timeFrom != null && timeFrom.trim().isNotEmpty) queryParams['time_from'] = timeFrom.trim();
      if (timeTo != null && timeTo.trim().isNotEmpty) queryParams['time_to'] = timeTo.trim();
      if (sort != null && sort.trim().isNotEmpty) queryParams['sort'] = sort.trim();
      if (limit != null) queryParams['limit'] = limit.toString();
      if (offset != null) queryParams['offset'] = offset.toString();

      final uri = Uri.parse(
        '$url/lets_go/trips/search/',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['trips'] ?? []);
      }

      throw Exception('Failed to search trips: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> suggestStops({
    String? query,
    double? lat,
    double? lng,
    double? radiusKm,
    int? limit,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (query != null && query.trim().isNotEmpty) queryParams['q'] = query.trim();
      if (lat != null) queryParams['lat'] = lat.toString();
      if (lng != null) queryParams['lng'] = lng.toString();
      if (radiusKm != null) queryParams['radius_km'] = radiusKm.toString();
      if (limit != null) queryParams['limit'] = limit.toString();

      final uri = Uri.parse(
        '$url/lets_go/stops/suggest/',
      ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['stops'] ?? []);
      }

      throw Exception('Failed to suggest stops: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Update user profile
  static Future<Map<String, dynamic>> updateUserProfile(
    String userId,
    Map<String, dynamic> userData,
  ) async {
    try {
      final data = await updateUserProfileWithVerification(userId, userData);
      final user = data['user'];
      if (user is Map<String, dynamic>) return user;
      return {};
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> updateUserProfileWithVerification(
    String userId,
    Map<String, dynamic> userData,
  ) async {
    try {
      final cleaned = <String, dynamic>{};
      userData.forEach((k, v) {
        if (v == null) return;
        if (v is String) {
          final s = v.trim();
          if (s.isEmpty) return;
          if (s.toLowerCase() == 'null') return;
          cleaned[k] = s;
          return;
        }
        cleaned[k] = v;
      });

      final response = await http.put(
        Uri.parse('$url/lets_go/users/$userId/'),
        headers: _headers,
        body: json.encode(cleaned),
      );

      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) {
          return {
            'success': decoded.containsKey('success') ? decoded['success'] : true,
            ...decoded,
          };
        }
        return {'success': true};
      }

      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to update profile',
          if (decoded.containsKey('code')) 'code': decoded['code'],
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }

      return {
        'success': false,
        'error': 'Failed to update user profile',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> createUserVehicle(
    int userId,
    Map<String, dynamic> vehicleData,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/users/$userId/vehicles/'),
        headers: _headers,
        body: json.encode(vehicleData),
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to create vehicle',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to create vehicle',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateVehicle(
    int vehicleId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final allowNullKeys = <String>{
        'registration_date',
        'insurance_expiry',
        'seats',
      };

      final cleaned = <String, dynamic>{};
      updates.forEach((k, v) {
        if (v == null) {
          if (allowNullKeys.contains(k)) cleaned[k] = null;
          return;
        }
        if (v is String) {
          final s = v.trim();
          if (s.isEmpty) return;
          if (s.toLowerCase() == 'null') return;
          cleaned[k] = s;
          return;
        }
        cleaned[k] = v;
      });

      final response = await http.patch(
        Uri.parse('$url/lets_go/vehicles/$vehicleId/'),
        headers: _headers,
        body: json.encode(cleaned),
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to update vehicle',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to update vehicle',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> deleteVehicle(int vehicleId) async {
    try {
      final response = await http.delete(
        Uri.parse('$url/lets_go/vehicles/$vehicleId/'),
        headers: _headers,
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode == 200 || response.statusCode == 204) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to delete vehicle',
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to delete vehicle',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> sendProfileContactChangeOtp(
    int userId, {
    required String which,
    required String value,
    bool resend = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/users/$userId/contact-change/send-otp/'),
        headers: _headers,
        body: json.encode({
          'which': which,
          'value': value,
          'resend': resend,
        }),
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to send OTP',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to send OTP',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyProfileContactChangeOtp(
    int userId, {
    required String which,
    required String value,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/users/$userId/contact-change/verify-otp/'),
        headers: _headers,
        body: json.encode({
          'which': which,
          'value': value,
          'otp': otp,
        }),
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to verify OTP',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to verify OTP',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getEmergencyContact(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$url/lets_go/users/$userId/emergency-contact/'),
        headers: _headers,
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to load emergency contact',
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to load emergency contact',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateEmergencyContact(
    int userId, {
    required String name,
    required String relation,
    required String email,
    required String phoneNo,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$url/lets_go/users/$userId/emergency-contact/'),
        headers: _headers,
        body: json.encode({
          'name': name,
          'relation': relation,
          'email': email,
          'phone_no': phoneNo,
        }),
      );
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};
      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to update emergency contact',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to update emergency contact',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadUserAccountQr(
    int userId, {
    required File file,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/accountqr/upload/');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to upload account QR',
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to upload account QR',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadVehicleImages(
    int userId, {
    required String plateNumber,
    File? photoFront,
    File? photoBack,
    File? documentsImage,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/vehicle-images/upload/');
      final request = http.MultipartRequest('POST', uri);

      request.fields['plate_number'] = plateNumber.trim().toUpperCase();

      if (photoFront != null) {
        request.files.add(await http.MultipartFile.fromPath('photo_front', photoFront.path));
      }
      if (photoBack != null) {
        request.files.add(await http.MultipartFile.fromPath('photo_back', photoBack.path));
      }
      if (documentsImage != null) {
        request.files.add(await http.MultipartFile.fromPath('documents_image', documentsImage.path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to upload vehicle images',
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to upload vehicle images',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadUserCnic(
    int userId, {
    String? cnicNo,
    File? front,
    File? back,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/cnic/upload/');
      final request = http.MultipartRequest('POST', uri);

      if (cnicNo != null && cnicNo.trim().isNotEmpty) {
        request.fields['cnic_no'] = cnicNo.trim();
      }
      if (front != null) {
        request.files.add(await http.MultipartFile.fromPath('front', front.path));
      }
      if (back != null) {
        request.files.add(await http.MultipartFile.fromPath('back', back.path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to update CNIC',
          if (decoded.containsKey('code')) 'code': decoded['code'],
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to update CNIC',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadUserDrivingLicense(
    int userId, {
    String? licenseNo,
    File? front,
    File? back,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/driving-license/upload/');
      final request = http.MultipartRequest('POST', uri);

      if (licenseNo != null && licenseNo.trim().isNotEmpty) {
        request.fields['driving_license_no'] = licenseNo.trim();
      }
      if (front != null) {
        request.files.add(await http.MultipartFile.fromPath('front', front.path));
      }
      if (back != null) {
        request.files.add(await http.MultipartFile.fromPath('back', back.path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to update driving license',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to update driving license',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadUserPhotos(
    int userId, {
    File? profilePhoto,
    File? livePhoto,
  }) async {
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/photos/upload/');
      final request = http.MultipartRequest('POST', uri);

      if (profilePhoto != null) {
        request.files.add(await http.MultipartFile.fromPath('profile_photo', profilePhoto.path));
      }
      if (livePhoto != null) {
        request.files.add(await http.MultipartFile.fromPath('live_photo', livePhoto.path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = response.body;
      final decoded = body.isNotEmpty ? json.decode(body) : {};

      if (response.statusCode == 200) {
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true};
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'error': decoded['error'] ?? 'Failed to update photos',
          if (decoded.containsKey('fields')) 'fields': decoded['fields'],
          'status': response.statusCode,
        };
      }
      return {
        'success': false,
        'error': 'Failed to update photos',
        'status': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Get user's created rides
  static Future<List<Map<String, dynamic>>> getUserRides(String userId) async {
    try {
      final uri = Uri.parse('$url/lets_go/users/$userId/rides/')
          .replace(queryParameters: {
        'mode': 'summary',
      });
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['rides'] ?? []);
      } else {
        throw Exception('Failed to load user rides: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Cancel a booking request
  static Future<Map<String, dynamic>> cancelBooking(
    int bookingId,
    String reason,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/bookings/$bookingId/cancel/'),
        headers: _headers,
        body: json.encode({'reason': reason}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          'Failed to cancel booking: ${errorData['error'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Update a trip
  static Future<Map<String, dynamic>> updateTrip(
    String tripId,
    Map<String, dynamic> tripData,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$url/lets_go/trips/$tripId/update/'),
        headers: _headers,
        body: json.encode(tripData),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
          'Failed to update trip: ${errorData['error'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Delete a trip
  static Future<Map<String, dynamic>> deleteTrip(String tripId) async {
    try {
      final response = await http.delete(
        Uri.parse('$url/lets_go/trips/$tripId/delete/'),
        headers: _headers,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true, 'message': 'Trip deleted successfully'};
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to delete trip',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Cancel a trip
  static Future<Map<String, dynamic>> cancelTrip(
    String tripId, {
    String? reason,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/trips/$tripId/cancel/'),
        headers: _headers,
        body: json.encode({'reason': reason ?? 'Cancelled by driver'}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? 'Failed to cancel trip',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Create a new route with map coordinates
  static Future<Map<String, dynamic>> createRoute(
    Map<String, dynamic> routeData,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/create_route/'),
        headers: _headers,
        body: jsonEncode(routeData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data;
      } else {
        throw Exception('Failed to create route: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> createTrip({
    required String routeId,
    required int vehicleId,
    required int driverId,
    required String tripDate,
    required String departureTime,
    required int totalSeats,
    required int customPrice,
    required Map<String, dynamic> fareCalculation,
    Map<String, dynamic>? autoFareCalculation,
    bool? hasManualAdjustments,
    String? genderPreference,
    String? notes,
    bool? isPriceNegotiable,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/create_trip/'),
        headers: _headers,
        body: jsonEncode({
          'route_id': routeId,
          'vehicle_id': vehicleId,
          'driver_id': driverId,
          'trip_date': tripDate,
          'departure_time': departureTime,
          'total_seats': totalSeats,
          'custom_price': customPrice,
          'fare_calculation':
              fareCalculation, // Send complete frontend calculation
          'stop_breakdown':
              fareCalculation['stop_breakdown'], // Explicitly send stop breakdown
          if (autoFareCalculation != null) 'auto_fare_calculation': autoFareCalculation,
          if (hasManualAdjustments != null) 'has_manual_adjustments': hasManualAdjustments,
          'gender_preference':
              genderPreference ?? 'Any', // Ensure explicit string
          'notes': notes ?? '',
          'is_negotiable': isPriceNegotiable ?? true,
        }),
      );

      final String body = response.body;
      Map<String, dynamic>? data;
      try {
        final decoded = json.decode(body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        data = null;
      }

      // Success path
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data != null) {
          if (data['success'] == true) {
            return data;
          }
          return {
            'success': false,
            'error': data['error'] ?? 'Trip creation failed',
            'status': response.statusCode,
          };
        }
        return {
          'success': false,
          'error': 'Trip creation failed: empty response',
          'status': response.statusCode,
        };
      }

      // Validation / known backend errors (e.g. 400 for <15 minute rule)
      if (response.statusCode >= 400 && response.statusCode < 500) {
        final message = data != null
            ? (data['error'] ?? 'Request rejected by server')
            : 'Request rejected by server (status ${response.statusCode})';
        return {
          'success': false,
          'error': message,
          'status': response.statusCode,
        };
      }

      // Other server or network issues
      return {
        'success': false,
        'error': 'Failed to create trip: HTTP ${response.statusCode}',
        'status': response.statusCode,
      };
    } catch (e) {
      // Only true network / decoding failures should reach here
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> calculateFare({
    required String routeId,
    required int vehicleId,
    required String departureTime,
    required int totalSeats,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$url/lets_go/calculate_fare/'),
        headers: _headers,
        body: jsonEncode({
          'route_id': routeId,
          'vehicle_id': vehicleId,
          'departure_time': departureTime,
          'total_seats': totalSeats,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(
            'Fare calculation failed: ${data['error'] ?? 'Unknown error'}',
          );
        }
      } else {
        throw Exception('Failed to calculate fare: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Cancel a ride
  static Future<void> cancelRide(int rideId) async {
    try {
      final response = await http.delete(
        Uri.parse('$url/lets_go/rides/$rideId/'),
        headers: _headers,
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to cancel ride: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> startTripRide({
    required String tripId,
    required int driverId,
  }) async {
    final endpoint = '$url/lets_go/trips/$tripId/start-ride/';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode({'driver_id': driverId}),
        )
        .timeout(const Duration(seconds: 12));

    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getBookingPaymentDetails({
    required int bookingId,
    required String role,
    required int userId,
  }) async {
    final endpoint = '$url/lets_go/bookings/$bookingId/payment/';
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {
        'role': role,
        'user_id': userId.toString(),
      },
    );

    final response = await http
        .get(
          uri,
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> submitBookingPayment({
    required int bookingId,
    required int passengerId,
    required double driverRating,
    String? driverFeedback,
    File? receiptFile,
    bool paidByCash = false,
  }) async {
    final endpoint = '$url/lets_go/bookings/$bookingId/payment/submit/';
    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.fields['passenger_id'] = passengerId.toString();
    request.fields['driver_rating'] = driverRating.toString();
    if (driverFeedback != null && driverFeedback.trim().isNotEmpty) {
      request.fields['driver_feedback'] = driverFeedback.trim();
    }
    request.fields['payment_method'] = paidByCash ? 'CASH' : 'BANK_TRANSFER';
    if (!paidByCash) {
      if (receiptFile == null) {
        throw Exception('Receipt file is required unless paid by cash');
      }
      request.files.add(await http.MultipartFile.fromPath('receipt', receiptFile.path));
    }
    request.headers['Accept'] = 'application/json';

    final streamed = await request.send().timeout(const Duration(seconds: 24));
    final body = await streamed.stream.bytesToString();
    return json.decode(body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> confirmBookingPayment({
    required int bookingId,
    required int driverId,
    required double passengerRating,
    String? passengerFeedback,
  }) async {
    final endpoint = '$url/lets_go/bookings/$bookingId/payment/confirm/';
    final payload = <String, dynamic>{
      'driver_id': driverId,
      'passenger_rating': passengerRating,
      if (passengerFeedback != null && passengerFeedback.trim().isNotEmpty)
        'passenger_feedback': passengerFeedback.trim(),
      'received': true,
    };

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: 12));
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getTripPayments({
    required String tripId,
    required int driverId,
  }) async {
    final endpoint = '$url/lets_go/trips/$tripId/payments/';
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {
        'driver_id': driverId.toString(),
      },
    );

    final response = await http
        .get(
          uri,
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> completeTripRide({
    required String tripId,
    required int driverId,
  }) async {
    final endpoint = '$url/lets_go/trips/$tripId/complete-ride/';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode({'driver_id': driverId}),
        )
        .timeout(const Duration(seconds: 12));

    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getLiveLocationAuthorized({
    required String tripId,
    required String role,
    required int userId,
    int? bookingId,
  }) async {
    final endpoint = '$url/lets_go/trips/$tripId/location/';
    final uri = Uri.parse(endpoint);
    final qp = <String, String>{
      'role': role,
      'user_id': userId.toString(),
      if (bookingId != null) 'booking_id': bookingId.toString(),
    };
    final response = await http
        .get(
          uri.replace(queryParameters: qp),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));

    Map<String, dynamic> parsed = <String, dynamic>{};
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        parsed = decoded;
      }
    } catch (_) {
      parsed = <String, dynamic>{
        'error': response.body,
      };
    }

    if (response.statusCode == 200) {
      // Normalize success for 200 even if backend doesn't include 'success'
      if (!parsed.containsKey('success')) {
        parsed['success'] = true;
      }
      return parsed;
    }

    // For non-200 responses, preserve any backend error while attaching status.
    return <String, dynamic>{
      ...parsed,
      'success': false,
      'status': response.statusCode,
      'error': (parsed['error'] ?? 'Request failed').toString(),
    };
  }

  static Future<Map<String, dynamic>> startBookingRide({
    required int bookingId,
    required int passengerId,
  }) async {
    final endpoint = '$url/lets_go/bookings/$bookingId/start-ride/';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode({'passenger_id': passengerId}),
        )
        .timeout(const Duration(seconds: 12));

    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> markBookingDroppedOff({
    required int bookingId,
    required int passengerId,
  }) async {
    final endpoint = '$url/lets_go/bookings/$bookingId/dropped-off/';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode({'passenger_id': passengerId}),
        )
        .timeout(const Duration(seconds: 12));

    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> driverMarkReachedPickup({
    required int bookingId,
    required int driverId,
  }) async {
    final endpoint = '$url/lets_go/bookings/$bookingId/driver-reached-pickup/';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode({'driver_id': driverId}),
        )
        .timeout(const Duration(seconds: 12));
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> driverMarkReachedDropoff({
    required int bookingId,
    required int driverId,
  }) async {
    final endpoint = '$url/lets_go/bookings/$bookingId/driver-reached-dropoff/';
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode({'driver_id': driverId}),
        )
        .timeout(const Duration(seconds: 12));
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<void> updateLiveLocation({
    required String tripId,
    required int userId,
    required String role,
    int? bookingId,
    required double lat,
    required double lng,
    double? speed,
  }) async {
    final endpoint = '$url/lets_go/trips/$tripId/location/update/';
    final body = <String, dynamic>{
      'user_id': userId,
      'role': role,
      'lat': lat,
      'lng': lng,
      if (bookingId != null) 'booking_id': bookingId,
      if (speed != null) 'speed': speed,
    };

    final resp = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('updateLiveLocation failed: ${resp.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> sendSosIncident({
    required int userId,
    required String tripId,
    required bool isDriver,
    int? bookingId,
    required double lat,
    required double lng,
    double? accuracy,
    String? note,
  }) async {
    try {
      final endpoint = '$url/lets_go/incidents/sos/';
      final body = <String, dynamic>{
        'user_id': userId,
        'trip_id': tripId,
        'role': isDriver ? 'driver' : 'passenger',
        if (!isDriver && bookingId != null) 'booking_id': bookingId,
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      };

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> parsed = <String, dynamic>{};
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          parsed = decoded;
        }
      } catch (_) {
        parsed = <String, dynamic>{'error': response.body};
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!parsed.containsKey('success')) {
          parsed['success'] = true;
        }
        if (!parsed.containsKey('status')) {
          parsed['status'] = response.statusCode;
        }
        return parsed;
      }

      return <String, dynamic>{
        ...parsed,
        'success': false,
        'status': response.statusCode,
        'error': (parsed['error'] ?? 'Request failed').toString(),
      };
    } on TimeoutException {
      return {'success': false, 'error': 'Network timeout'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> createTripShareLink({
    required String tripId,
    required bool isDriver,
    int? bookingId,
  }) async {
    try {
      final endpoint = '$url/lets_go/trips/$tripId/share/';
      final body = <String, dynamic>{
        'role': isDriver ? 'driver' : 'passenger',
        if (!isDriver && bookingId != null) 'booking_id': bookingId,
      };

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 12));

      Map<String, dynamic> parsed = <String, dynamic>{};
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          parsed = decoded;
        }
      } catch (_) {
        parsed = <String, dynamic>{'error': response.body};
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!parsed.containsKey('success')) {
          parsed['success'] = true;
        }
        return parsed;
      }

      return <String, dynamic>{
        ...parsed,
        'success': false,
        'status': response.statusCode,
        'error': (parsed['error'] ?? 'Request failed').toString(),
      };
    } on TimeoutException {
      return {'success': false, 'error': 'Network timeout'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getLiveLocation(String tripId) async {
    final endpoint = '$url/lets_go/trips/$tripId/location/';
    final uri = Uri.parse(endpoint);
    final qp = <String, String>{};
    final requestUri = qp.isEmpty ? uri : uri.replace(queryParameters: qp);
    final response = await http
        .get(
          requestUri,
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));

    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> generatePickupCode({
    required String tripId,
    required int bookingId,
    required int driverId,
    double? driverLat,
    double? driverLng,
  }) async {
    final endpoint = '$url/lets_go/trips/$tripId/bookings/$bookingId/pickup-code/';
    final body = <String, dynamic>{
      'driver_id': driverId,
      if (driverLat != null) 'driver_lat': driverLat,
      if (driverLng != null) 'driver_lng': driverLng,
    };

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 12));

    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyPickupCode({
    required int bookingId,
    required int passengerId,
    required String code,
    double? passengerLat,
    double? passengerLng,
  }) async {
    final endpoint = '$url/lets_go/pickup-code/verify/';
    final body = <String, dynamic>{
      'booking_id': bookingId,
      'passenger_id': passengerId,
      'code': code,
      if (passengerLat != null) 'passenger_lat': passengerLat,
      if (passengerLng != null) 'passenger_lng': passengerLng,
    };

    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: _headers,
          body: json.encode(body),
        )
        .timeout(const Duration(seconds: 12));

    return json.decode(response.body) as Map<String, dynamic>;
  }
}

/// Example usage of the API service with fare calculation
class BookingService {
  /// Get complete booking data with fare calculation
  static Future<Map<String, dynamic>> getBookingData({
    required int routeId,
    required int tripId,
    required int fromStopOrder,
    required int toStopOrder,
    required int numberOfSeats,
  }) async {
    try {
      // Get route data with fare matrix
      final routeData = await ApiService.getRouteWithFareMatrix(routeId);

      // Get trip data
      final tripData = await ApiService.getTripDetails(tripId);

      // Calculate fare using Flutter calculator
      final fareBreakdown = FareCalculator.calculateBookingFare(
        fromStopOrder: fromStopOrder,
        toStopOrder: toStopOrder,
        numberOfSeats: numberOfSeats,
        fareMatrix: routeData['fare_matrix'],
        bookingTime: DateTime.now(),
        baseFareMultiplier: 1.0,
        seatDiscount: 0.0, // No discount
      );

      return {
        'route_data': routeData,
        'trip_data': tripData,
        'fare_breakdown': fareBreakdown,
        'booking_summary': {
          'from_stop':
              routeData['route_stops'].firstWhere(
                (stop) => stop['stop_order'] == fromStopOrder,
              )['stop_name'],
          'to_stop':
              routeData['route_stops'].firstWhere(
                (stop) => stop['stop_order'] == toStopOrder,
              )['stop_name'],
          'number_of_seats': numberOfSeats,
          'total_fare': fareBreakdown['total_fare'],
          'is_peak_hour': fareBreakdown['is_peak_hour'],
        },
      };
    } catch (e) {
      throw Exception('Failed to get booking data: $e');
    }
  }

  /// Create booking with fare validation
  static Future<Map<String, dynamic>> createBookingWithValidation({
    required int tripId,
    required int fromStopOrder,
    required int toStopOrder,
    required int numberOfSeats,
    required List<int> selectedSeats,
    required Map<String, dynamic> fareBreakdown,
  }) async {
    try {
      // Validate fare calculation on client side
      final bookingData = {
        'trip_id': tripId,
        'from_stop_order': fromStopOrder,
        'to_stop_order': toStopOrder,
        'number_of_seats': numberOfSeats,
        'selected_seats': selectedSeats,
        'total_fare': fareBreakdown['total_fare'],
        'fare_breakdown': fareBreakdown,
        'booking_time': DateTime.now().toIso8601String(),
      };

      // Send to server
      final result = await ApiService.createBooking(bookingData);

      return {
        'success': true,
        'booking_id': result['booking_id'],
        'message': 'Booking created successfully',
        'data': result,
      };
    } catch (e) {
      return {'success': false, 'message': 'Booking failed: $e', 'data': null};
    }
  }

  /// Calculate dynamic fare and duration for selected stops using TripStopBreakdown data
  static Future<Map<String, dynamic>> calculateDynamicFare({
    required String tripId,
    required int fromStopOrder,
    required int toStopOrder,
    required int numberOfSeats,
  }) async {
    try {
      debugPrint('=== CALCULATE DYNAMIC FARE DEBUG ===');
      debugPrint(
        'Trip ID: $tripId, From: $fromStopOrder, To: $toStopOrder, Seats: $numberOfSeats',
      );

      // Get trip details to access stop_breakdown data
      final tripData = await ApiService.getRideBookingDetails(tripId);
      final stopBreakdown = tripData['stop_breakdown'] as List<dynamic>? ?? [];

      debugPrint('Found ${stopBreakdown.length} stop breakdown records');

      if (stopBreakdown.isEmpty) {
        debugPrint(
          'No stop breakdown data found, falling back to route fare matrix',
        );
        return _calculateFareFromMatrix(
          tripId,
          fromStopOrder,
          toStopOrder,
          numberOfSeats,
        );
      }

      // Calculate fare and duration from TripStopBreakdown data
      double totalFare = 0.0;
      int totalDuration = 0;
      double totalDistance = 0.0;
      List<Map<String, dynamic>> fareBreakdown = [];

      // Sum up segments between selected stops
      for (final breakdown in stopBreakdown) {
        final segmentFromOrder = breakdown['from_stop_order'] as int;
        final segmentToOrder = breakdown['to_stop_order'] as int;

        // Check if this segment is within our selected range
        if (segmentFromOrder >= fromStopOrder &&
            segmentToOrder <= toStopOrder) {
          final segmentPrice = (breakdown['price'] as num?)?.toDouble() ?? 0.0;
          final segmentDuration = breakdown['duration_minutes'] as int? ?? 0;
          final segmentDistance =
              (breakdown['distance'] as num?)?.toDouble() ?? 0.0;

          totalFare += segmentPrice;
          totalDuration += segmentDuration;
          totalDistance += segmentDistance;

          fareBreakdown.add({
            'from_stop': segmentFromOrder,
            'to_stop': segmentToOrder,
            'fare': segmentPrice,
            'duration': segmentDuration,
            'distance': segmentDistance,
          });

          debugPrint(
            'Added segment $segmentFromOrder->$segmentToOrder: ₨$segmentPrice, ${segmentDuration}min, ${segmentDistance}km',
          );
        }
      }

      debugPrint(
        'Calculated totals: ₨$totalFare, ${totalDuration}min, ${totalDistance}km',
      );

      // Apply number of seats multiplier to fare only
      double finalFare = totalFare * numberOfSeats;

      return {
        'success': true,
        'fare_calculation': {
          'base_fare_per_seat': totalFare,
          'number_of_seats': numberOfSeats,
          'total_fare': finalFare,
          'total_duration_minutes': totalDuration,
          'total_distance_km': totalDistance,
          'from_stop_order': fromStopOrder,
          'to_stop_order': toStopOrder,
          'fare_breakdown': fareBreakdown,
        },
        'message': 'Dynamic fare and duration calculated successfully',
      };
    } catch (e) {
      debugPrint('Error in calculateDynamicFare: $e');
      return {
        'success': false,
        'message': 'Failed to calculate dynamic fare: $e',
        'fare_calculation': null,
      };
    }
  }

  /// Fallback method using fare matrix when stop breakdown is not available
  static Future<Map<String, dynamic>> _calculateFareFromMatrix(
    String tripId,
    int fromStopOrder,
    int toStopOrder,
    int numberOfSeats,
  ) async {
    try {
      final tripData = await ApiService.getRideBookingDetails(tripId);
      final routeId = tripData['route']['id'];

      final routeData = await ApiService.getRouteWithFareMatrix(routeId);
      final fareMatrix = routeData['fare_matrix'] as List<dynamic>;

      double totalFare = 0.0;
      List<Map<String, dynamic>> fareBreakdown = [];

      for (int i = fromStopOrder; i < toStopOrder; i++) {
        final fareEntry = fareMatrix.firstWhere(
          (item) => item['from_stop'] == i && item['to_stop'] == i + 1,
          orElse: () => null,
        );

        if (fareEntry != null) {
          double segmentFare = (fareEntry['fare'] ?? 0.0).toDouble();
          totalFare += segmentFare;

          fareBreakdown.add({
            'from_stop': i,
            'to_stop': i + 1,
            'fare': segmentFare,
          });
        }
      }

      double finalFare = totalFare * numberOfSeats;

      return {
        'success': true,
        'fare_calculation': {
          'base_fare_per_seat': totalFare,
          'number_of_seats': numberOfSeats,
          'total_fare': finalFare,
          'from_stop_order': fromStopOrder,
          'to_stop_order': toStopOrder,
          'fare_breakdown': fareBreakdown,
          // Note: No duration available from fare matrix
        },
        'message':
            'Dynamic fare calculated from fare matrix (no duration data)',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to calculate fare from matrix: $e',
        'fare_calculation': null,
      };
    }
  }

  
}
