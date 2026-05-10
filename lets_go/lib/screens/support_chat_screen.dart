import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/time_format.dart';

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

  Future<void> _clearCurrentChat() async {
    final uid = _userId();
    final gid = _guestUserId();
    if (!_hasOwner()) return;

    final isBotTab = (_tabController.index == 0);
    final threadType = isBotTab ? 'BOT' : 'ADMIN';

    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear chat'),
            content: Text(
              isBotTab
                  ? 'This will clear all bot messages and reset the bot context. Continue?'
                  : 'This will clear all admin chat messages. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    try {
      final resp = await ApiService.clearSupportChat(
        userId: uid,
        guestUserId: gid > 0 ? gid : null,
        threadType: threadType,
      );
      if ((resp['success'] ?? false) != true) {
        throw Exception(resp['error'] ?? 'Failed');
      }

      setState(() {
        if (isBotTab) {
          _botMessages.clear();
          _lastBotId = 0;
          _botController.clear();
        } else {
          _adminMessages.clear();
          _lastAdminId = 0;
          _adminLastSeenId = 0;
          _adminController.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear chat: $e')),
      );
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

  String _formatMessageTime(Map<String, dynamic> m) {
    final raw = (m['created_at'] ?? '').toString();
    try {
      final dt = DateTime.parse(raw).toLocal();
      return TimeFormat.amPmCompactFromDateTime(dt);
    } catch (_) {
      return '';
    }
  }

  String _displayTextForBot(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'\btrip_id\s*=\s*', caseSensitive: false), 'Trip ');
    t = t.replaceAll(RegExp(r'\bbooking_id\s*=\s*', caseSensitive: false), 'Booking ');
    t = t.replaceAll(RegExp(r'\bvehicle_id\s*=\s*', caseSensitive: false), 'Vehicle ');
    return t;
  }

  List<String> _extractIds(String text, String key) {
    final matches = RegExp('${RegExp.escape(key)}\\s*=\\s*([^\\s|,]+)', caseSensitive: false)
        .allMatches(text);
    return matches.map((m) => (m.group(1) ?? '').trim()).where((x) => x.isNotEmpty).toList();
  }

  List<MapEntry<String, String>> _extractKeyValueLines(List<String> lines) {
    final out = <MapEntry<String, String>>[];
    for (final line in lines) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final k = line.substring(0, idx).trim();
      final v = line.substring(idx + 1).trim();
      if (k.isEmpty || v.isEmpty) continue;
      if (k.length > 32) continue;
      out.add(MapEntry(k, v));
    }
    return out;
  }

  Widget _botActionChips(String rawText) {
    final chips = <Widget>[];

    void addPrefillChip(String label, String text) {
      chips.add(
        ActionChip(
          label: Text(label),
          onPressed: () {
            _botController.text = text;
            _botController.selection = TextSelection.fromPosition(
              TextPosition(offset: _botController.text.length),
            );
          },
        ),
      );
    }

    final vehicleIds = _extractIds(rawText, 'vehicle_id');
    for (final vid in vehicleIds.take(4)) {
      addPrefillChip('Use vehicle $vid', vid);
    }

    if (rawText.toLowerCase().contains('faqs')) {
      addPrefillChip('Show FAQs', 'show faqs');
    }
    if (rawText.toLowerCase().contains('user manual') || rawText.toLowerCase().contains('manual')) {
      addPrefillChip('Manual topics', 'user manual topics');
    }
    if (rawText.toLowerCase().contains('bookings')) {
      addPrefillChip('My bookings', 'my bookings');
    }
    if (rawText.toLowerCase().contains('rides') || rawText.toLowerCase().contains('trips')) {
      addPrefillChip('My rides', 'my rides');
    }
    if (rawText.toLowerCase().contains('vehicles')) {
      addPrefillChip('My vehicles', 'my vehicles');
    }
    if (rawText.toLowerCase().contains('profile')) {
      addPrefillChip('My profile', 'my profile');
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  Widget _renderBotContent(String rawText) {
    final text = _displayTextForBot(rawText);
    final lines = text.split('\n');
    final bulletLines = lines.where((l) => l.trimLeft().startsWith('- ')).toList();
    final isBulletList = bulletLines.length >= 2;

    final kv = _extractKeyValueLines(lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList());
    final isKeyValue = kv.length >= 2 && kv.length == lines.where((l) => l.trim().isNotEmpty).length;

    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: Colors.grey[900],
    );

    if (rawText.trimLeft().startsWith('{') && rawText.trimRight().endsWith('}')) {
      return Text(text, style: monoStyle);
    }

    if (isKeyValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in kv)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      row.key,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.value,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          _botActionChips(rawText),
        ],
      );
    }

    if (isBulletList) {
      String? title;
      final firstNonEmpty = lines.firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => '',
      );
      if (firstNonEmpty.trim().endsWith(':')) {
        title = firstNonEmpty.trim().substring(0, firstNonEmpty.trim().length - 1);
      }
      final items = bulletLines
          .map((l) => l.trimLeft().replaceFirst('- ', '').trim())
          .where((x) => x.isNotEmpty)
          .toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(
                              top: BorderSide(color: Colors.grey.shade200),
                            ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 7),
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            items[i],
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _botActionChips(rawText),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
          ),
        ),
        _botActionChips(rawText),
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final isMe = _isMe(m);
    final text = (m['message_text'] ?? '').toString();
    final time = _formatMessageTime(m);

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
            if (isMe)
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              )
            else
              _renderBotContent(text),
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
    Widget? header,
  }) {
    return Column(
      children: [
        if (header != null) header,
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
          IconButton(
            onPressed: _clearCurrentChat,
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear chat',
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
