import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  static const _kSessionUser = 'session_user';
  static const _kLoggedInUserId = 'logged_in_user_id';
  static const _kSessionCreatedAt = 'session_created_at';

  /// Save the logged-in user's profile to local storage for auto-login.
  static Future<void> save(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = userData['id']?.toString();
    await prefs.setString(_kSessionUser, jsonEncode(userData));
    if (userId != null) {
      await prefs.setString(_kLoggedInUserId, userId);
    }
    await prefs.setString(_kSessionCreatedAt, DateTime.now().toIso8601String());
  }

  /// Load the stored user session if present. Returns null if missing.
  static Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kSessionUser);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Clear the stored session (use on logout).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionUser);
    await prefs.remove(_kLoggedInUserId);
    await prefs.remove(_kSessionCreatedAt);
  }
}
