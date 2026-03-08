import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import '../../utils/image_utils.dart';

class DriverIndividualChatScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String tripId;
  final String chatRoomId;
  final Map<String, dynamic> passengerInfo;

  const DriverIndividualChatScreen({
    super.key,
    required this.userData,
    required this.tripId,
    required this.chatRoomId,
    required this.passengerInfo,
  });

  @override
  State<DriverIndividualChatScreen> createState() =>
      _DriverIndividualChatScreenState();
}

class _DriverIndividualChatScreenState
    extends State<DriverIndividualChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessage> messages = [];
  bool isLoading = true;
  bool isSending = false;
  dynamic _subscription;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _unsubscribe();
    super.dispose();
  }

  Future<void> _initChat() async {
    await _loadMessages();
    _subscribeToMessages();
    await _markMessagesAsRead();
  }

  Future<void> _loadMessages() async {
    setState(() => isLoading = true);

    try {
      final driverId = int.tryParse(
            widget.userData['id']?.toString() ?? '',
          ) ??
          0;
      final passengerId = int.tryParse(
            widget.passengerInfo['id']?.toString() ??
                widget.passengerInfo['user_id']?.toString() ??
                '',
          ) ??
          0;

      final allMessages = await ChatService.getMessages(
        chatRoomId: widget.chatRoomId,
        userId: driverId,
        otherId: passengerId,
      );

      // Filter messages between this driver and this passenger
      final filteredMessages = allMessages.where((msg) {
        // Messages sent by driver to this passenger
        if (msg.senderId == driverId &&
            (msg.targetUserIds == null ||
                msg.targetUserIds!.contains(passengerId))) {
          return true;
        }
        // Messages sent by passenger to this driver
        if (msg.senderId == passengerId &&
            (msg.targetUserIds == null ||
                msg.targetUserIds!.contains(driverId))) {
          return true;
        }
        return false;
      }).toList();

      filteredMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // ignore: avoid_print
      debugPrint('[DriverChat] initial load messages.length = ${filteredMessages.length}');

      setState(() {
        messages = filteredMessages;
        isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void _subscribeToMessages() {
    final driverId = int.tryParse(
          widget.userData['id']?.toString() ?? '',
        ) ??
        0;
    final passengerId = int.tryParse(
          widget.passengerInfo['id']?.toString() ??
              widget.passengerInfo['user_id']?.toString() ??
              '',
        ) ??
        0;

    _subscription = ChatService.subscribeToMessages(
      chatRoomId: widget.chatRoomId,
      userId: driverId,
      otherId: passengerId,
      onNewMessage: (message) {
        final isBetweenDriverAndPassenger =
            (message.senderId == driverId &&
                    (message.targetUserIds == null ||
                        message.targetUserIds!.contains(passengerId))) ||
                (message.senderId == passengerId &&
                    (message.targetUserIds == null ||
                        message.targetUserIds!.contains(driverId)));

        if (isBetweenDriverAndPassenger) {
          setState(() {
            final idx = messages.indexWhere((m) => m.id == message.id);
            if (idx >= 0) {
              messages[idx] = message;
            } else {
              messages.add(message);
            }
          });
          _scrollToBottom();

          // Mark as read if from passenger
          if (message.senderId == passengerId) {
            ChatService.markMessageAsRead(
              messageId: message.id,
              userId: driverId,
            );
          }
        }
      },
      onError: (error) {
        // ignore: avoid_print
        debugPrint('Driver chat subscription error: $error');
      },
    );
  }

  void _unsubscribe() {
    if (_subscription != null) {
      ChatService.unsubscribeFromMessages(widget.chatRoomId);
    }
  }

  Future<void> _markMessagesAsRead() async {
    final driverId = int.tryParse(
          widget.userData['id']?.toString() ?? '',
        ) ??
        0;

    final passengerId = int.tryParse(
          widget.passengerInfo['id']?.toString() ??
              widget.passengerInfo['user_id']?.toString() ??
              '',
        ) ??
        0;
    for (var message in messages) {
      if (message.senderId == passengerId && !message.isRead) {
        await ChatService.markMessageAsRead(
          messageId: message.id,
          userId: driverId,
        );
      }
    }

    await ChatService.updateLastReadTime(
      chatRoomId: widget.chatRoomId,
      userId: driverId,
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final driverId = int.tryParse(
          widget.userData['id']?.toString() ?? '',
        ) ??
        0;
    final driverName = widget.userData['name']?.toString() ?? 'Driver';

    final passengerId = int.tryParse(
          widget.passengerInfo['id']?.toString() ??
              widget.passengerInfo['user_id']?.toString() ??
              '',
        ) ??
        0;
    final text = _messageController.text.trim();

    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tempMessage = ChatMessage(
      id: tempId,
      tripId: widget.chatRoomId,
      senderId: driverId,
      senderName: driverName,
      senderRole: 'driver',
      recipientId: passengerId,
      messageText: text,
      messageType: 'text',
      isBroadcast: false,
      createdAt: DateTime.now(),
      isRead: false,
      isReadByOther: false,
      localStatus: 'sending',
    );

    setState(() {
      isSending = true;
      messages.add(tempMessage);
    });
    _scrollToBottom();

    try {
      final sent = await ChatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: driverId,
        senderName: driverName,
        senderRole: 'driver',
        messageText: text,
        messageType: 'text',
        isBroadcast: false,
        targetUserIds: [passengerId],
      );

      _messageController.clear();
      if (!mounted) return;
      setState(() {
        messages.removeWhere((m) => m.id == sent.id);
        final idx = messages.indexWhere((m) => m.id == tempId);
        if (idx >= 0) {
          messages[idx] = sent;
        } else {
          messages.add(sent);
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = messages.indexWhere((m) => m.id == tempId);
          if (idx >= 0) {
            final failed = ChatMessage(
              id: tempMessage.id,
              tripId: tempMessage.tripId,
              senderId: tempMessage.senderId,
              senderName: tempMessage.senderName,
              senderRole: tempMessage.senderRole,
              recipientId: tempMessage.recipientId,
              messageText: tempMessage.messageText,
              messageType: tempMessage.messageType,
              isBroadcast: tempMessage.isBroadcast,
              createdAt: tempMessage.createdAt,
              isRead: tempMessage.isRead,
              isReadByOther: tempMessage.isReadByOther,
              localStatus: 'failed',
            );
            messages[idx] = failed;
          }
        });
      }
    } finally {
      setState(() => isSending = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final passengerName = widget.passengerInfo['name']?.toString() ??
        widget.passengerInfo['full_name']?.toString() ??
        'Passenger';
    final passengerRating =
        widget.passengerInfo['passenger_rating']?.toString() ?? 'N/A';

    final rawPhoto = widget.passengerInfo['profile_photo'] ??
        widget.passengerInfo['photo_url'] ??
        widget.passengerInfo['profile_image'];
    final passengerPhotoUrl =
        ImageUtils.ensureValidImageUrl(rawPhoto?.toString());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(passengerName),
            Row(
              children: [
                const Icon(Icons.star, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  passengerRating,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (isLoading)
            const LinearProgressIndicator(),
          Expanded(
            child: Column(
              children: [
                // Passenger info header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.teal,
                        radius: 24,
                        backgroundImage: (passengerPhotoUrl != null &&
                                ImageUtils.isValidImageUrl(passengerPhotoUrl))
                            ? NetworkImage(passengerPhotoUrl)
                            : null,
                        child: (passengerPhotoUrl == null ||
                                !ImageUtils.isValidImageUrl(passengerPhotoUrl))
                            ? Text(
                                passengerName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              passengerName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    size: 16, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  passengerRating,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.teal,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Passenger',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Messages list
                Expanded(
                  child: messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final driverId = int.tryParse(
                                  widget.userData['id']?.toString() ?? '',
                                ) ??
                                0;
                            final isMe = message.senderId == driverId;

                            bool showDateSeparator = false;
                            if (index == 0) {
                              showDateSeparator = true;
                            } else {
                              final prevMessage = messages[index - 1];
                              showDateSeparator = !_isSameDay(
                                message.createdAt,
                                prevMessage.createdAt,
                              );
                            }

                            return Column(
                              children: [
                                if (showDateSeparator)
                                  _buildDateSeparator(message.createdAt),
                                _buildMessageBubble(message, isMe),
                              ],
                            );
                          },
                        ),
                ),

                // Input bar
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
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton(
                        onPressed: isSending ? null : _sendMessage,
                        backgroundColor: Colors.teal,
                        mini: true,
                        child: isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate == today) {
      dateText = 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      dateText = 'Yesterday';
    } else {
      dateText = DateFormat('MMM dd, yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              dateText,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    Widget? statusIcon;
    if (isMe) {
      if (message.localStatus == 'sending') {
        statusIcon = const Icon(Icons.access_time, size: 14, color: Colors.white70);
      } else if (message.localStatus == 'failed') {
        statusIcon = const Icon(Icons.error_outline, size: 14, color: Colors.white70);
      } else if (message.isReadByOther) {
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
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.messageText,
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
                  DateFormat('hh:mm a').format(message.createdAt.toLocal()),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation with your passenger',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}