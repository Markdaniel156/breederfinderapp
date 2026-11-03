import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../services/chat_service.dart';

class ChatProvider with ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _chatService = ChatService();
  int _unreadCount = 0;
  StreamSubscription? _unreadSubscription;
  StreamSubscription? _authSubscription;
  RealtimeChannel? _messageChannel;
  String? _activeChatId;

  int get unreadCount => _unreadCount;

  ChatProvider() {
    _initAuthListener();
    _initUnreadListener();
    _initMessageRealtimeListener();
  }

  void setActiveChat(String? chatId) {
    _activeChatId = chatId;
    NotificationService.activeChatId = chatId;
  }

  void _initAuthListener() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed) {
        refresh();
      } else if (event == AuthChangeEvent.signedOut) {
        _unreadCount = 0;
        _unreadSubscription?.cancel();
        _messageChannel?.unsubscribe();
        notifyListeners();
      }
    });
  }

  void _initUnreadListener() {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    _unreadSubscription?.cancel();
    _unreadSubscription = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', myId)
        .map((data) => data.where((map) => map['read_at'] == null && map['is_deleted'] != true).length)
        .listen((count) {
          _unreadCount = count;
          notifyListeners();
        });
  }

  void _initMessageRealtimeListener() {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    _messageChannel?.unsubscribe();
    _messageChannel = _supabase
        .channel('new_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            final senderId = record['sender_id'] as String;

            // Only show notification if we are not currently chatting with this user
            if (senderId != _activeChatId) {
              final userDetails = await _chatService.getUserDetails(senderId);
              final senderName = userDetails?['full_name'] ?? 'Someone';
              
              String messageText = record['message_text']?.toString() ?? '';
              if (messageText.startsWith('{"reply":')) {
                try {
                  final decoded = jsonDecode(messageText);
                  if (decoded is Map && decoded.containsKey('text')) {
                    messageText = decoded['text']?.toString() ?? '';
                  }
                } catch (_) {}
              }

              if (messageText.trim().isEmpty) {
                if (record['image_url'] != null) {
                  final url = record['image_url'].toString().toLowerCase();
                  final isVid = url.endsWith('.mp4') || url.endsWith('.mov') || url.endsWith('.webm') || url.contains('.mp4?');
                  messageText = isVid ? 'Sent you a video' : 'Sent you a photo';
                } else {
                  messageText = 'Sent you a message';
                }
              }

              NotificationService.showMessageNotification(
                id: record['id'].hashCode,
                title: senderName,
                body: messageText,
                payload: 'chat:$senderId',
              );
            }
          },
        );
    _messageChannel!.subscribe();
  }

  @override
  void dispose() {
    _unreadSubscription?.cancel();
    _authSubscription?.cancel();
    _messageChannel?.unsubscribe();
    super.dispose();
  }

  void refresh() {
    _initUnreadListener();
    _initMessageRealtimeListener();
  }
}
