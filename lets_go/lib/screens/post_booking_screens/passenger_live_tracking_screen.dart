import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';

import '../../controllers/post_bookings_controller/live_tracking_controller.dart';
import '../../services/api_service.dart';
import '../../services/live_tracking_session_manager.dart';
import '../../services/notification_service.dart';
import '../../utils/map_util.dart';
import '../chat_screens/passenger_chat_screen.dart';
import 'passenger_payment_screen.dart';

class PassengerLiveTrackingScreen extends StatefulWidget {
  final String tripId;
  final int passengerId;
  final int bookingId;

  const PassengerLiveTrackingScreen({
    super.key,
    required this.tripId,
    required this.passengerId,
    required this.bookingId,
  });

  @override
  State<PassengerLiveTrackingScreen> createState() => _PassengerLiveTrackingScreenState();
}

class _PassengerLiveTrackingScreenState extends State<PassengerLiveTrackingScreen> {
  LiveTrackingController? controller;
  final TextEditingController _codeController = TextEditingController();
  final MapController _mapController = MapController();
  bool _openingChat = false;
  bool _sharingLocation = false;

  int? _lastCameraFitPointsCount;
  bool _cameraFitScheduled = false;

  DateTime? _lastNearPickupNotificationAt;
  DateTime? _lastNearDestinationNotificationAt;

  static const double _geofenceMeters = 100;

  Future<void> _maybeProximityNotifications(LiveTrackingController controller) async {
    if (!controller.rideStarted) return;

    final myPos = controller.myPosition;
    if (myPos == null) return;

    final distance = const Distance();

    final pickup = controller.passengerPickupPoint;
    if (pickup != null && controller.pickupVerified != true) {
      final driverPos = controller.driverPosition;
      // Notify passenger when the DRIVER is near the pickup point.
      // If driver position isn't available yet, fall back to passenger position.
      final meters = driverPos != null ? distance(driverPos, pickup) : distance(myPos, pickup);
      if (meters <= _geofenceMeters) {
        final last = _lastNearPickupNotificationAt;
        if (last == null || DateTime.now().difference(last) > const Duration(minutes: 2)) {
          _lastNearPickupNotificationAt = DateTime.now();
          await NotificationService.showLocalNotification(
            id: 9101,
            title: 'Driver is near your pickup',
            body: 'Please be ready. Keep your phone accessible for verification.',
            payload: <String, dynamic>{
              'type': 'near_pickup',
              'trip_id': widget.tripId,
              'booking_id': widget.bookingId,
            },
          );
        }
      }
    }

    final drop = controller.passengerDropoffPoint;
    if (drop != null) {
      final meters = distance(myPos, drop);
      if (meters <= _geofenceMeters) {
        final last = _lastNearDestinationNotificationAt;
        if (last == null || DateTime.now().difference(last) > const Duration(minutes: 2)) {
          _lastNearDestinationNotificationAt = DateTime.now();
          await NotificationService.showLocalNotification(
            id: 9102,
            title: 'You are near your destination',
            body: 'Mark as Reached when you arrive.',
            payload: <String, dynamic>{
              'type': 'near_destination',
              'trip_id': widget.tripId,
              'booking_id': widget.bookingId,
            },
          );
        }
      }
    }
  }

