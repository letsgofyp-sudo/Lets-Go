import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:typed_data';

import 'package:lets_go/controllers/ride_posting_controllers/create_route_controller.dart';
import 'package:lets_go/screens/ride_posting_screens/create_route_screen.dart';

class _InMemoryTileProvider extends TileProvider {
  // 1x1 transparent PNG
  static final Uint8List _png = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_png);
  }
}

void main() {
  group('CreateRouteScreen actual path overlay', () {
    testWidgets('shows the overlay switch when actualRoutePoints are present', (tester) async {
      final ctrl = CreateRouteController();
      ctrl.loadExistingRouteData({
        'points': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'locationNames': ['A', 'B'],
        'routePoints': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'actualRoutePoints': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'preferActualPath': true,
      });
      ctrl.currentPosition = const LatLng(33.0, 73.0);
      ctrl.isLoading = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CreateRouteScreen(
            userData: const {'id': 1},
            existingRouteData: null,
            routeEditMode: true,
            controllerOverride: ctrl,
            skipInitSideEffects: true,
            tileLayerOverride: TileLayer(
              urlTemplate: 'about:blank',
              tileProvider: _InMemoryTileProvider(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Show actual path overlay'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('does not show the overlay switch when no actualRoutePoints', (tester) async {
      final ctrl = CreateRouteController();
      ctrl.loadExistingRouteData({
        'points': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
        'locationNames': ['A', 'B'],
        'routePoints': [const LatLng(33.0, 73.0), const LatLng(33.1, 73.1)],
      });
      ctrl.currentPosition = const LatLng(33.0, 73.0);
      ctrl.isLoading = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CreateRouteScreen(
            userData: const {'id': 1},
            routeEditMode: true,
            controllerOverride: ctrl,
            skipInitSideEffects: true,
            tileLayerOverride: TileLayer(
              urlTemplate: 'about:blank',
              tileProvider: _InMemoryTileProvider(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Show actual path overlay'), findsNothing);
    });
  });
}
