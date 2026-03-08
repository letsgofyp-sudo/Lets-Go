import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/chat_models.dart';

/// Simple REST + polling based chat service.
///
/// Assumptions:
/// - chatRoomId is the same as backend trip_id (string).
/// - PassengerChatScreen filters messages for the specific driver/passenger
///   using senderId and recipientId, so backend returns all trip messages.
class ChatService {
  static final Map<String, Timer> _pollingTimers = {};
  static final Map<String, Set<int>> _seenMessageIds = {};
  static final Map<String, int> _lastMessageId = {};

  static Uri _buildUri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(url);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.port,
      path: '${base.path}$path',
      queryParameters: query,
    );
  }

  /// Fetch all chat messages for a given trip/chatRoom.
  static Future<List<ChatMessage>> getMessages({
    required String chatRoomId,
    int? userId,
    int? otherId,
  }) async {
    // Use the lightweight updates endpoint with since_id=0 so that
    // both initial load and polling share the same efficient backend
    // implementation.
    final uri = _buildUri(
      '/lets_go/chat/$chatRoomId/messages/updates/',
      {
        'since_id': '0',
        if (userId != null) 'user_id': userId.toString(),
        if (otherId != null) 'other_id': otherId.toString(),
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load messages: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Unknown error');
    }
    final List<dynamic> list = data['messages'] as List<dynamic>;
    return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetch only messages newer than the given message id for a trip/chatRoom.
  static Future<List<ChatMessage>> getNewMessages({
    required String chatRoomId,
    required int sinceId,
    int? userId,
    int? otherId,
  }) async {
    final uri = _buildUri(
      '/lets_go/chat/$chatRoomId/messages/updates/',
      {
        'since_id': sinceId.toString(),
        if (userId != null) 'user_id': userId.toString(),
        if (otherId != null) 'other_id': otherId.toString(),
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load new messages: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Unknown error');
    }
    final List<dynamic> list = data['messages'] as List<dynamic>;
    return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Send a simple text message.
  ///
  /// - chatRoomId: trip_id string
  /// - senderRole: 'passenger' or 'driver'
  /// - targetUserIds: first element is treated as recipient_id
  static Future<ChatMessage> sendMessage({
    required String chatRoomId,
    required int senderId,
    required String senderName,
    required String senderRole,
    required String messageText,
    required String messageType,
    required bool isBroadcast,
    List<int>? targetUserIds,
  }) async {
    if (messageText.trim().isEmpty) {
      throw ArgumentError('messageText must not be empty');
    }
    if (isBroadcast) {
      throw UnimplementedError('Broadcast chat is not implemented yet');
    }
    if (targetUserIds == null || targetUserIds.isEmpty) {
      throw ArgumentError('targetUserIds must contain at least one recipient');
    }
    final recipientId = targetUserIds.first;

    final uri = _buildUri('/lets_go/chat/$chatRoomId/messages/send/');
    final payload = {
      'sender_id': senderId,
      'recipient_id': recipientId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'message_text': messageText,
    };

    // ignore: avoid_print
    debugPrint('ChatService.sendMessage -> POST $uri payload=$payload');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 201) {
      dynamic body;
      try {
        body = json.decode(response.body);
      } catch (_) {
        body = response.body;
      }
      // ignore: avoid_print
      debugPrint('ChatService.sendMessage error: '
          'status=${response.statusCode}, body=$body');
      throw Exception(
        body is Map<String, dynamic>
            ? (body['error'] ?? 'Failed to send message')
            : 'Failed to send message (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic> && decoded['message'] is Map<String, dynamic>) {
      final message = ChatMessage.fromJson(decoded['message'] as Map<String, dynamic>);

      final key = chatRoomId;
      _seenMessageIds.putIfAbsent(key, () => <int>{});
      _seenMessageIds[key]!.add(message.id);
      final prevLast = _lastMessageId[key] ?? 0;
      if (message.id > prevLast) {
        _lastMessageId[key] = message.id;
      }

      return message;
    }
    throw Exception('Failed to parse send message response');
  }

  /// Send a broadcast message from driver to multiple passengers.
  static Future<void> sendBroadcast({
    required String chatRoomId,
    required int senderId,
    required String senderName,
    required String senderRole, // 'driver'
    required String messageText,
    required List<int> recipientIds,
  }) async {
    if (messageText.trim().isEmpty) return;
    if (recipientIds.isEmpty) {
      throw ArgumentError('recipientIds must not be empty for broadcast');
    }

    final uri = _buildUri('/lets_go/chat/$chatRoomId/messages/broadcast/');
    final payload = {
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'message_text': messageText,
      'recipient_ids': recipientIds,
    };

    // ignore: avoid_print
    debugPrint('ChatService.sendBroadcast -> POST $uri payload=$payload');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 201) {
      dynamic body;
      try {
        body = json.decode(response.body);
      } catch (_) {
        body = response.body;
      }
      // ignore: avoid_print
      debugPrint('ChatService.sendBroadcast error: '
          'status=${response.statusCode}, body=$body');
      throw Exception(
        body is Map<String, dynamic>
            ? (body['error'] ?? 'Failed to send broadcast')
            : 'Failed to send broadcast (${response.statusCode})',
      );
    }
  }

  /// Mark a single message as read for a user.
  static Future<void> markMessageAsRead({
    required int messageId,
    required int userId,
  }) async {
    final uri = _buildUri('/lets_go/chat/messages/$messageId/read/');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (response.statusCode != 200) {
      // Not fatal for UX; just log via exception
      throw Exception('Failed to mark message as read: ${response.statusCode}');
    }
  }

  /// No-op placeholder for compatibility with existing code.
  static Future<void> updateLastReadTime({
    required String chatRoomId,
    required int userId,
  }) async {
    // We already track read status per-message; nothing extra needed here.
    return;
  }

  /// Subscribe to messages using simple polling.
  /// Returns an opaque subscription id (timer key).
  static String subscribeToMessages({
    required String chatRoomId,
    int? userId,
    int? otherId,
    required void Function(ChatMessage) onNewMessage,
    void Function(Object error)? onError,
    Duration pollInterval = const Duration(seconds: 7),
  }) {
    final key = chatRoomId;
    _seenMessageIds.putIfAbsent(key, () => <int>{});

    // Cancel any existing timer for this chat
    _pollingTimers[key]?.cancel();

    var isFirstPoll = true;

    Future<void> poll() async {
      try {
        final seen = _seenMessageIds[key]!;

        if (isFirstPoll) {
          // On first poll, load the full list once to seed the
          // seen set and establish the lastMessageId, but do not
          // emit messages to the UI (screens already loaded them).
          final messages = await getMessages(
            chatRoomId: chatRoomId,
            userId: userId,
            otherId: otherId,
          );
          var maxId = 0;
          for (final m in messages) {
            seen.add(m.id);
            if (m.id > maxId) {
              maxId = m.id;
            }
          }
          _lastMessageId[key] = maxId;
          isFirstPoll = false;
          return;
        }

        final sinceId = _lastMessageId[key] ?? 0;
        final newMessages = sinceId > 0
            ? await getNewMessages(
                chatRoomId: chatRoomId,
                sinceId: sinceId,
                userId: userId,
                otherId: otherId,
              )
            : await getMessages(
                chatRoomId: chatRoomId,
                userId: userId,
                otherId: otherId,
              );

        for (final m in newMessages) {
          if (!seen.contains(m.id)) {
            seen.add(m.id);
            _lastMessageId[key] = m.id > (_lastMessageId[key] ?? 0)
                ? m.id
                : (_lastMessageId[key] ?? m.id);
            onNewMessage(m);
          }
        }
      } catch (e) {
        if (onError != null) {
          onError(e);
        }
      }
    }

    // Initial seed
    poll();

    final timer = Timer.periodic(pollInterval, (_) => poll());
    _pollingTimers[key] = timer;
    return key;
  }

  static void unsubscribeFromMessages(String chatRoomId) {
    final key = chatRoomId;
    _pollingTimers[key]?.cancel();
    _pollingTimers.remove(key);
    _seenMessageIds.remove(key);
    _lastMessageId.remove(key);
  }
}
