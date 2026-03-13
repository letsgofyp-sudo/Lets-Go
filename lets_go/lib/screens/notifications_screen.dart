import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const NotificationsScreen({
    super.key,
    required this.userData,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  int _unreadCount = 0;
  bool _loading = true;
  Timer? _timer;

  int _getUserId() {
    final v = widget.userData['id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<int> _getGuestUserId() async {
    final v = widget.userData['guest_user_id'];
    final parsed = v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    if (parsed > 0) return parsed;
    try {
      final prefs = await SharedPreferences.getInstance();
      return int.tryParse((prefs.getString('guest_user_id') ?? '').toString()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final uid = _getUserId();
    final gid = uid > 0 ? 0 : await _getGuestUserId();
    if (uid <= 0 && gid <= 0) return;

    if (!silent) setState(() => _loading = true);
    try {
      final resp = await ApiService.listNotifications(userId: uid > 0 ? uid : null, guestUserId: gid > 0 ? gid : null);
      if (resp['success'] == true) {
        final list = (resp['notifications'] as List?) ?? [];
        setState(() {
          _items = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          _unreadCount = (resp['unread_count'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      // ignore errors
    } finally {
      if (!silent) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await ApiService.markNotificationRead(notificationId: id);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _dismiss(int id) async {
    try {
      await ApiService.dismissNotification(notificationId: id);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _markAllRead() async {
    final uid = _getUserId();
    final gid = uid > 0 ? 0 : await _getGuestUserId();
    if (uid <= 0 && gid <= 0) return;
    try {
      await ApiService.markAllNotificationsRead(userId: uid > 0 ? uid : null, guestUserId: gid > 0 ? gid : null);
    } catch (_) {}
    await _load();
  }

  void _handleTap(Map<String, dynamic> n) {
    final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final type = (data['type'] ?? n['notification_type'] ?? '').toString();

    // Mark as read immediately for UX
    final id = (n['id'] as num?)?.toInt() ?? 0;
    if (id > 0) {
      unawaited(_markRead(id));
    }

    // Navigate to relevant screens if possible
    if (type == 'chat_message') {
      final tripId = (data['trip_id'] ?? '').toString();
      if (tripId.isNotEmpty) {
        Navigator.pushNamed(
          context,
          '/ride_booking_details',
          arguments: {
            'userData': widget.userData,
            'tripId': tripId,
          },
        );
      }
      return;
    }

    if (type == 'ride_request') {
      final tripId = (data['trip_id'] ?? '').toString();
      if (tripId.isNotEmpty) {
        Navigator.pushNamed(
          context,
          '/ride_booking_details',
          arguments: {
            'userData': widget.userData,
            'tripId': tripId,
          },
        );
      }
      return;
    }

    if (type == 'support_admin' || type == 'support_bot') {
      Navigator.pushNamed(context, '/support-chat', arguments: widget.userData);
      return;
    }

    if (type == 'notification_summary') {
      return;
    }

    // otherwise: do nothing
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Notifications',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 140),
                        Center(child: Text('No notifications')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final n = _items[i];
                        final id = (n['id'] as num?)?.toInt() ?? 0;
                        final title = (n['title'] ?? '').toString();
                        final body = (n['body'] ?? '').toString();
                        final isRead = n['is_read'] == true;
                        final data = (n['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                        final type = (data['type'] ?? n['notification_type'] ?? '').toString();

                        final senderName = (data['sender_name'] ?? data['name'] ?? '').toString().trim();
                        final senderPhotoUrl = (data['sender_photo_url'] ?? '').toString().trim();
                        final genericPhotoUrl = (data['photo_url'] ?? '').toString().trim();
                        final driverPhotoUrl = (data['driver_photo_url'] ?? '').toString().trim();
                        final passengerPhotoUrl = (data['passenger_photo_url'] ?? '').toString().trim();
                        final userPhotoUrl = (data['user_photo_url'] ?? '').toString().trim();
                        final initiator = (data['initiator'] ?? data['source'] ?? data['sender_type'] ?? '').toString().trim().toLowerCase();

                        ImageProvider? avatar;
                        Widget? avatarChild;

                        final isSupportAdmin = type == 'support_admin' || initiator == 'admin' || initiator == 'administration';
                        final isSupportBot = type == 'support_bot' || initiator == 'system' || initiator == 'bot';
                        final isAdminInitiated = type == 'support_admin' || type == 'user_status_updated' || type == 'change_request_reviewed';
                        final isSystemInitiated = type == 'support_bot' || type == 'notification_summary';

                        String resolvedPhotoUrl = '';
                        if (senderPhotoUrl.isNotEmpty) {
                          resolvedPhotoUrl = senderPhotoUrl;
                        } else if (!isSupportAdmin && !isSupportBot && genericPhotoUrl.isNotEmpty) {
                          resolvedPhotoUrl = genericPhotoUrl;
                        } else if (driverPhotoUrl.isNotEmpty) {
                          resolvedPhotoUrl = driverPhotoUrl;
                        } else if (passengerPhotoUrl.isNotEmpty) {
                          resolvedPhotoUrl = passengerPhotoUrl;
                        } else if (userPhotoUrl.isNotEmpty) {
                          resolvedPhotoUrl = userPhotoUrl;
                        }

                        if (resolvedPhotoUrl.isNotEmpty) {
                          avatar = NetworkImage(resolvedPhotoUrl);
                        } else if (isAdminInitiated) {
                          avatarChild = Image.asset('assets/images/admin_support.png', width: 28, height: 28);
                        } else if (isSystemInitiated || isSupportBot) {
                          avatarChild = Image.asset('assets/images/app_logo.png', width: 28, height: 28);
                        } else if (initiator == 'user' || initiator == 'driver' || initiator == 'passenger' || senderName.isNotEmpty) {
                          avatarChild = const Icon(Icons.person, size: 20);
                        } else {
                          avatarChild = const Icon(Icons.notifications_active, size: 20);
                        }

                        return Dismissible(
                          key: ValueKey('n-$id-$i'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) {
                            if (id > 0) _dismiss(id);
                          },
                          child: Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _handleTap(n),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Colors.grey.shade200,
                                      backgroundImage: avatar,
                                      child: avatar == null ? avatarChild : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title.isEmpty ? 'Notification' : title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                              if (!isRead)
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: const BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (senderName.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              senderName,
                                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Text(
                                            body,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Colors.grey.shade800),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
