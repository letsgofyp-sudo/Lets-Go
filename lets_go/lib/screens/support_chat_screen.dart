import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class SupportChatScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const SupportChatScreen({
    super.key,
    required this.userData,
  });

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _botController = TextEditingController();
  final TextEditingController _adminController = TextEditingController();

  final ScrollController _botScroll = ScrollController();
  final ScrollController _adminScroll = ScrollController();

  bool _loadingBot = true;
  bool _loadingAdmin = true;

  bool _sendingBot = false;
  bool _sendingAdmin = false;

  List<Map<String, dynamic>> _botMessages = [];
  List<Map<String, dynamic>> _adminMessages = [];

  Timer? _pollTimer;
  int _lastBotId = 0;
  int _lastAdminId = 0;
  int _adminLastSeenId = 0;

  int _userId() {
    return int.tryParse(widget.userData['id']?.toString() ?? '') ??
        int.tryParse(widget.userData['user_id']?.toString() ?? '') ??
        0;
  }

  int _guestUserId() {
    return int.tryParse(widget.userData['guest_user_id']?.toString() ?? '') ?? 0;
  }

  bool _hasOwner() {
    return _userId() > 0 || _guestUserId() > 0;
  }

  Future<String?> _getCachedFcmToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString('fcm_token') ?? '').trim();
      if (token.isEmpty) return null;
      return token;
    } catch (_) {
      return null;
    }
  }

  void _applyAdminReadState() {
    if (_adminLastSeenId <= 0) return;
    var changed = false;
    for (final m in _adminMessages) {
      final senderType = (m['sender_type'] ?? '').toString().toUpperCase();
      final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
      if (senderType == 'USER' && id > 0 && id <= _adminLastSeenId) {
        if (m['is_read_by_other'] != true) {
          m['is_read_by_other'] = true;
          changed = true;
        }
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBot();
    _loadAdmin();

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollUpdates();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _botController.dispose();
    _adminController.dispose();
    _botScroll.dispose();
    _adminScroll.dispose();
    super.dispose();
  }

  int _getMaxId(List<Map<String, dynamic>> messages) {
    var maxId = 0;
    for (final m in messages) {
      final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
      if (id > maxId) maxId = id;
    }
    return maxId;
  }

  Future<void> _pollUpdates() async {
    final uid = _userId();
    final gid = _guestUserId();
    if (!_hasOwner()) return;
    if (!mounted) return;

    if (_loadingBot || _loadingAdmin) return;

    try {
      final resp = await ApiService.getSupportBotUpdates(
        userId: uid,
        guestUserId: gid > 0 ? gid : null,
        sinceId: _lastBotId,
      );
      final List<Map<String, dynamic>> newBot =
          List<Map<String, dynamic>>.from(resp['messages'] ?? []);
      if (newBot.isNotEmpty && mounted) {
        setState(() {
          for (final m in newBot) {
            final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
            if (id <= 0) {
              _botMessages.add(m);
              continue;
            }
            final idx = _botMessages.indexWhere(
              (x) => (int.tryParse(x['id']?.toString() ?? '') ?? 0) == id,
            );
            if (idx >= 0) {
              _botMessages[idx] = m;
            } else {
              _botMessages.add(m);
            }
          }
          _lastBotId = _getMaxId(_botMessages);
        });
        _scrollToBottom(_botScroll);
      }
    } catch (_) {
    }

    try {
      final resp = await ApiService.getSupportAdminUpdates(
        userId: uid,
        guestUserId: gid > 0 ? gid : null,
        sinceId: _lastAdminId,
      );
      final List<Map<String, dynamic>> newAdmin =
          List<Map<String, dynamic>>.from(resp['messages'] ?? []);
      _adminLastSeenId = int.tryParse(resp['admin_last_seen_id']?.toString() ?? '') ?? _adminLastSeenId;
      if (newAdmin.isNotEmpty && mounted) {
        setState(() {
          for (final m in newAdmin) {
            final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
            if (id <= 0) {
              _adminMessages.add(m);
              continue;
            }
            final idx = _adminMessages.indexWhere(
              (x) => (int.tryParse(x['id']?.toString() ?? '') ?? 0) == id,
            );
            if (idx >= 0) {
              _adminMessages[idx] = m;
            } else {
              _adminMessages.add(m);
            }
          }
          _lastAdminId = _getMaxId(_adminMessages);
        });
        _scrollToBottom(_adminScroll);
      }
      _applyAdminReadState();
    } catch (_) {
    }
  }

  Future<void> _loadBot() async {
    final uid = _userId();
    final gid = _guestUserId();
    if (!_hasOwner()) return;
    setState(() => _loadingBot = true);
    try {
      final resp = await ApiService.getSupportBotUpdates(
        userId: uid,
        guestUserId: gid > 0 ? gid : null,
        sinceId: 0,
      );
      final msgs = List<Map<String, dynamic>>.from(resp['messages'] ?? []);
      setState(() {
        _botMessages = msgs;
        _lastBotId = _getMaxId(_botMessages);
      });
      _scrollToBottom(_botScroll);
    } finally {
      if (mounted) setState(() => _loadingBot = false);
    }
  }

  Future<void> _loadAdmin() async {
    final uid = _userId();
    final gid = _guestUserId();
    if (!_hasOwner()) return;
    setState(() => _loadingAdmin = true);
    try {
      final resp = await ApiService.getSupportAdminUpdates(
        userId: uid,
        guestUserId: gid > 0 ? gid : null,
        sinceId: 0,
      );
      final msgs = List<Map<String, dynamic>>.from(resp['messages'] ?? []);
      _adminLastSeenId = int.tryParse(resp['admin_last_seen_id']?.toString() ?? '') ?? 0;
      setState(() {
        _adminMessages = msgs;
        _lastAdminId = _getMaxId(_adminMessages);
      });
      _applyAdminReadState();
      _scrollToBottom(_adminScroll);
    } finally {
      if (mounted) setState(() => _loadingAdmin = false);
    }
  }

  Future<void> _sendBot() async {
    final uid = _userId();
    final gid = _guestUserId();
    final text = _botController.text.trim();
    if (!_hasOwner() || text.isEmpty) return;

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tempMessage = {
      'id': tempId,
      'sender_type': 'USER',
      'message_text': text,
      'created_at': DateTime.now().toIso8601String(),
      'local_status': 'sending',
      'is_read_by_other': false,
    };

    setState(() {
      _sendingBot = true;
      _botMessages.add(tempMessage);
    });
    _scrollToBottom(_botScroll);
    try {
      final fcmToken = gid > 0 ? await _getCachedFcmToken() : null;
      final newMsgs = await ApiService.sendSupportBotMessage(
        userId: uid,
        guestUserId: gid > 0 ? gid : null,
        messageText: text,
        fcmToken: fcmToken,
      );
      _botController.clear();
      setState(() {
        _botMessages.removeWhere((m) => (m['id']?.toString() ?? '') == tempId.toString());
        final incomingIds = newMsgs
            .map((x) => int.tryParse(x['id']?.toString() ?? '') ?? 0)
            .where((id) => id > 0)
            .toSet();
        if (incomingIds.isNotEmpty) {
          _botMessages.removeWhere(
            (m) => incomingIds.contains(int.tryParse(m['id']?.toString() ?? '') ?? 0),
          );
        }
        _botMessages.addAll(newMsgs);
        _lastBotId = _getMaxId(_botMessages);
      });
      _scrollToBottom(_botScroll);
    } finally {
      if (mounted) setState(() => _sendingBot = false);
    }
  }

  Future<void> _sendAdmin() async {
    final uid = _userId();
    final gid = _guestUserId();
    final text = _adminController.text.trim();
    if (!_hasOwner() || text.isEmpty) return;

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tempMessage = {
      'id': tempId,
      'sender_type': 'USER',
      'message_text': text,
      'created_at': DateTime.now().toIso8601String(),
      'local_status': 'sending',
      'is_read_by_other': false,
    };

    setState(() {
      _sendingAdmin = true;
      _adminMessages.add(tempMessage);
    });
    _scrollToBottom(_adminScroll);
    try {
      final fcmToken = gid > 0 ? await _getCachedFcmToken() : null;
      final resp = await ApiService.sendSupportAdminMessage(
        userId: uid,
        guestUserId: gid > 0 ? gid : null,
        messageText: text,
        fcmToken: fcmToken,
      );
      _adminController.clear();
      final msg = resp['message'];
      if (msg is Map<String, dynamic>) {
        final serverId = int.tryParse(msg['id']?.toString() ?? '') ?? 0;
        setState(() {
          _adminMessages.removeWhere((m) => (m['id']?.toString() ?? '') == tempId.toString());
          if (serverId > 0) {
            _adminMessages.removeWhere(
              (m) => (int.tryParse(m['id']?.toString() ?? '') ?? 0) == serverId,
            );
          }
          _adminMessages.add(msg);
          _lastAdminId = _getMaxId(_adminMessages);
        });
      } else {
        await _loadAdmin();
      }
      _scrollToBottom(_adminScroll);
    } finally {
      if (mounted) setState(() => _sendingAdmin = false);
    }
  }

  void _scrollToBottom(ScrollController c) {
    if (!c.hasClients) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!c.hasClients) return;
      c.animateTo(
        c.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isMe(Map<String, dynamic> m) {
    final st = (m['sender_type'] ?? '').toString().toUpperCase();
    return st == 'USER';
  }

  String _formatTime(Map<String, dynamic> m) {
    final raw = (m['created_at'] ?? '').toString();
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  Widget _bubble(Map<String, dynamic> m) {
    final isMe = _isMe(m);
    final text = (m['message_text'] ?? '').toString();
    final time = _formatTime(m);

    Widget? statusIcon;
    if (isMe) {
      final localStatus = (m['local_status'] ?? '').toString();
      final isReadByOther = m['is_read_by_other'] == true;
      if (localStatus == 'sending') {
        statusIcon = const Icon(Icons.access_time, size: 14, color: Colors.white70);
      } else if (localStatus == 'failed') {
        statusIcon = const Icon(Icons.error_outline, size: 14, color: Colors.white70);
      } else if (isReadByOther) {
        statusIcon = const Icon(Icons.done_all, size: 14, color: Colors.lightBlueAccent);
      } else {
        statusIcon = const Icon(Icons.done, size: 14, color: Colors.white70);
      }
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
                if (statusIcon != null) ...[
                  const SizedBox(width: 6),
                  statusIcon,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatTab({
    required bool loading,
    required bool sending,
    required List<Map<String, dynamic>> messages,
    required ScrollController scroll,
    required TextEditingController input,
    required VoidCallback onSend,
    required String hint,
  }) {
    return Column(
      children: [
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'No messages yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _bubble(messages[index]),
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade300,
                offset: const Offset(0, -2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  decoration: InputDecoration(
                    hintText: hint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                onPressed: sending ? null : onSend,
                backgroundColor: Colors.teal,
                mini: true,
                child: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Support Chat',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bot'),
            Tab(text: 'Admin'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              _loadBot();
              _loadAdmin();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _chatTab(
            loading: _loadingBot,
            sending: _sendingBot,
            messages: _botMessages,
            scroll: _botScroll,
            input: _botController,
            onSend: _sendBot,
            hint: 'Ask the bot...',
          ),
          _chatTab(
            loading: _loadingAdmin,
            sending: _sendingAdmin,
            messages: _adminMessages,
            scroll: _adminScroll,
            input: _adminController,
            onSend: _sendAdmin,
            hint: 'Message admin support...',
          ),
        ],
      ),
    );
  }
}
