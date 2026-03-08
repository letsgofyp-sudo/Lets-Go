import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/post_bookings_controller/live_tracking_controller.dart';
import '../services/live_tracking_session_manager.dart';
import '../services/api_service.dart';
import '../utils/auth_session.dart';

class SosFloatingButtonOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const SosFloatingButtonOverlay({super.key, required this.navigatorKey});

  @override
  State<SosFloatingButtonOverlay> createState() => _SosFloatingButtonOverlayState();
}

class _SosFloatingButtonOverlayState extends State<SosFloatingButtonOverlay> {
  static const double _size = 58;

  Offset _pos = const Offset(0, 0);
  bool _posInitialized = false;

  double _dragDistance = 0;

  Timer? _pollTimer;
  bool _shouldShow = false;
  Map<String, dynamic>? _activeSession;

  BuildContext? get _navContext => widget.navigatorKey.currentContext;

  Future<void> _showMessage(String title, String message) async {
    final navCtx = _navContext;
    if (navCtx == null) return;
    await showDialog<void>(
      context: navCtx,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(navCtx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshVisibility());
    _refreshVisibility();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }

  Future<void> _refreshVisibility() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('active_live_tracking_send_enabled_v1') ?? false;
      final raw = prefs.getString('active_live_tracking_session_v1');
      Map<String, dynamic>? session;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          session = Map<String, dynamic>.from(decoded);
        }
      }

      final shouldShow = enabled && session != null;

      if (!mounted) return;
      if (_shouldShow != shouldShow || jsonEncode(_activeSession) != jsonEncode(session)) {
        setState(() {
          _shouldShow = shouldShow;
          _activeSession = session;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (_shouldShow) {
        setState(() {
          _shouldShow = false;
          _activeSession = null;
        });
      }
    }
  }

  Future<void> _triggerSos() async {
    final session = _activeSession;
    if (session == null) {
      await _showMessage('SOS', 'No active ride session found.');
      return;
    }

    final navCtx = _navContext;
    if (navCtx == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: navCtx,
      barrierDismissible: false,
      builder: (_) => const _SosCountdownDialog(),
    );

    if (confirmed != true) {
      return;
    }

    try {
      final user = await AuthSession.load();
      final userId = int.tryParse(user?['id']?.toString() ?? '') ??
          int.tryParse(user?['user_id']?.toString() ?? '') ??
          0;
      if (userId == 0) {
        await _showMessage('SOS Failed', 'You are not logged in.');
        return;
      }

      final tripId = session['trip_id']?.toString() ?? '';
      final isDriver = session['is_driver'] == true;
      final bookingIdRaw = session['booking_id'];
      int? bookingId;
      if (bookingIdRaw is int) {
        bookingId = bookingIdRaw;
      } else if (bookingIdRaw is String) {
        bookingId = int.tryParse(bookingIdRaw);
      } else if (bookingIdRaw is num) {
        bookingId = bookingIdRaw.toInt();
      }

      if (tripId.isEmpty) {
        await _showMessage('SOS Failed', 'Trip information is missing.');
        return;
      }

      LiveTrackingController? ctrl = LiveTrackingSessionManager.instance.controller;
      ctrl ??= await LiveTrackingSessionManager.instance.restorePersistedSession();

      LatLng? point;
      if (ctrl != null) {
        if (isDriver) {
          point = ctrl.driverPosition;
          point ??= ctrl.driverPathPolyline.isNotEmpty ? ctrl.driverPathPolyline.last : null;
        } else {
          final targetBookingId = bookingId ?? ctrl.bookingId;
          if (targetBookingId != null) {
            for (final p in ctrl.passengers) {
              final bid = p['booking_id'] ?? p['bookingId'] ?? p['id'];
              final bidInt = bid is int ? bid : int.tryParse(bid?.toString() ?? '');
              if (bidInt != null && bidInt == targetBookingId) {
                final latRaw = p['lat'] ?? p['latitude'];
                final lngRaw = p['lng'] ?? p['lon'] ?? p['longitude'];
                final lat = latRaw is num ? latRaw.toDouble() : double.tryParse(latRaw?.toString() ?? '');
                final lng = lngRaw is num ? lngRaw.toDouble() : double.tryParse(lngRaw?.toString() ?? '');
                if (lat != null && lng != null) {
                  point = LatLng(lat, lng);
                }
                break;
              }
            }
          }
        }
      }

      if (point == null) {
        await _showMessage(
          'SOS Failed',
          'Live location not available yet. Please wait a few seconds and try again.',
        );
        return;
      }

      final dialogCtx = _navContext;
      if (dialogCtx == null) return;
      if (!dialogCtx.mounted) return;

      bool cancelled = false;
      bool completed = false;
      int attempt = 0;
      String statusText = 'Sending SOS…';
      Map<String, dynamic>? lastOkResponse;

      bool dialogOpen = true;
      void Function(void Function())? setDialogState;

      showDialog<void>(
        context: dialogCtx,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              setDialogState = setLocal;
              return AlertDialog(
                title: const Text('Sending SOS'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 12),
                    Text(statusText, textAlign: TextAlign.center),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelled = true;
                      dialogOpen = false;
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      ).then((_) {
        dialogOpen = false;
      });

      while (!cancelled && !completed) {
        attempt += 1;
        try {
          statusText = 'Sending SOS… (attempt $attempt)';
          try {
            setDialogState?.call(() {});
          } catch (_) {}

          final res = await ApiService.sendSosIncident(
            userId: userId,
            tripId: tripId,
            isDriver: isDriver,
            bookingId: isDriver ? null : bookingId,
            lat: point.latitude,
            lng: point.longitude,
            accuracy: null,
            note: null,
          );

          if (res['success'] == true) {
            lastOkResponse = res;
            completed = true;
            break;
          }

          final status = int.tryParse((res['status'] ?? '').toString());
          final err = (res['error'] ?? '').toString().trim();

          if (status != null && status >= 400 && status < 500) {
            statusText = err.isNotEmpty ? err : 'SOS request rejected (HTTP $status)';
            try {
              setDialogState?.call(() {});
            } catch (_) {}
            break;
          }

          statusText = err.isNotEmpty
              ? '$err (attempt $attempt). Retrying…'
              : 'Network/server slow (attempt $attempt). Retrying…';
          try {
            setDialogState?.call(() {});
          } catch (_) {}
        } catch (_) {
          statusText = 'Network timeout/server slow (attempt $attempt). Retrying…';
          try {
            setDialogState?.call(() {});
          } catch (_) {}
        }

        final waitSeconds = (attempt < 3)
            ? 2
            : (attempt < 6)
                ? 4
                : (attempt < 10)
                    ? 8
                    : 15;

        await Future.delayed(Duration(seconds: waitSeconds));
      }

      // Close progress dialog if still open
      try {
        if (dialogOpen) {
          final closeCtx = _navContext;
          if (closeCtx != null && closeCtx.mounted) {
            Navigator.of(closeCtx, rootNavigator: true).pop();
          }
        }
      } catch (_) {}

      if (cancelled) {
        await _showMessage('SOS Cancelled', 'SOS was cancelled.');
        return;
      }

      if (!completed) {
        await _showMessage('SOS Failed', statusText);
        return;
      }

      final shareUrl = (lastOkResponse?['share_url'] ?? '').toString().trim();
      final mapsUrl = (lastOkResponse?['maps_url'] ?? '').toString().trim();
      final notified = lastOkResponse?['notified'];

      final details = <String>[];
      if (notified is Map) {
        final emailOk = (notified['emergency_contact_email'] == true);
        final smsOk = (notified['emergency_contact_sms'] == true);
        final adminOk = (notified['admin_email'] == true);
        details.add('Emergency email: ${emailOk ? 'sent' : 'not sent'}');
        details.add('Emergency SMS: ${smsOk ? 'sent' : 'not sent'}');
        details.add('Admin email: ${adminOk ? 'sent' : 'not sent'}');
      }

      final navCtx2 = _navContext;
      if (navCtx2 == null) return;
      if (!navCtx2.mounted) return;

      await showDialog<void>(
        context: navCtx2,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('SOS Sent'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your SOS has been sent. Help is being notified.'),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final line in details)
                    Text(line, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
                if (shareUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('SOS Tracking Link', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SelectableText(shareUrl, style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
            actions: [
              if (shareUrl.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: shareUrl));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Link copied')));
                    }
                  },
                  child: const Text('Copy Link'),
                ),
              if (shareUrl.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final msg = mapsUrl.isNotEmpty
                        ? 'SOS tracking: $shareUrl\nLocation: $mapsUrl'
                        : 'SOS tracking: $shareUrl';
                    await Share.share(msg);
                  },
                  child: const Text('Share'),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      await _showMessage('SOS Failed', 'Unexpected error while sending SOS.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxX = (constraints.maxWidth - _size).clamp(0.0, double.infinity);
        final maxY = (constraints.maxHeight - _size).clamp(0.0, double.infinity);

        if (!_posInitialized) {
          _pos = Offset(maxX, maxY * 0.55);
          _posInitialized = true;
        }

        final clamped = Offset(
          _pos.dx.clamp(0.0, maxX),
          _pos.dy.clamp(0.0, maxY),
        );
        _pos = clamped;

        return Stack(
          children: [
            Positioned(
              left: _pos.dx,
              top: _pos.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _dragDistance = 0;
                },
                onPanUpdate: (d) {
                  _dragDistance += d.delta.distance;
                  setState(() {
                    _pos = Offset(
                      (_pos.dx + d.delta.dx).clamp(0.0, maxX),
                      (_pos.dy + d.delta.dy).clamp(0.0, maxY),
                    );
                  });
                },
                onPanEnd: (_) {
                  if (_dragDistance < 6) {
                    _triggerSos();
                  }
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(64),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SosCountdownDialog extends StatefulWidget {
  const _SosCountdownDialog();

  @override
  State<_SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<_SosCountdownDialog> {
  Timer? _timer;
  int _remaining = 3;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        _timer = null;
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _remaining -= 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Emergency SOS',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(31),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$_remaining',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sending SOS automatically…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
