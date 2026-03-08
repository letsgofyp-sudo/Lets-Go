import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/post_bookings_controller/live_tracking_controller.dart';
import '../../services/api_service.dart';
import '../../services/live_tracking_session_manager.dart';
import '../../services/notification_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/map_util.dart';
import '../chat_screens/driver_chat_members_screen.dart';
import 'driver_payment_confirmation_screen.dart';

class DriverLiveTrackingScreen extends StatefulWidget {
  final String tripId;
  final int driverId;

  const DriverLiveTrackingScreen({
    super.key,
    required this.tripId,
    required this.driverId,
  });

  @override
  State<DriverLiveTrackingScreen> createState() => _DriverLiveTrackingScreenState();
}

class _DriverLiveTrackingScreenState extends State<DriverLiveTrackingScreen> {
  LiveTrackingController? controller;
  final MapController _mapController = MapController();
  bool _openingChat = false;
  bool _sharingLocation = false;

  int? _lastCameraFitPointsCount;
  bool _cameraFitScheduled = false;

  DateTime? _lastNearPickupNotificationAt;
  DateTime? _lastNearDropoffNotificationAt;
  static const double _geofenceMeters = 100;

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

  Future<void> _openChat() async {
    if (_openingChat) return;
    setState(() {
      _openingChat = true;
    });

    try {
      final userData = await ApiService.getUserProfile(widget.driverId);
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DriverChatMembersScreen(
            userData: userData,
            tripId: widget.tripId,
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
          isDriver: true,
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

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String _stopNameForOrder(LiveTrackingController controller, int? stopOrder, {required String fallback}) {
    if (stopOrder == null) return fallback;
    for (final stop in controller.routeStops) {
      final order = _asInt(stop['stop_order'] ?? stop['order']);
      if (order != null && order == stopOrder) {
        final name = (stop['name'] ?? stop['stop_name'] ?? '').toString().trim();
        return name.isNotEmpty ? name : fallback;
      }
    }
    return fallback;
  }

  LatLng? _pointForStopOrder(LiveTrackingController controller, int? stopOrder) {
    if (stopOrder == null) return null;
    for (final stop in controller.routeStops) {
      final order = _asInt(stop['stop_order'] ?? stop['order']);
      if (order != null && order == stopOrder) {
        final lat = (stop['lat'] ?? stop['latitude']) as num?;
        final lng = (stop['lng'] ?? stop['longitude']) as num?;
        if (lat == null || lng == null) return null;
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  double? _metersTo(LiveTrackingController controller, LatLng? target) {
    final me = controller.myPosition;
    if (me == null || target == null) return null;
    return const Distance()(me, target);
  }

  String _fmtKm(double? meters) {
    if (meters == null) return '-';
    final km = meters / 1000.0;
    return km >= 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(2);
  }

  Future<void> _maybeDriverProximityNotifications(LiveTrackingController controller) async {
    if (!controller.rideStarted) return;

    final booking = _bookingForPassengerSelection(controller);
    if (booking == null) return;

    final fromOrder = _asInt(booking['from_stop_order'] ?? booking['from_order'] ?? booking['pickup_stop_order'] ?? booking['pickup_order']);
    final toOrder = _asInt(booking['to_stop_order'] ?? booking['to_order'] ?? booking['dropoff_stop_order'] ?? booking['dropoff_order']);

    final pickupPoint = _pointForStopOrder(controller, fromOrder);
    final dropPoint = _pointForStopOrder(controller, toOrder);

    if (controller.pickupVerified != true) {
      final meters = _metersTo(controller, pickupPoint);
      if (meters != null && meters <= _geofenceMeters) {
        final last = _lastNearPickupNotificationAt;
        if (last == null || DateTime.now().difference(last) > const Duration(minutes: 2)) {
          _lastNearPickupNotificationAt = DateTime.now();
          await NotificationService.showLocalNotification(
            id: 9201,
            title: 'Near passenger pickup',
            body: 'Ask passenger to verify pickup using QR/OTP.',
            payload: <String, dynamic>{
              'type': 'driver_near_pickup',
              'trip_id': widget.tripId,
              'booking_id': controller.selectedBookingId,
            },
          );
        }
      }
    } else {
      final meters = _metersTo(controller, dropPoint);
      if (meters != null && meters <= _geofenceMeters) {
        final last = _lastNearDropoffNotificationAt;
        if (last == null || DateTime.now().difference(last) > const Duration(minutes: 2)) {
          _lastNearDropoffNotificationAt = DateTime.now();
          await NotificationService.showLocalNotification(
            id: 9202,
            title: 'Near destination',
            body: 'Passenger can mark as Reached when you arrive.',
            payload: <String, dynamic>{
              'type': 'driver_near_dropoff',
              'trip_id': widget.tripId,
              'booking_id': controller.selectedBookingId,
            },
          );
        }
      }
    }
  }

  Map<String, dynamic>? _bookingForPassengerSelection(LiveTrackingController controller) {
    final id = controller.selectedBookingId;
    if (id == null) return null;
    for (final b in controller.confirmedPassengerBookings) {
      final bid = _asInt(b['booking_id'] ?? b['id']);
      if (bid != null && bid == id) {
        return b;
      }
    }
    return null;
  }

  Widget _buildNextActions(LiveTrackingController controller) {
    final booking = _bookingForPassengerSelection(controller);
    if (booking == null) return const SizedBox.shrink();

    final fromOrder = _asInt(booking['from_stop_order'] ?? booking['from_order'] ?? booking['pickup_stop_order'] ?? booking['pickup_order']);
    final toOrder = _asInt(booking['to_stop_order'] ?? booking['to_order'] ?? booking['dropoff_stop_order'] ?? booking['dropoff_order']);

    final pickupName = _stopNameForOrder(controller, fromOrder, fallback: 'Pickup');
    final dropName = _stopNameForOrder(controller, toOrder, fallback: 'Drop-off');

    final pickupPoint = _pointForStopOrder(controller, fromOrder);
    final dropPoint = _pointForStopOrder(controller, toOrder);

    final pickupMeters = _metersTo(controller, pickupPoint);
    final dropMeters = _metersTo(controller, dropPoint);

    final primaryTitle = controller.pickupVerified == true ? 'Next: Drop-off' : 'Next: Pickup';
    final primaryWhere = controller.pickupVerified == true ? dropName : pickupName;
    final primaryKm = controller.pickupVerified == true ? _fmtKm(dropMeters) : _fmtKm(pickupMeters);

    final secondaryTitle = controller.pickupVerified == true ? null : 'Then: Drop-off';
    final secondaryWhere = controller.pickupVerified == true ? null : dropName;
    final secondaryKm = controller.pickupVerified == true ? null : _fmtKm(dropMeters);

    _maybeDriverProximityNotifications(controller);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(primaryTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('$primaryWhere • $primaryKm km', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (secondaryTitle != null && secondaryWhere != null && secondaryKm != null) ...[
            const SizedBox(height: 10),
            Text(secondaryTitle, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('$secondaryWhere • $secondaryKm km', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          Text(
            controller.pickupVerified == true
                ? 'Ask the passenger to mark as Reached near destination.'
                : 'Generate pickup QR and ask passenger to scan or enter OTP.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  double? _computeFinalFarePerSeat(Map<String, dynamic> booking) {
    return _asDouble(
      booking['final_fare_per_seat'] ??
          booking['final_fare'] ??
          booking['accepted_fare_per_seat'] ??
          booking['negotiated_fare_per_seat'] ??
          booking['negotiated_fare'] ??
          booking['passenger_offer_per_seat'] ??
          booking['passenger_offer'] ??
          booking['original_fare_per_seat'],
    );
  }

  Future<int?> _selectBookingIdForDriverAction() async {
    final controller = this.controller;
    if (controller == null) return null;

    final list = controller.confirmedPassengerBookings;
    if (list.isEmpty) return null;

    if (list.length == 1) {
      final id = list.first['booking_id'] ?? list.first['id'];
      return int.tryParse(id?.toString() ?? '');
    }

    final selectedBookingId = await showModalBottomSheet<int>(
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

    return selectedBookingId;
  }

  String? _passengerPhotoUrl(Map<String, dynamic> m) {
    final raw = m['passenger_photo_url'] ??
        m['passenger_profile_image'] ??
        m['passenger_image'] ??
        m['profile_photo'] ??
        m['photo_url'] ??
        m['profile_image'];
    final ensured = ImageUtils.ensureValidImageUrl(raw?.toString());
    if (ensured != null && ImageUtils.isValidImageUrl(ensured)) {
      return ensured;
    }
    return null;
  }

  Map<String, dynamic>? _stopForOrder(LiveTrackingController controller, int? stopOrder) {
    if (stopOrder == null) return null;
    for (final stop in controller.routeStops) {
      final order = _asInt(stop['stop_order'] ?? stop['order']);
      if (order != null && order == stopOrder) {
        return stop;
      }
    }
    return null;
  }

  int? _stopEstimatedMinutesFromStart(Map<String, dynamic> stop) {
    final v = stop['estimated_time_from_start'] ??
        stop['estimated_minutes_from_start'] ??
        stop['minutes_from_start'] ??
        stop['time_from_start'] ??
        stop['estimated_time'] ??
        stop['estimated_minutes'] ??
        stop['duration_from_start'];
    return _asInt(v);
  }

  DateTime? _etaForStopOrder(LiveTrackingController controller, int? stopOrder) {
    final base = controller.tripDepartureDateTime;
    if (base == null) return null;
    final stop = _stopForOrder(controller, stopOrder);
    if (stop == null) return null;
    final mins = _stopEstimatedMinutesFromStart(stop);
    if (mins == null) return null;
    return base.add(Duration(minutes: mins));
  }

  Map<String, dynamic>? _bookingForPassenger(LiveTrackingController controller, Map<String, dynamic> passenger) {
    final bookingId = _asInt(passenger['booking_id'] ?? passenger['bookingId'] ?? passenger['id']);
    if (bookingId == null) return null;
    for (final b in controller.confirmedPassengerBookings) {
      final id = _asInt(b['booking_id'] ?? b['id']);
      if (id != null && id == bookingId) {
        return b;
      }
    }
    return null;
  }

  Future<void> _showPassengerDetailsPopup(Map<String, dynamic> passenger) async {
    final controller = this.controller;
    if (controller == null) return;

    final booking = _bookingForPassenger(controller, passenger) ?? <String, dynamic>{};
    final passengerName = (booking['passenger_name'] ?? passenger['name'] ?? passenger['passenger_name'] ?? 'Passenger').toString();
    final gender = (booking['passenger_gender'] ?? passenger['gender'] ?? passenger['passenger_gender'] ?? '').toString();
    final rating = _asDouble(booking['passenger_rating'] ?? passenger['rating'] ?? passenger['passenger_rating']);
    final seats = _asInt(booking['number_of_seats'] ?? passenger['number_of_seats'] ?? booking['seats']) ?? 1;

    int maleSeats = _asInt(booking['male_seats'] ?? passenger['male_seats']) ?? 0;
    int femaleSeats = _asInt(booking['female_seats'] ?? passenger['female_seats']) ?? 0;
    if ((maleSeats + femaleSeats) <= 0) {
      final g = gender.toLowerCase();
      if (g == 'female') {
        femaleSeats = seats;
        maleSeats = 0;
      } else if (g == 'male') {
        maleSeats = seats;
        femaleSeats = 0;
      }
    }

    final fromName = (booking['from_stop_name'] ?? '').toString();
    final toName = (booking['to_stop_name'] ?? '').toString();
    final fromOrder = _asInt(booking['from_stop_order'] ?? booking['from_order']);
    final toOrder = _asInt(booking['to_stop_order'] ?? booking['to_order']);
    final resolvedFrom = fromName.isNotEmpty
        ? fromName
        : _stopNameForOrder(controller, fromOrder, fallback: 'Pickup');
    final resolvedTo = toName.isNotEmpty
        ? toName
        : _stopNameForOrder(controller, toOrder, fallback: 'Drop-off');

    final pickupEta = _etaForStopOrder(controller, fromOrder);
    final dropoffEta = _etaForStopOrder(controller, toOrder);

    final offeredPerSeat = _asDouble(booking['passenger_offer_per_seat'] ?? booking['passenger_offer'] ?? passenger['passenger_offer_per_seat']);
    final finalFarePerSeat = _computeFinalFarePerSeat(booking);

    final photoUrl = _passengerPhotoUrl(booking) ?? _passengerPhotoUrl(passenger);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Passenger Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          child: Text(passengerName.isNotEmpty ? passengerName[0].toUpperCase() : 'P'),
                        ),
                        if (photoUrl != null && ImageUtils.isValidImageUrl(photoUrl))
                          ClipOval(
                            child: Image.network(
                              photoUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox.shrink();
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(passengerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            if (gender.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Icon(gender.toLowerCase() == 'female' ? Icons.female : Icons.male, size: 16, color: Colors.grey),
                            ],
                            if (rating != null) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.star, color: Colors.amber.shade600, size: 16),
                              Text(rating.toStringAsFixed(1)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Seats: $seats (M:$maleSeats F:$femaleSeats)', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Pickup: $resolvedFrom${pickupEta != null ? ' (${_fmtHm(pickupEta)})' : ''}'),
              Text('Drop-off: $resolvedTo${dropoffEta != null ? ' (${_fmtHm(dropoffEta)})' : ''}'),
              const SizedBox(height: 8),
              if (offeredPerSeat != null)
                Text('Passenger offer: ₨${offeredPerSeat.round()}/seat'),
              if (finalFarePerSeat != null)
                Text(
                  'Final accepted fare: ₨${finalFarePerSeat.round()}/seat',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
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

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  Future<void> _attachController() async {
    final c = await LiveTrackingSessionManager.instance.getOrStartSession(
      tripId: widget.tripId,
      currentUserId: widget.driverId,
      isDriver: true,
    );
    if (!c.rideStarted) {
      c.stopSendingLocation();
    }
    c.onStateChanged = () {
      if (mounted) setState(() {});
    };
    controller = c;
    c.refreshTripLayout();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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

  Future<void> _showDriverPickupCodeFlow() async {
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
        final qrPayload = jsonEncode(<String, dynamic>{
          'trip_id': widget.tripId,
          'booking_id': selectedBookingId,
          'otp': controller.activePickupCode,
        });
        return AlertDialog(
          title: const Text('Pickup Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 200,
              ),
              const SizedBox(height: 12),
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
              onPressed: () async {
                await controller.generatePickupCode();
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (mounted) {
                  await _showDriverPickupCodeFlow();
                }
              },
              child: const Text('Change'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
            _LegendRow(icon: Icons.trip_origin, color: Colors.green, label: 'Start stop'),
            _LegendRow(icon: Icons.place, color: Colors.red, label: 'End stop'),
            _LegendRow(icon: Icons.location_on, color: Colors.orange, label: 'Intermediate stop'),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LiveTrackingController controller) {
    final canGenerateCode = controller.confirmedPassengerBookings.isNotEmpty;

    final speedLine = controller.driverSpeedKph != null
        ? 'Speed: ${controller.driverSpeedKph!.toStringAsFixed(1)} km/h'
        : null;
    final etaLine = controller.driverEtaSecondsToFinal != null
        ? 'Live ETA: ${_fmtMinutes(controller.driverEtaSecondsToFinal)}'
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
                'You may be off the planned route'
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
                  controller.rideStarted ? 'Ride in progress' : 'Press start when all passengers are ready.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
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
            ],
          ),
          if (speedLine != null) ...[
            const SizedBox(height: 4),
            Text(speedLine, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (etaLine != null) ...[
            const SizedBox(height: 2),
            Text(etaLine, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 10),
          _buildNextActions(controller),
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
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DriverPaymentConfirmationScreen(
                        tripId: widget.tripId,
                        driverId: widget.driverId,
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 34),
                ),
                child: const Icon(Icons.payments_outlined),
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
              OutlinedButton.icon(
                onPressed: canGenerateCode
                    ? () async {
                        final id = await _selectBookingIdForDriverAction();
                        if (id != null) {
                          controller.setSelectedBookingId(id);
                        }
                      }
                    : null,
                icon: const Icon(Icons.person_search),
                label: Text(
                  controller.selectedBookingId != null
                      ? 'Passenger (${controller.selectedBookingId})'
                      : 'Select Passenger',
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                if (canGenerateCode) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (controller.isGeneratingCode || !controller.rideStarted)
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
                                driverId: widget.driverId,
                              );
                              if (res['success'] == true) {
                                await LiveTrackingSessionManager.instance.stopSession();
                                if (mounted) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => DriverPaymentConfirmationScreen(
                                        tripId: widget.tripId,
                                        driverId: widget.driverId,
                                      ),
                                    ),
                                  );
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

  Widget _buildDriverMap(LiveTrackingController controller) {
    final center = _computeCenter(controller);
    final markers = <Marker>[];

    final bool signalLost = controller.rideStarted &&
        (controller.driverSignalLost == true || ((controller.driverLastSeenSeconds ?? 0) > 15));

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
          child: GestureDetector(
            onTap: () => _showPassengerDetailsPopup(Map<String, dynamic>.from(p)),
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
        ),
      );
    }

    final sortedStops = List<Map<String, dynamic>>.from(controller.routeStops);
    sortedStops.sort((a, b) {
      final oa = _asInt(a['stop_order'] ?? a['order']) ?? 0;
      final ob = _asInt(b['stop_order'] ?? b['order']) ?? 0;
      return oa.compareTo(ob);
    });

    for (var i = 0; i < sortedStops.length; i++) {
      final stop = sortedStops[i];
      final lat = (stop['lat'] ?? stop['latitude']) as num?;
      final lng = (stop['lng'] ?? stop['longitude']) as num?;
      if (lat == null || lng == null) continue;

      final name = (stop['name'] ?? stop['stop_name'] ?? 'Stop').toString();
      final icon = i == 0
          ? Icons.trip_origin
          : i == sortedStops.length - 1
              ? Icons.place
              : Icons.location_on;
      final color = i == 0
          ? Colors.green
          : i == sortedStops.length - 1
              ? Colors.red
              : Colors.orange;

      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: LatLng(lat.toDouble(), lng.toDouble()),
          child: GestureDetector(
            onTap: () => _showStopName(name),
            child: Stack(
              children: [
                Icon(icon, color: color, size: 40),
                Positioned(
                  bottom: -2,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      name.length > 8 ? '${name.substring(0, 8)}...' : name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final fitPoints = <LatLng>[];
    if (controller.routePolyline.length >= 2) {
      fitPoints.addAll(controller.routePolyline);
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
            if (controller.routePolyline.length >= 2 || controller.driverPathPolyline.length >= 2)
              MapUtil.buildPolylineLayerFromPolylines(
                polylines: [
                  if (controller.routePolyline.length >= 2)
                    MapUtil.polyline(
                      points: controller.routePolyline,
                      color: Colors.blue,
                      strokeWidth: 4,
                    ),
                  if (controller.driverPathPolyline.length >= 2)
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
                    ? 'Signal lost (${controller.driverLastSeenSeconds}s)'
                    : 'Signal lost',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _buildLegend(),
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
            child: _buildDriverMap(controller),
          ),
          _buildFooter(controller),
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
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
