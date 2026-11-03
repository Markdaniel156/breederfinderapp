import 'dart:convert';

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

  final String? replyToId;
  final String? replyToSender;
  final String? replyToText;
  final String? replyToImageUrl;

  bool get isVideo {
    if (imageUrl == null || imageUrl!.isEmpty) return false;
    final lower = imageUrl!.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.contains('.mp4?') ||
        lower.contains('.mov?') ||
        lower.contains('.webm?');
  }

  bool get replyToIsVideo {
    if (replyToImageUrl == null || replyToImageUrl!.isEmpty) return false;
    final lower = replyToImageUrl!.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.contains('.mp4?') ||
        lower.contains('.mov?') ||
        lower.contains('.webm?');
  }

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
    this.replyToId,
    this.replyToSender,
    this.replyToText,
    this.replyToImageUrl,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String currentUserId) {
    String rawText = map['message_text']?.toString() ?? '';
    String? replyToId = map['reply_to_id']?.toString();
    String? replyToSender = map['reply_to_sender']?.toString();
    String? replyToText = map['reply_to_text']?.toString();
    String? replyToImageUrl = map['reply_to_image_url']?.toString();

    if (rawText.startsWith('{"reply":')) {
      try {
        final decoded = jsonDecode(rawText);
        if (decoded is Map && decoded.containsKey('reply')) {
          final r = decoded['reply'];
          if (r is Map) {
            replyToId ??= r['id']?.toString();
            replyToSender ??= r['sender']?.toString();
            replyToText ??= r['text']?.toString();
            replyToImageUrl ??= r['imageUrl']?.toString();
          }
          rawText = decoded['text']?.toString() ?? '';
        }
      } catch (_) {}
    }

    return ChatMessage(
      id: map['id'].toString(),
      senderId: map['sender_id'].toString(),
      receiverId: map['receiver_id'].toString(),
      text: rawText,
      imageUrl: map['image_url']?.toString(),
      createdAt: DateTime.parse(map['created_at']),
      readAt: map['read_at'] != null ? DateTime.parse(map['read_at']) : null,
      isMe: map['sender_id'] == currentUserId,
      isDeleted: map['is_deleted'] == true,
      replyToId: replyToId,
      replyToSender: replyToSender,
      replyToText: replyToText,
      replyToImageUrl: replyToImageUrl,
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
      'reply_to_id': replyToId,
      'reply_to_sender': replyToSender,
      'reply_to_text': replyToText,
      'reply_to_image_url': replyToImageUrl,
    };
  }
}
