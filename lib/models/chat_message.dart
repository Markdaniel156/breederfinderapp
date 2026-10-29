class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;
  final bool isMe;
  final bool isDeleted;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.imageUrl,
    required this.createdAt,
    this.readAt,
    required this.isMe,
    this.isDeleted = false,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    return ChatMessage(
      id: map['id'].toString(),
      senderId: map['sender_id'].toString(),
      receiverId: map['receiver_id'].toString(),
      text: map['message_text']?.toString() ?? '',
      imageUrl: map['image_url']?.toString(),
      createdAt: DateTime.parse(map['created_at']),
      readAt: map['read_at'] != null ? DateTime.parse(map['read_at']) : null,
      isMe: map['sender_id'] == currentUserId,
      isDeleted: map['is_deleted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_text': text,
      'image_url': imageUrl,
      'is_deleted': isDeleted,
      'read_at': readAt?.toIso8601String(),
    };
  }
}
