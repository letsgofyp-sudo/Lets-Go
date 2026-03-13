import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../controllers/post_bookings_controller/live_tracking_controller.dart';
import '../../services/api_service.dart';
import '../../services/live_tracking_session_manager.dart';
import '../../utils/image_utils.dart';
import '../../utils/map_util.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String tripId;
  final int currentUserId;
  final bool isDriver;
  final int? bookingId;

  const LiveTrackingScreen({
    super.key,
    required this.tripId,
    required this.currentUserId,
    required this.isDriver,
    this.bookingId,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  LiveTrackingController? controller;
  final TextEditingController _codeController = TextEditingController();
  final MapController _mapController = MapController();

  int? _lastCameraFitPointsCount;
  bool _cameraFitScheduled = false;

  Future<void> _showDriverPickupCodeFlow() async {
    if (!widget.isDriver) return;

    final controller = this.controller;
    if (controller == null) return;

    final list = controller.confirmedPassengerBookings;
    if (list.isEmpty) {
      return;
    }

    int? selectedBookingId;
    if (list.length == 1) {
      final id = list.first['booking_id'] ?? list.first['id'];
      selectedBookingId = int.tryParse(id?.toString() ?? '');
    } else {
      selectedBookingId = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final b in list)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        ((b['name'] ?? b['passenger_name'] ?? 'P').toString())
                            .trim()
                            .characters
                            .first
                            .toUpperCase(),
                      ),
                    ),
                    title: Text((b['name'] ?? b['passenger_name'] ?? 'Passenger').toString()),
                    subtitle: Text('Booking ${(b['booking_id'] ?? b['id']).toString()}'),
                    onTap: () {
                      final id = int.tryParse((b['booking_id'] ?? b['id']).toString());
                      Navigator.of(ctx).pop(id);
                    },
                  ),
              ],
            ),
          );
        },
      );
    }

    if (selectedBookingId == null) return;

    controller.setSelectedBookingId(selectedBookingId);
    await controller.generatePickupCode();

    if (!mounted) return;
    if (controller.activePickupCode == null) {
      final msg = controller.errorMessage ?? 'Failed to generate pickup code';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Pickup Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                controller.activePickupCode!,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              if (controller.pickupExpiresAt != null)
                Text(
                  'Expires at ${controller.pickupExpiresAt!.toLocal().toString().substring(0, 19)}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _passengerInitialsAvatar(String name) {
    final safe = name.trim();
    final letter = safe.isNotEmpty ? safe.characters.first.toUpperCase() : 'P';
    return Container(
      color: Colors.red,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _showPassengerVerifyCodeDialog() async {
    if (widget.isDriver || widget.bookingId == null) return;

    final controller = this.controller;
    if (controller == null) return;

    _codeController.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Enter pickup code'),
          content: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(counterText: ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: controller.isVerifyingCode
                  ? null
                  : () async {
                      final code = _codeController.text.trim();
                      if (code.isEmpty) return;
                      await controller.verifyPickupCode(code);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
              child: controller.isVerifyingCode
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  Future<void> _attachController() async {
    final c = await LiveTrackingSessionManager.instance.getOrStartSession(
      tripId: widget.tripId,
      currentUserId: widget.currentUserId,
      isDriver: widget.isDriver,
      bookingId: widget.bookingId,
    );
    c.onStateChanged = () {
      if (mounted) setState(() {});
    };
    controller = c;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _codeController.dispose();
    controller?.detachUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Live Ride Tracking',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            flex: 8,
            child: widget.isDriver ? _buildDriverMap() : _buildPassengerMap(),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final controller = this.controller;
    if (controller == null) return const SizedBox.shrink();
    final driverCanGenerateCode = widget.isDriver &&
        (controller.confirmedPassengerBookings.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.rideStarted
                      ? 'Ride in progress'
                      : widget.isDriver
                          ? 'Press start when all passengers are ready.'
                          : 'Press start when you board the vehicle.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isDriver)
                ElevatedButton(
                  onPressed: (controller.isLoading || controller.rideStarted)
                      ? null
                      : () {
                          controller.startRide();
                        },
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  child: controller.isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Start Ride'),
                )
              else
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: (controller.isLoading || controller.rideStarted)
                          ? null
                          : () {
                              controller.startRide();
                            },
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      child: controller.isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(controller.rideStarted ? 'On Board' : 'Start Ride'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: (!controller.rideStarted || controller.pickupVerified || controller.isVerifyingCode)
                          ? null
                          : () async {
                              await _showPassengerVerifyCodeDialog();
                            },
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      child: controller.isVerifyingCode
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(controller.pickupVerified ? 'Pickup Verified' : 'Pickup Code'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.isDriver)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  if (driverCanGenerateCode) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: controller.isGeneratingCode
                            ? null
                            : () async {
                                await _showDriverPickupCodeFlow();
                              },
                        icon: const Icon(Icons.qr_code),
                        label: Text(
                          controller.isGeneratingCode ? 'Generating...' : 'Pickup Code',
                        ),
                        style: ElevatedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (!controller.rideStarted || controller.isLoading || (controller.tripStatus == 'COMPLETED'))
                          ? null
                          : () async {
                              try {
                                setState(() {
                                  controller.isLoading = true;
                                  controller.errorMessage = null;
                                });
                                final res = await ApiService.completeTripRide(
                                  tripId: widget.tripId,
                                  driverId: widget.currentUserId,
                                );
                                if (res['success'] == true) {
                                  await LiveTrackingSessionManager.instance.stopSession();
                                  if (mounted) {
                                    Navigator.of(context).pop();
                                  }
                                } else {
                                  if (mounted) {
                                    setState(() {
                                      controller.errorMessage = res['error']?.toString() ?? 'Failed to complete trip';
                                    });
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() {
                                    controller.errorMessage = e.toString();
                                  });
                                }
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    controller.isLoading = false;
                                  });
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      child: const Text('Reached Destination (End Trip)'),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 34,
              child: ElevatedButton(
                onPressed: (!controller.rideStarted || !controller.pickupVerified || controller.isLoading)
                    ? null
                    : () async {
                        if (widget.bookingId == null) return;
                        try {
                          setState(() {
                            controller.isLoading = true;
                            controller.errorMessage = null;
                          });
                          final res = await ApiService.markBookingDroppedOff(
                            bookingId: widget.bookingId!,
                            passengerId: widget.currentUserId,
                          );
                          if (res['success'] == true) {
                            await LiveTrackingSessionManager.instance.stopSession();
                            if (mounted) {
                              Navigator.of(context).pop();
                            }
                          } else {
                            if (mounted) {
                              setState(() {
                                controller.errorMessage = res['error']?.toString() ?? 'Failed to mark dropped off';
                              });
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              controller.errorMessage = e.toString();
                            });
                          }
                        } finally {
                          if (mounted) {
                            setState(() {
                              controller.isLoading = false;
                            });
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Reached Destination'),
              ),
            ),
        ],
      ),
    );
  }

  LatLng _computeCenter(LiveTrackingController controller) {
    if (controller.driverPosition != null) {
      return controller.driverPosition!;
    }
    if (controller.passengers.isNotEmpty) {
      final first = controller.passengers.first;
      if (first['lat'] != null && first['lng'] != null) {
        return LatLng(
          (first['lat'] as num).toDouble(),
          (first['lng'] as num).toDouble(),
        );
      }
    }
    if (controller.routePolyline.isNotEmpty) {
      return controller.routePolyline.first;
    }
    return MapUtil.defaultFallbackCenter;
  }

  Widget _buildDriverMap() {
    final controller = this.controller;
    if (controller == null) return const SizedBox.shrink();
    final center = _computeCenter(controller);

    final markers = <Marker>[];

    // Driver live location
    if (controller.driverPosition != null) {
      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: controller.driverPosition!,
          child: const Icon(
            Icons.directions_bus,
            color: Colors.blue,
            size: 32,
          ),
        ),
      );
    }

    // Passengers live locations
    for (final p in controller.passengers) {
      if (p['lat'] == null || p['lng'] == null) continue;

      final name = (p['name'] ?? p['passenger_name'] ?? 'Passenger').toString();
      final rawPhoto = p['profile_photo'] ?? p['photo_url'] ?? p['profile_image'];
      final photoUrl = ImageUtils.ensureValidImageUrl(rawPhoto?.toString());
      final hasPhoto = photoUrl != null && ImageUtils.isValidImageUrl(photoUrl);

      markers.add(
        Marker(
          width: 34,
          height: 34,
          point: LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: hasPhoto
                  ? Image.network(
                      photoUrl,
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return _passengerInitialsAvatar(name);
                      },
                    )
                  : _passengerInitialsAvatar(name),
            ),
          ),
        ),
      );
    }

    // Route stops
    for (final stop in controller.routeStops) {
      final lat = (stop['lat'] ?? stop['latitude']) as num?;
      final lng = (stop['lng'] ?? stop['longitude']) as num?;
      if (lat == null || lng == null) continue;
      final name = (stop['name'] ?? stop['stop_name'] ?? 'Route stop').toString();
      markers.add(
        Marker(
          width: 18,
          height: 18,
          point: LatLng(lat.toDouble(), lng.toDouble()),
          child: GestureDetector(
            onTap: () => _showStopName(name),
            child: const Icon(
              Icons.location_on,
              color: Colors.grey,
              size: 16,
            ),
          ),
        ),
      );
    }

    // All passengers' pickup points (green) and dropoff points (purple)
    for (final p in controller.allPickupPoints) {
      markers.add(
        Marker(
          width: 20,
          height: 20,
          point: p,
          child: const Icon(
            Icons.arrow_circle_down,
            color: Colors.green,
            size: 18,
          ),
        ),
      );
    }

    for (final d in controller.allDropoffPoints) {
      markers.add(
        Marker(
          width: 20,
          height: 20,
          point: d,
          child: const Icon(
            Icons.arrow_circle_up,
            color: Colors.deepPurple,
            size: 18,
          ),
        ),
      );
    }

    final fitPoints = <LatLng>[];
    if (controller.routePolyline.length >= 2) {
      fitPoints.addAll(controller.routePolyline);
    }
    if (controller.driverPosition != null) {
      fitPoints.add(controller.driverPosition!);
    }
    for (final m in markers) {
      fitPoints.add(m.point);
    }
    if (!_cameraFitScheduled && fitPoints.isNotEmpty) {
      final shouldFit = _lastCameraFitPointsCount == null || _lastCameraFitPointsCount != fitPoints.length;
      if (shouldFit) {
        _cameraFitScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _cameraFitScheduled = false;
          if (!mounted) return;
          try {
            MapUtil.fitCameraToPoints(_mapController, fitPoints);
            _lastCameraFitPointsCount = fitPoints.length;
          } catch (_) {}
        });
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
          ),
          children: [
            MapUtil.buildDefaultTileLayer(userAgentPackageName: 'lets_go.app'),
            if (controller.routePolyline.length >= 2)
              MapUtil.buildPolylineLayerFromPolylines(
                polylines: [
                  MapUtil.polyline(
                    points: controller.routePolyline,
                    color: Colors.blue.withAlpha(153),
                    strokeWidth: 4,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _buildLegend(),
        ),
      ],
    );
  }

  Widget _buildPassengerMap() {
    final controller = this.controller;
    if (controller == null) return const SizedBox.shrink();
    final center = _computeCenter(controller);

    final markers = <Marker>[];

    // Driver live location
    if (controller.driverPosition != null) {
      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: controller.driverPosition!,
          child: const Icon(
            Icons.directions_bus,
            color: Colors.blue,
            size: 32,
          ),
        ),
      );
    }

    // Current passenger live location (only after on board)
    if (controller.rideStarted) {
      for (final p in controller.passengers) {
        if (p['booking_id'] != null && controller.bookingId != null) {
          final id = (p['booking_id'] as num?)?.toInt();
          if (id != null && id != controller.bookingId) {
            continue; // Only show self to avoid clutter
          }
        }
        if (p['lat'] == null || p['lng'] == null) continue;
        markers.add(
          Marker(
            width: 28,
            height: 28,
            point: LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
            child: const Icon(
              Icons.person_pin_circle,
              color: Colors.red,
              size: 24,
            ),
          ),
        );
      }
    }

    // Route stops: grey for all others, highlighted for this booking's
    for (final stop in controller.routeStops) {
      final lat = (stop['lat'] ?? stop['latitude']) as num?;
      final lng = (stop['lng'] ?? stop['longitude']) as num?;
      if (lat == null || lng == null) continue;
      final point = LatLng(lat.toDouble(), lng.toDouble());
      final name = (stop['name'] ?? stop['stop_name'] ?? 'Route stop').toString();

      bool isPickup = controller.passengerPickupPoint != null &&
          (controller.passengerPickupPoint!.latitude == point.latitude &&
              controller.passengerPickupPoint!.longitude == point.longitude);
      bool isDropoff = controller.passengerDropoffPoint != null &&
          (controller.passengerDropoffPoint!.latitude == point.latitude &&
              controller.passengerDropoffPoint!.longitude == point.longitude);

      Color color;
      IconData icon;

      if (isPickup) {
        color = Colors.green;
        icon = Icons.location_on;
      } else if (isDropoff) {
        color = Colors.deepPurple;
        icon = Icons.location_on;
      } else {
        color = Colors.grey; // Out-of-booking stops grey
        icon = Icons.circle;
      }

      markers.add(
        Marker(
          width: 20,
          height: 20,
          point: point,
          child: GestureDetector(
            onTap: () => _showStopName(name),
            child: Icon(
              icon,
              color: color,
              size: isPickup || isDropoff ? 20 : 10,
            ),
          ),
        ),
      );
    }

    // Build highlighted segment between passenger pickup and drop, following the route.
    List<LatLng> passengerSegment = [];
    if (controller.passengerPickupPoint != null &&
        controller.passengerDropoffPoint != null &&
        controller.routePolyline.isNotEmpty) {
      int startIndex = -1;
      int endIndex = -1;

      bool closeTo(LatLng a, LatLng b) {
        const eps = 1e-5;
        return (a.latitude - b.latitude).abs() < eps &&
            (a.longitude - b.longitude).abs() < eps;
      }

      for (var i = 0; i < controller.routePolyline.length; i++) {
        final pt = controller.routePolyline[i];
        if (startIndex == -1 && closeTo(pt, controller.passengerPickupPoint!)) {
          startIndex = i;
        }
        if (closeTo(pt, controller.passengerDropoffPoint!)) {
          endIndex = i;
          break;
        }
      }

      if (startIndex != -1 && endIndex != -1 && endIndex >= startIndex) {
        passengerSegment =
            controller.routePolyline.sublist(startIndex, endIndex + 1);
      }
    }

    final fitPoints = <LatLng>[];
    if (controller.routePolyline.length >= 2) {
      fitPoints.addAll(controller.routePolyline);
    }
    if (controller.driverPosition != null) {
      fitPoints.add(controller.driverPosition!);
    }
    for (final m in markers) {
      fitPoints.add(m.point);
    }
    if (!_cameraFitScheduled && fitPoints.isNotEmpty) {
      final shouldFit = _lastCameraFitPointsCount == null || _lastCameraFitPointsCount != fitPoints.length;
      if (shouldFit) {
        _cameraFitScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _cameraFitScheduled = false;
          if (!mounted) return;
          try {
            MapUtil.fitCameraToPoints(_mapController, fitPoints);
            _lastCameraFitPointsCount = fitPoints.length;
          } catch (_) {}
        });
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
          ),
          children: [
            MapUtil.buildDefaultTileLayer(userAgentPackageName: 'lets_go.app'),
            if (controller.routePolyline.length >= 2)
              MapUtil.buildPolylineLayerFromPolylines(
                polylines: [
                  MapUtil.polyline(
                    points: controller.routePolyline,
                    color: Colors.blue.withAlpha(153),
                    strokeWidth: 4,
                  ),
                  if (passengerSegment.isNotEmpty)
                    MapUtil.polyline(
                      points: passengerSegment,
                      color: Colors.green,
                      strokeWidth: 5,
                    ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _buildLegend(),
        ),
      ],
    );
  }

  void _showStopName(String name) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(name),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildLegend() {
    return Card(
      color: Colors.white.withAlpha(230),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _LegendRow(icon: Icons.directions_bus, color: Colors.blue, label: 'Driver'),
            _LegendRow(icon: Icons.person_pin_circle, color: Colors.red, label: 'Passenger location'),
            _LegendRow(icon: Icons.circle, color: Colors.grey, label: 'Other route stops'),
            _LegendRow(icon: Icons.location_on, color: Colors.green, label: 'Pickup stop'),
            _LegendRow(icon: Icons.location_on, color: Colors.deepPurple, label: 'Drop-off stop'),
          ],
        ),
      ),
    );
  }
  Widget _buildFooter() {
    final controller = this.controller;
    if (controller == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.errorMessage != null)
            Text(
              controller.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _LegendRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
