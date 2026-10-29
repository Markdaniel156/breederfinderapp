import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';

class ChatService {
  final _supabase = Supabase.instance.client;
  static final Map<String, Map<String, dynamic>> _userCache = {};

  static Map<String, Map<String, dynamic>> getUserCache() => _userCache;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Stream<List<ChatMessage>> getMessagesStream(String otherUserId) {
    final myId = currentUserId;
    if (myId == null) return Stream.value([]);

    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) {
      return data
          .where((map) =>
      (map['sender_id'] == myId && map['receiver_id'] == otherUserId) ||
          (map['sender_id'] == otherUserId && map['receiver_id'] == myId))
          .map((map) => ChatMessage.fromMap(map, myId))
          .toList();
    });
  }

  Future<void> sendMessage(String receiverId, String text) async {
    final myId = currentUserId;
    if (myId == null) return;

    final message = {
      'sender_id': myId,
      'receiver_id': receiverId,
      'message_text': text,
    };

    await _supabase.from('messages').insert(message);
    updateLastSeen();
  }

  Future<void> markMessagesAsRead(String senderId) async {
    final myId = currentUserId;
    if (myId == null) return;

    try {
      await _supabase
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('sender_id', senderId)
          .eq('receiver_id', myId)
          .filter('read_at', 'is', null);
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> sendImageMessage(String receiverId, File imageFile) async {
    final myId = currentUserId;
    if (myId == null) return;

    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '$myId/$fileName';

      await _supabase.storage.from('chat_images').upload(
        filePath,
        imageFile,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      final imageUrl = _supabase.storage.from('chat_images').getPublicUrl(filePath);

      final message = {
        'sender_id': myId,
        'receiver_id': receiverId,
        'message_text': '',
        'image_url': imageUrl,
      };

      await _supabase.from('messages').insert(message);
      updateLastSeen();
    } catch (e) {
      debugPrint('Error sending image message: $e');
      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      // We only set is_deleted to true. 
      // We keep the original data for a moment so the UI knows if it was a photo or text
      // but the UI will hide the content because is_deleted is true.
      await _supabase
          .from('messages')
          .update({'is_deleted': true})
          .eq('id', messageId);
    } catch (e) {
      debugPrint('Error deleting message: $e');
      rethrow;
    }
  }

  Future<void> deleteConversation(String otherUserId) async {
    final myId = currentUserId;
    if (myId == null) return;

    try {
      try {
        await _supabase
            .from('messages')
            .delete()
            .eq('sender_id', myId)
            .eq('receiver_id', otherUserId);
      } catch (e) {
        debugPrint('Note: Could not delete sent messages: $e');
      }

      try {
        await _supabase
            .from('messages')
            .delete()
            .eq('sender_id', otherUserId)
            .eq('receiver_id', myId);
      } catch (e) {
        debugPrint('Note: Could not delete received messages: $e');
      }
    } catch (e) {
      debugPrint('Error in deleteConversation: $e');
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> getConversationsStream() {
    final myId = currentUserId;
    if (myId == null) return Stream.value([]);

    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) {
      final Map<String, Map<String, dynamic>> lastMessages = {};

      for (var msg in data) {
        if (msg['sender_id'] == myId || msg['receiver_id'] == myId) {
          final otherId = msg['sender_id'] == myId ? msg['receiver_id'] : msg['sender_id'];
          if (!lastMessages.containsKey(otherId)) {
            lastMessages[otherId] = msg;
          }
        }
      }

      return lastMessages.values.toList();
    });
  }

  bool _isValidName(dynamic name) {
    if (name == null) return false;
    final s = name.toString().trim();
    // Allow "User" if it's at least something, but prefer real names
    return s.isNotEmpty && s != '...' && s != 'Loading...';
  }

  String _resolveAvatarUrl(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.trim().isEmpty) return '';
    if (avatarUrl.startsWith('http')) return avatarUrl;
    return _supabase.storage.from('avatars').getPublicUrl(avatarUrl);
  }

  Future<Map<String, dynamic>?> getUserDetails(String userId) async {
    if (_userCache.containsKey(userId)) {
      final cached = _userCache[userId];
      if (cached != null && _isValidName(cached['full_name']) && cached['full_name'] != 'User') {
        return cached;
      }
    }

    String? bestName;
    String? bestAvatar;
    String? lastSeen;

    try {
      // 1. Try create_account (Primary source for all users)
      try {
        final accountData = await _supabase
            .from('create_account')
            .select('full_name, avatar_url, last_seen')
            .eq('id', userId)
            .maybeSingle();
        
        if (accountData != null) {
          bestName = accountData['full_name']?.toString();
          bestAvatar = accountData['avatar_url']?.toString();
          lastSeen = accountData['last_seen']?.toString();
        }
      } catch (e) {
        debugPrint('Note: Error fetching from create_account (column last_seen might be missing): $e');
        // Fallback: fetch without last_seen if it failed
        final fallbackAccount = await _supabase
            .from('create_account')
            .select('full_name, avatar_url')
            .eq('id', userId)
            .maybeSingle();
        if (fallbackAccount != null) {
          bestName = fallbackAccount['full_name']?.toString();
          bestAvatar = fallbackAccount['avatar_url']?.toString();
        }
      }

      // 2. Try Breeder table (High priority for business names)
      final breederData = await _supabase
          .from('breeder_postings')
          .select('full_name, avatar_url')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      if (breederData != null) {
        final name = breederData['full_name']?.toString();
        if (_isValidName(name) && name != 'User') bestName = name;
        if (breederData['avatar_url'] != null) bestAvatar = breederData['avatar_url'];
      }

      // 3. Try Trader table
      final traderData = await _supabase
          .from('trader_postings')
          .select('full_name, avatar_url')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      if (traderData != null) {
        final name = traderData['full_name']?.toString();
        if (_isValidName(name) && name != 'User') bestName = name;
        if (traderData['avatar_url'] != null) bestAvatar = traderData['avatar_url'];
      }

      final combined = <String, dynamic>{
        'id': userId,
        'full_name': _isValidName(bestName) ? bestName! : 'User',
        'avatar_url': _resolveAvatarUrl(bestAvatar),
        if (lastSeen != null) 'last_seen': lastSeen,
      };

      if (combined['full_name'] != 'User') {
        _userCache[userId] = combined;
      }
      return combined;
    } catch (e) {
      debugPrint('Error in getUserDetails($userId): $e');
      return {'id': userId, 'full_name': 'User', 'avatar_url': ''};
    }
  }

  Future<void> updateLastSeen() async {
    final myId = currentUserId;
    if (myId == null) return;
    try {
      await _supabase
          .from('create_account')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', myId);
    } catch (e) {
      debugPrint('Error updating last seen: $e');
    }
  }
}