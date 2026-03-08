import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineLocationQueue {
  static const String _key = 'offline_location_queue_v1';
  static const int _maxItems = 800;

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static Future<List<Map<String, dynamic>>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }

  static Future<void> enqueue({
    required String tripId,
    required int userId,
    required String role,
    int? bookingId,
    required double lat,
    required double lng,
    double? speed,
    int? recordedAtMs,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final item = <String, dynamic>{
      't': tripId,
      'u': userId,
      'r': role,
      if (bookingId != null) 'b': bookingId,
      'lat': lat,
      'lng': lng,
      if (speed != null) 's': speed,
      'ts': recordedAtMs ?? nowMs,
    };

    final items = await _load();
    items.add(item);

    if (items.length > _maxItems) {
      final keepFrom = items.length - _maxItems;
      items.removeRange(0, keepFrom);
    }

    await _save(items);
  }

  static Future<int> count() async {
    final items = await _load();
    return items.length;
  }

  static Future<List<Map<String, dynamic>>> peekBatch({
    required String tripId,
    required int userId,
    required String role,
    int? bookingId,
    int limit = 25,
  }) async {
    final items = await _load();
    final filtered = <Map<String, dynamic>>[];

    for (final it in items) {
      if ((it['t'] ?? '').toString() != tripId) continue;
      if (_asInt(it['u']) != userId) continue;
      if ((it['r'] ?? '').toString() != role) continue;

      final b = it.containsKey('b') ? _asInt(it['b']) : 0;
      final expectedB = bookingId ?? 0;
      if (b != expectedB) continue;

      final lat = _asDouble(it['lat']);
      final lng = _asDouble(it['lng']);
      if (lat == null || lng == null) continue;

      filtered.add(it);
      if (filtered.length >= limit) break;
    }

    filtered.sort((a, b) => _asInt(a['ts']).compareTo(_asInt(b['ts'])));
    return filtered;
  }

  static Future<void> dropBatch({
    required String tripId,
    required int userId,
    required String role,
    int? bookingId,
    required int count,
  }) async {
    if (count <= 0) return;
    final items = await _load();
    final out = <Map<String, dynamic>>[];
    int removed = 0;
    final expectedB = bookingId ?? 0;

    for (final it in items) {
      final match = (it['t'] ?? '').toString() == tripId &&
          _asInt(it['u']) == userId &&
          (it['r'] ?? '').toString() == role &&
          (it.containsKey('b') ? _asInt(it['b']) : 0) == expectedB;

      if (match && removed < count) {
        removed += 1;
        continue;
      }
      out.add(it);
    }

    await _save(out);
  }

  static Future<void> clearAll() async {
    await _save(<Map<String, dynamic>>[]);
  }
}
