class ChatMessage {
  final int id;
  final String tripId;
  final int senderId;
  final String senderName;
  final String senderRole;
  final int? recipientId;
  final String messageText;
  final String messageType;
  final bool isBroadcast;
  final DateTime createdAt;
  final bool isRead;
  final bool isReadByOther;
  final String localStatus;

  // For compatibility with existing screens that expect targetUserIds
  List<int>? get targetUserIds => recipientId != null ? [recipientId!] : null;

  ChatMessage({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.recipientId,
    required this.messageText,
    required this.messageType,
    required this.isBroadcast,
    required this.createdAt,
    required this.isRead,
    this.isReadByOther = false,
    this.localStatus = 'sent',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      tripId: (json['trip_id'] ?? '').toString(),
      senderId: (json['sender_id'] as num).toInt(),
      senderName: (json['sender_name'] ?? '').toString(),
      senderRole: (json['sender_role'] ?? '').toString(),
      recipientId: json['recipient_id'] != null
          ? (json['recipient_id'] as num).toInt()
          : null,
      messageText: (json['message_text'] ?? '').toString(),
      messageType: (json['message_type'] ?? 'TEXT').toString(),
      isBroadcast: json['is_broadcast'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] == true,
      isReadByOther: json['is_read_by_other'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'recipient_id': recipientId,
      'message_text': messageText,
      'message_type': messageType,
      'is_broadcast': isBroadcast,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'is_read_by_other': isReadByOther,
    };
  }
}