  Future<bool> _ensureCameraPermission() async {
    try {
      final status = await Permission.camera.status;
      if (status.isGranted) return true;

      final requested = await Permission.camera.request();
      if (requested.isGranted) return true;

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requested.isPermanentlyDenied
                ? 'Camera permission permanently denied. Enable it from Settings to scan QR.'
                : 'Camera permission denied. Cannot scan QR.',
          ),
          duration: const Duration(seconds: 3),
          action: requested.isPermanentlyDenied
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: () {
                    openAppSettings();
                  },
                )
              : null,
        ),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to request camera permission')),
      );
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  Future<void> _scanPickupQrAndVerify() async {
    final controller = this.controller;
    if (controller == null) return;

    final ok = await _ensureCameraPermission();
    if (!ok) return;

    if (!mounted) return;

    String? code;
    try {
      code = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return Dialog(
            child: SizedBox(
              height: 360,
              child: Column(
                children: [
                  AppBar(
                    title: const Text('Scan Pickup QR'),
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  Expanded(
                    child: MobileScanner(
                      onDetect: (capture) {
                        final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
                        final raw = barcode?.rawValue;
                        if (raw == null || raw.isEmpty) return;

                        // Expected payload: JSON {trip_id, booking_id, otp}
                        try {
                          final decoded = jsonDecode(raw);
                          if (decoded is Map) {
                            final otp = decoded['otp']?.toString();
                            final bookingId = decoded['booking_id']?.toString();
                            final tripId = decoded['trip_id']?.toString();
                            if (otp != null && otp.isNotEmpty && bookingId == widget.bookingId.toString() && tripId == widget.tripId) {
                              Navigator.of(ctx).pop(otp);
                              return;
                            }
                          }
                        } catch (_) {
                          // fallback: raw might just be the OTP
                          if (raw.length >= 4 && raw.length <= 8) {
                            Navigator.of(ctx).pop(raw);
                            return;
                          }
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (_) {
      code = null;
    }

    if (!mounted) return;
    if (code == null || code.trim().isEmpty) return;
    await controller.verifyPickupCode(code.trim());
  }

  Future<void> _attachController() async {
    final c = await LiveTrackingSessionManager.instance.getOrStartSession(
      tripId: widget.tripId,
      currentUserId: widget.passengerId,
      isDriver: false,
      bookingId: widget.bookingId,
    );
    if (!c.rideStarted) {
      c.stopSendingLocation();
    }
    c.onStateChanged = () {
      if (mounted) setState(() {});
    };
    await c.refreshTripLayout();
    controller = c;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _codeController.dispose();
    controller?.detachUi();
    if (controller != null && controller!.rideStarted != true) {
      () async {
        try {
          await LiveTrackingSessionManager.instance.stopSession();
        } catch (_) {}
      }();
    }
    super.dispose();
  }

  LatLng _computeCenter(LiveTrackingController controller) {
    if (controller.driverPosition != null) {
      return controller.driverPosition!;
    }
    if (controller.routePolyline.isNotEmpty) {
      return controller.routePolyline.first;
    }
    return MapUtil.defaultFallbackCenter;
  }

  Future<void> _showPassengerVerifyCodeDialog() async {
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

  Future<void> _openChat() async {
    if (_openingChat) return;
    setState(() {
      _openingChat = true;
    });

    try {
      final userData = await ApiService.getUserProfile(widget.passengerId);
      final detail = await ApiService.getRideBookingDetails(widget.tripId);

      Map<String, dynamic> driverInfo = <String, dynamic>{};
      if (detail['driver'] is Map) {
        driverInfo = Map<String, dynamic>.from(detail['driver'] as Map);
      } else if (detail['trip'] is Map && (detail['trip'] as Map)['driver'] is Map) {
        driverInfo = Map<String, dynamic>.from((detail['trip'] as Map)['driver'] as Map);
      }

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PassengerChatScreen(
            userData: userData,
            tripId: widget.tripId,
            chatRoomId: widget.tripId,
            driverInfo: driverInfo,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open chat: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingChat = false;
        });
      }
    }
  }

  Future<void> _shareLiveLocation() async {
    if (_sharingLocation) return;
    setState(() {
      _sharingLocation = true;
    });

    try {
      String? trackingPageUrl;
      try {
        final resp = await ApiService.createTripShareLink(
          tripId: widget.tripId,
          isDriver: false,
          bookingId: widget.bookingId,
        );
        final raw = resp['share_url']?.toString();
        if (raw != null && raw.trim().isNotEmpty) {
          trackingPageUrl = raw.trim();
        }
      } catch (_) {
        trackingPageUrl = null;
      }

      if (trackingPageUrl == null) {
        throw Exception('Unable to create tracking link');
      }

      await Share.share('Trip tracking page: $trackingPageUrl');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share location: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sharingLocation = false;
        });
      }
    }
  }

  String _fmtHm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtMinutes(int? seconds) {
    if (seconds == null) return '-';
    final mins = (seconds / 60).round();
    if (mins <= 0) return '0 min';
    return '$mins min';
  }

  Map<String, dynamic>? _stopForOrder(LiveTrackingController controller, int? stopOrder) {
    if (stopOrder == null) return null;
    for (final s in controller.routeStops) {
      final orderRaw = s['stop_order'] ?? s['order'];
      final order = orderRaw is int ? orderRaw : int.tryParse(orderRaw?.toString() ?? '');
      if (order != null && order == stopOrder) {
        return s;
      }
    }
    return null;
  }

  String _stopDisplayName(Map<String, dynamic> stop, {required String fallback}) {
    final name = (stop['name'] ?? stop['stop_name'] ?? '').toString().trim();
    return name.isNotEmpty ? name : fallback;
  }

  int? _stopEstimatedMinutesFromStart(Map<String, dynamic> stop) {
    final raw = stop['estimated_time_from_start'] ??
        stop['estimated_minutes_from_start'] ??
        stop['minutes_from_start'] ??
        stop['time_from_start'] ??
        stop['estimated_time'] ??
        stop['estimated_minutes'] ??
        stop['duration_from_start'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  bool _isWithinPassengerSegment(LiveTrackingController controller, int stopOrder) {
    final from = controller.passengerFromStopOrder;
    final to = controller.passengerToStopOrder;
    if (from == null || to == null) return true;
    if (from <= to) {
      return stopOrder >= from && stopOrder <= to;
    }
    return stopOrder <= from && stopOrder >= to;
  }

  Widget _buildHeader(LiveTrackingController controller) {
    final pickupStop = _stopForOrder(controller, controller.passengerFromStopOrder);
    final dropStop = _stopForOrder(controller, controller.passengerToStopOrder);

    String? pickupLine;
    String? dropLine;

    if (controller.tripDepartureDateTime != null) {
      if (pickupStop != null) {
        final mins = _stopEstimatedMinutesFromStart(pickupStop);
        if (mins != null) {
          final eta = controller.tripDepartureDateTime!.add(Duration(minutes: mins));
          pickupLine = 'Pickup time: ${_fmtHm(eta)}';
        }
      }
      if (dropStop != null) {
        final mins = _stopEstimatedMinutesFromStart(dropStop);
        if (mins != null) {
          final eta = controller.tripDepartureDateTime!.add(Duration(minutes: mins));
          dropLine = 'Drop-off ETA: ${_fmtHm(eta)}';
        }
      }
    }

    final speedLine = controller.driverSpeedKph != null
        ? 'Speed: ${controller.driverSpeedKph!.toStringAsFixed(1)} km/h'
        : null;
    final etaLine = controller.passengerEtaSecondsToDropoff != null
        ? 'Live ETA: ${_fmtMinutes(controller.passengerEtaSecondsToDropoff)}'
        : null;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.isDriverDeviating == true) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Text(
                'Driver may be off the planned route'
                '${controller.driverDeviationMeters != null ? ' (${controller.driverDeviationMeters!.toStringAsFixed(0)}m)' : ''}',
                style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.rideStarted
                      ? 'Ride in progress'
                      : 'Start the ride to share your live location.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          if (pickupStop != null) ...[
            const SizedBox(height: 6),
            Text(
              'Pickup: ${_stopDisplayName(pickupStop, fallback: 'Pickup')}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
          if (pickupLine != null) ...[
            const SizedBox(height: 2),
            Text(pickupLine, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (dropStop != null) ...[
            const SizedBox(height: 2),
            Text(
              'Drop-off: ${_stopDisplayName(dropStop, fallback: 'Drop-off')}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
          if (dropLine != null) ...[
            const SizedBox(height: 2),
            Text(dropLine, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (speedLine != null) ...[
            const SizedBox(height: 2),
            Text(speedLine, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (etaLine != null) ...[
            const SizedBox(height: 2),
            Text(etaLine, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (!controller.rideStarted || controller.pickupVerified || controller.isVerifyingCode)
                        ? null
                        : () async => _showPassengerVerifyCodeDialog(),
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    child: controller.isVerifyingCode
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Pickup Code'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: OutlinedButton(
                    onPressed: (!controller.rideStarted || controller.pickupVerified || controller.isVerifyingCode)
                        ? null
                        : () async => _scanPickupQrAndVerify(),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.qr_code_scanner, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (!controller.rideStarted || !controller.pickupVerified || controller.isLoading)
                        ? null
                        : () async {
                            try {
                              setState(() {
                                controller.isLoading = true;
                                controller.errorMessage = null;
                              });
                              final res = await ApiService.markBookingDroppedOff(
                                bookingId: widget.bookingId,
                                passengerId: widget.passengerId,
                              );
                              if (res['success'] == true) {
                                await LiveTrackingSessionManager.instance.stopSession();
                                if (mounted) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => PassengerPaymentScreen(
                                        tripId: widget.tripId,
                                        passengerId: widget.passengerId,
                                        bookingId: widget.bookingId,
                                      ),
                                    ),
                                  );
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    child: const Text('Reached Destination'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _openingChat ? null : _openChat,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 34),
                ),
                child: const Icon(Icons.chat),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PassengerPaymentScreen(
                        tripId: widget.tripId,
                        passengerId: widget.passengerId,
                        bookingId: widget.bookingId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Payment'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              OutlinedButton(
                onPressed: _sharingLocation ? null : _shareLiveLocation,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 34),
                ),
                child: const Icon(Icons.share_location_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(LiveTrackingController controller) {
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
        ],
      ),
    );
  }

  Widget _buildPassengerMap(LiveTrackingController controller) {
    final center = _computeCenter(controller);
    final markers = <Marker>[];

    final bool signalLost = controller.rideStarted &&
        (controller.driverSignalLost == true || ((controller.driverLastSeenSeconds ?? 0) > 15));

    final int? pickupOrder = controller.passengerFromStopOrder;
    final int? dropOrder = controller.passengerToStopOrder;

    final stops = controller.routeStops
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    stops.sort((a, b) {
      final aoRaw = a['stop_order'] ?? a['order'];
      final boRaw = b['stop_order'] ?? b['order'];
      final ao = aoRaw is int ? aoRaw : int.tryParse(aoRaw?.toString() ?? '');
      final bo = boRaw is int ? boRaw : int.tryParse(boRaw?.toString() ?? '');
      if (ao == null && bo == null) return 0;
      if (ao == null) return 1;
      if (bo == null) return -1;
      return ao.compareTo(bo);
    });

    final stopPoints = <LatLng>[];

    for (final stop in stops) {
      final lat = (stop['latitude'] ?? stop['lat']) as num?;
      final lng = (stop['longitude'] ?? stop['lng']) as num?;
      if (lat == null || lng == null) continue;
      final point = LatLng(lat.toDouble(), lng.toDouble());
      stopPoints.add(point);

      final name = (stop['name'] ?? stop['stop_name'] ?? 'Stop').toString();
      final rawOrder = stop['stop_order'] ?? stop['order'];
      final stopOrder = rawOrder is int ? rawOrder : int.tryParse(rawOrder?.toString() ?? '');

      final resolvedStopOrder = stopOrder ?? (stopPoints.length);
      final within = _isWithinPassengerSegment(controller, resolvedStopOrder);

      final isPickup = pickupOrder != null && resolvedStopOrder == pickupOrder;
      final isDrop = dropOrder != null && resolvedStopOrder == dropOrder;

      Color baseColor;
      IconData icon;
      if (isPickup) {
        baseColor = const Color(0xFF4CAF50);
        icon = Icons.trip_origin;
      } else if (isDrop) {
        baseColor = const Color(0xFFE53935);
        icon = Icons.place;
      } else {
        baseColor = const Color(0xFFFF9800);
        icon = Icons.location_on;
      }

      final color = within ? baseColor : Colors.grey;

      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: point,
          child: Stack(
            children: [
              Icon(
                icon,
                color: color,
                size: 40,
              ),
              Positioned(
                bottom: -2,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withAlpha(230),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    name.length > 8 ? '${name.substring(0, 8)}...' : name,
                    style: const TextStyle(color: Colors.white, fontSize: 8),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

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

    if (controller.rideStarted) {
      for (final p in controller.passengers) {
        if (p['booking_id'] != null && controller.bookingId != null) {
          final id = (p['booking_id'] as num?)?.toInt();
          if (id != null && id != controller.bookingId) {
            continue;
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

    final fitPoints = <LatLng>[];
    if (controller.routePolyline.length >= 2) {
      fitPoints.addAll(controller.routePolyline);
    } else {
      fitPoints.addAll(stopPoints);
    }
    if (controller.driverPathPolyline.length >= 2) {
      fitPoints.addAll(controller.driverPathPolyline);
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
          } catch (_) {
            // MapController isn't ready yet; retry on next frame.
          }
        });
      }
    }

    _maybeProximityNotifications(controller);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
          ),
          children: [
            MapUtil.buildDefaultTileLayer(userAgentPackageName: 'com.example.lets_go'),
            if (controller.routePolyline.length > 1 || controller.driverPathPolyline.length > 1)
              MapUtil.buildPolylineLayerFromPolylines(
                polylines: [
                  if (controller.routePolyline.length > 1)
                    MapUtil.polyline(
                      points: controller.routePolyline,
                      color: Colors.blue,
                      strokeWidth: 4,
                    ),
                  if (controller.driverPathPolyline.length > 1)
                    MapUtil.polyline(
                      points: controller.driverPathPolyline,
                      color: signalLost ? Colors.red : const Color(0xFF8E44AD),
                      strokeWidth: 5,
                    ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        if (signalLost)
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(230),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                controller.driverLastSeenSeconds != null
                    ? 'Driver signal lost (${controller.driverLastSeenSeconds}s)'
                    : 'Driver signal lost',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
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
        title: const Text('Live Ride Tracking'),
      ),
      body: Column(
        children: [
          _buildHeader(controller),
          Expanded(
            flex: 8,
            child: _buildPassengerMap(controller),
          ),
          _buildFooter(controller),
        ],
      ),
    );
  }
}
