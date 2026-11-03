import 'dart:convert';
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
        .asyncMap((data) async {
      // One check covers both directions (I blocked them / they blocked me)
      final isBlocked = await isBlockedEitherWay(otherUserId);

      return data
          .where((map) {
        final senderId = map['sender_id'];
        final receiverId = map['receiver_id'];

        final inThisChat =
            (senderId == myId && receiverId == otherUserId) ||
                (senderId == otherUserId && receiverId == myId);
        if (!inThisChat) return false;

        // Hide messages sent by the other user when a block exists
        if (isBlocked && senderId == otherUserId) return false;

        return true;
      })
          .map((map) => ChatMessage.fromMap(map, myId))
          .toList();
    });
  }

  Future<void> sendMessage(
      String receiverId,
      String text, {
        String? replyToId,
        String? replyToSender,
        String? replyToText,
        String? replyToImageUrl,
      }) async {
    final myId = currentUserId;
    if (myId == null) return;

    if (await isBlockedEitherWay(receiverId)) {
      throw Exception('Cannot send message: user is blocked.');
    }

    String finalMessageText = text;
    if (replyToSender != null || replyToText != null || replyToImageUrl != null) {
      finalMessageText = jsonEncode({
        'reply': {
          if (replyToId != null) 'id': replyToId,
          if (replyToSender != null) 'sender': replyToSender,
          if (replyToText != null) 'text': replyToText,
          if (replyToImageUrl != null) 'imageUrl': replyToImageUrl,
        },
        'text': text,
      });
    }

    final message = <String, dynamic>{
      'sender_id': myId,
      'receiver_id': receiverId,
      'message_text': finalMessageText,
    };

    if (replyToId != null) message['reply_to_id'] = replyToId;
    if (replyToSender != null) message['reply_to_sender'] = replyToSender;
    if (replyToText != null) message['reply_to_text'] = replyToText;
    if (replyToImageUrl != null) message['reply_to_image_url'] = replyToImageUrl;

    try {
      await _supabase.from('messages').insert(message);
    } catch (e) {
      debugPrint('Note: Insert with explicit reply_to columns failed, falling back to message payload: $e');
      await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': receiverId,
        'message_text': finalMessageText,
      });
    }
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

  Future<void> markAllMessagesAsRead() async {
    final myId = currentUserId;
    if (myId == null) return;

    try {
      await _supabase
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('receiver_id', myId)
          .filter('read_at', 'is', null);
    } catch (e) {
      debugPrint('Error marking all messages as read: $e');
    }
  }

  Future<void> sendImageMessage(
      String receiverId,
      File imageFile, {
        String? replyToId,
        String? replyToSender,
        String? replyToText,
        String? replyToImageUrl,
      }) async {
    final myId = currentUserId;
    if (myId == null) return;

    if (await isBlockedEitherWay(receiverId)) {
      throw Exception('Cannot send message: user is blocked.');
    }

    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '$myId/$fileName';

      await _supabase.storage.from('chat_images').upload(
        filePath,
        imageFile,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      final imageUrl = _supabase.storage.from('chat_images').getPublicUrl(filePath);

      String finalMessageText = '';
      if (replyToSender != null || replyToText != null || replyToImageUrl != null) {
        finalMessageText = jsonEncode({
          'reply': {
            if (replyToId != null) 'id': replyToId,
            if (replyToSender != null) 'sender': replyToSender,
            if (replyToText != null) 'text': replyToText,
            if (replyToImageUrl != null) 'imageUrl': replyToImageUrl,
          },
          'text': '',
        });
      }

      final message = <String, dynamic>{
        'sender_id': myId,
        'receiver_id': receiverId,
        'message_text': finalMessageText,
        'image_url': imageUrl,
      };

      if (replyToId != null) message['reply_to_id'] = replyToId;
      if (replyToSender != null) message['reply_to_sender'] = replyToSender;
      if (replyToText != null) message['reply_to_text'] = replyToText;
      if (replyToImageUrl != null) message['reply_to_image_url'] = replyToImageUrl;

      try {
        await _supabase.from('messages').insert(message);
      } catch (e) {
        debugPrint('Note: Insert with explicit reply_to columns failed, falling back to message payload: $e');
        await _supabase.from('messages').insert({
          'sender_id': myId,
          'receiver_id': receiverId,
          'message_text': finalMessageText,
          'image_url': imageUrl,
        });
      }
      updateLastSeen();
    } catch (e) {
      debugPrint('Error sending image message: $e');
      rethrow;
    }
  }

  Future<void> sendVideoMessage(
      String receiverId,
      File videoFile, {
        String? replyToId,
        String? replyToSender,
        String? replyToText,
        String? replyToImageUrl,
      }) async {
    final myId = currentUserId;
    if (myId == null) return;

    if (await isBlockedEitherWay(receiverId)) {
      throw Exception('Cannot send message: user is blocked.');
    }

    try {
      final ext = videoFile.path.split('.').last.toLowerCase();
      final validExt = (ext == 'mov' || ext == 'webm' || ext == 'm4v' || ext == 'mkv') ? ext : 'mp4';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$validExt';
      final filePath = '$myId/$fileName';

      await _supabase.storage.from('chat_images').upload(
        filePath,
        videoFile,
        fileOptions: FileOptions(
          cacheControl: '3600',
          upsert: false,
          contentType: 'video/$validExt',
        ),
      );

      final videoUrl = _supabase.storage.from('chat_images').getPublicUrl(filePath);

      String finalMessageText = '';
      if (replyToSender != null || replyToText != null || replyToImageUrl != null) {
        finalMessageText = jsonEncode({
          'reply': {
            if (replyToId != null) 'id': replyToId,
            if (replyToSender != null) 'sender': replyToSender,
            if (replyToText != null) 'text': replyToText,
            if (replyToImageUrl != null) 'imageUrl': replyToImageUrl,
          },
          'text': '',
        });
      }

      final message = <String, dynamic>{
        'sender_id': myId,
        'receiver_id': receiverId,
        'message_text': finalMessageText,
        'image_url': videoUrl,
      };

      if (replyToId != null) message['reply_to_id'] = replyToId;
      if (replyToSender != null) message['reply_to_sender'] = replyToSender;
      if (replyToText != null) message['reply_to_text'] = replyToText;
      if (replyToImageUrl != null) message['reply_to_image_url'] = replyToImageUrl;

      try {
        await _supabase.from('messages').insert(message);
      } catch (e) {
        debugPrint('Note: Insert with explicit reply_to columns failed, falling back to message payload: $e');
        await _supabase.from('messages').insert({
          'sender_id': myId,
          'receiver_id': receiverId,
          'message_text': finalMessageText,
          'image_url': videoUrl,
        });
      }
      updateLastSeen();
    } catch (e) {
      debugPrint('Error sending video message: $e');
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

  Future<Map<String, dynamic>?> getUserDetails(String userId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _userCache.containsKey(userId)) {
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

  Future<DateTime?> getLastSeen(String userId) async {
    try {
      final data = await _supabase
          .from('create_account')
          .select('last_seen')
          .eq('id', userId)
          .maybeSingle();
      if (data != null && data['last_seen'] != null) {
        final lastSeenStr = data['last_seen'].toString();
        if (_userCache.containsKey(userId)) {
          _userCache[userId]!['last_seen'] = lastSeenStr;
        }
        return DateTime.tryParse(lastSeenStr);
      }
    } catch (e) {
      debugPrint('Error getting last_seen for $userId: $e');
    }
    return null;
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

  Future<List<Map<String, dynamic>>> getChatSettings() async {
    final myId = currentUserId;
    if (myId == null) return [];
    try {
      final response = await _supabase
          .from('user_chat_settings')
          .select('target_user_id, is_pinned, is_archived, is_blocked')
          .eq('user_id', myId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Note: user_chat_settings query failed: $e');
      return [];
    }
  }

  /// Updates only MY settings row. No mirror row for the other user:
  /// RLS prevents writing rows for another user, and the database function
  /// `is_blocked_either_way` checks both directions anyway.
  Future<void> updateChatSetting({
    required String targetUserId,
    bool? isPinned,
    bool? isArchived,
    bool? isBlocked,
  }) async {
    final myId = currentUserId;
    if (myId == null) return;

    final data = <String, dynamic>{
      'user_id': myId,
      'target_user_id': targetUserId,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isArchived != null) 'is_archived': isArchived,
      if (isBlocked != null) 'is_blocked': isBlocked,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _supabase
          .from('user_chat_settings')
          .upsert(data, onConflict: 'user_id,target_user_id');
    } catch (e) {
      debugPrint('Upsert to user_chat_settings failed: $e');
      rethrow; // so the UI doesn't show "blocked" when it actually failed
    }
  }

  /// True if either user has blocked the other (calls the SQL function).
  Future<bool> isBlockedEitherWay(String otherUserId) async {
    final myId = currentUserId;
    if (myId == null) return false;
    try {
      final res = await _supabase.rpc('is_blocked_either_way', params: {
        'a': myId,
        'b': otherUserId,
      });
      return res == true;
    } catch (e) {
      debugPrint('isBlockedEitherWay failed: $e');
      return false;
    }
  }

  /// True only if I blocked them (reads my own row, which RLS allows).
  Future<bool> isUserBlocked(String otherUserId) async {
    final myId = currentUserId;
    if (myId == null) return false;
    try {
      final res = await _supabase
          .from('user_chat_settings')
          .select('is_blocked')
          .eq('user_id', myId)
          .eq('target_user_id', otherUserId)
          .maybeSingle();
      return res?['is_blocked'] == true;
    } catch (_) {
      return false;
    }
  }

  /// True only if THEY blocked me. Their row is hidden by RLS,
  /// so this works out the answer from the either-way check.
  Future<bool> isBlockedByOther(String otherUserId) async {
    final either = await isBlockedEitherWay(otherUserId);
    if (!either) return false;
    return !(await isUserBlocked(otherUserId));
  }
}