import 'package:latlong2/latlong.dart';

import 'map_util.dart';

class ActualPathRules {
  static bool polylineCoversStop(
    List<LatLng> poly,
    LatLng stop, {
    double thresholdMeters = 150,
  }) {
    if (poly.isEmpty) return false;
    for (final p in poly) {
      final d = MapUtil.calculateDistanceMeters(p, stop);
      if (d <= thresholdMeters) return true;
    }
    return false;
  }

  static bool validateActualPathCoversAllStops(
    List<LatLng> actual,
    List<LatLng> stops, {
    double thresholdMeters = 150,
  }) {
    if (actual.length < 2) return false;
    if (stops.length < 2) return false;

    for (final s in stops) {
      if (!polylineCoversStop(actual, s, thresholdMeters: thresholdMeters)) {
        return false;
      }
    }
    return true;
  }

  static bool sameLatLng(LatLng a, LatLng b, {double epsilon = 1e-7}) {
    return (a.latitude - b.latitude).abs() <= epsilon &&
        (a.longitude - b.longitude).abs() <= epsilon;
  }

  static bool startsWithStops(List<LatLng> full, List<LatLng> prefix, {double epsilon = 1e-7}) {
    if (prefix.isEmpty) return true;
    if (full.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (!sameLatLng(full[i], prefix[i], epsilon: epsilon)) return false;
    }
    return true;
  }

  static bool shouldExtendActualPathAppendOnly({
    required List<LatLng> currentStops,
    required List<LatLng> initialStopsSnapshot,
  }) {
    if (initialStopsSnapshot.length < 2) return false;
    if (currentStops.length <= initialStopsSnapshot.length) return false;
    if (!startsWithStops(currentStops, initialStopsSnapshot)) return false;
    return true;
  }
}
