import 'package:intl/intl.dart';

class TimeFormat {
  static String amPmCompactFromDateTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayHour = h % 12 == 0 ? 12 : (h % 12);

    if (m == 0) {
      return '$displayHour$period';
    }

    final mm = m.toString().padLeft(2, '0');
    return '$displayHour:$mm$period';
  }

  static String amPmCompactFrom24hString(String? time) {
    final s = (time ?? '').trim();
    if (s.isEmpty) return 'N/A';

    try {
      final parts = s.split(':');
      if (parts.length < 2) return s;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : (hour % 12);

      if (minute == 0) {
        return '$displayHour$period';
      }

      final mm = minute.toString().padLeft(2, '0');
      return '$displayHour:$mm$period';
    } catch (_) {
      return s;
    }
  }

  static String dateWithTimeAmPm(DateTime dt) {
    final local = dt.toLocal();
    final date = DateFormat('MMM dd, yyyy').format(local);
    return '$date ${amPmCompactFromDateTime(local)}';
  }
}
