import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:lets_go/utils/actual_path_rules.dart';

void main() {
  group('ActualPathRules.validateActualPathCoversAllStops', () {
    test('returns true when each stop is within threshold of some actual point', () {
      final actual = <LatLng>[
        const LatLng(33.0, 73.0),
        const LatLng(33.001, 73.001),
        const LatLng(33.002, 73.002),
      ];
      final stops = <LatLng>[
        const LatLng(33.0, 73.0),
        const LatLng(33.002, 73.002),
      ];

      final ok = ActualPathRules.validateActualPathCoversAllStops(
        actual,
        stops,
        thresholdMeters: 200,
      );
      expect(ok, isTrue);
    });

    test('returns false when any stop is not covered', () {
      final actual = <LatLng>[
        const LatLng(33.0, 73.0),
        const LatLng(33.001, 73.001),
      ];
      final stops = <LatLng>[
        const LatLng(33.0, 73.0),
        const LatLng(34.0, 74.0),
      ];

      final ok = ActualPathRules.validateActualPathCoversAllStops(
        actual,
        stops,
        thresholdMeters: 150,
      );
      expect(ok, isFalse);
    });

    test('returns false when actual polyline has < 2 points', () {
      final ok = ActualPathRules.validateActualPathCoversAllStops(
        [const LatLng(33.0, 73.0)],
        [const LatLng(33.0, 73.0), const LatLng(33.001, 73.001)],
      );
      expect(ok, isFalse);
    });

    test('returns false when stops has < 2 points', () {
      final ok = ActualPathRules.validateActualPathCoversAllStops(
        [const LatLng(33.0, 73.0), const LatLng(33.001, 73.001)],
        [const LatLng(33.0, 73.0)],
      );
      expect(ok, isFalse);
    });
  });

  group('ActualPathRules.shouldExtendActualPathAppendOnly', () {
    test('returns true when current stops start with initial snapshot and new stops appended', () {
      final initial = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];
      final current = <LatLng>[
        const LatLng(33.0, 73.0),
        const LatLng(33.1, 73.1),
        const LatLng(33.2, 73.2),
      ];

      final ok = ActualPathRules.shouldExtendActualPathAppendOnly(
        currentStops: current,
        initialStopsSnapshot: initial,
      );
      expect(ok, isTrue);
    });

    test('returns false when a stop is deleted', () {
      final initial = <LatLng>[
        const LatLng(33.0, 73.0),
        const LatLng(33.1, 73.1),
        const LatLng(33.2, 73.2),
      ];
      final current = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];

      final ok = ActualPathRules.shouldExtendActualPathAppendOnly(
        currentStops: current,
        initialStopsSnapshot: initial,
      );
      expect(ok, isFalse);
    });

    test('returns false when order changes (no longer a prefix match)', () {
      final initial = <LatLng>[const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)];
      final current = <LatLng>[const LatLng(33.1, 73.1), const LatLng(33.0, 73.0), const LatLng(33.2, 73.2)];

      final ok = ActualPathRules.shouldExtendActualPathAppendOnly(
        currentStops: current,
        initialStopsSnapshot: initial,
      );
      expect(ok, isFalse);
    });
  });
}
