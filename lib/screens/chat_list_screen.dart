import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/breeder_provider.dart';
import '../models/breeder.dart';
import 'chat_screen.dart';
import '../services/chat_service.dart';
import '../services/presence_service.dart';
import '../utils/system_ui_utils.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final PresenceService _presenceService = PresenceService();
  final TextEditingController _searchController = TextEditingController();
  SharedPreferences? _prefs;
  bool _isOffline = false;
  bool _showArchivedOnly = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<Map<String, dynamic>> _cachedConversations = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _checkConnectivity();
    _loadCachedConversations();
    _chatService.markAllMessagesAsRead();
    _presenceService.addListener(_onPresenceChanged);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
      });
    });
  }

  void _onPresenceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCachedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString('cached_conversations');
    if (cached != null) {
      setState(() {
        _cachedConversations = List<Map<String, dynamic>>.from(jsonDecode(cached));
      });
    }
  }

  Future<void> _saveConversationsToCache(List<Map<String, dynamic>> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_conversations', jsonEncode(conversations));
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
      });
    }
  }

  @override
  void dispose() {
    _presenceService.removeListener(_onPresenceChanged);
    _connectivitySubscription.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {});
    _syncSettingsFromSupabase();
  }

  Future<void> _syncSettingsFromSupabase() async {
    try {
      final settings = await _chatService.getChatSettings();
      if (settings.isNotEmpty && _prefs != null) {
        final pinned = <String>[];
        final archived = <String>[];
        final blocked = <String>[];

        for (var row in settings) {
          final targetId = row['target_user_id']?.toString();
          if (targetId == null) continue;

          if (row['is_pinned'] == true) pinned.add(targetId);
          if (row['is_archived'] == true) archived.add(targetId);
          if (row['is_blocked'] == true) blocked.add(targetId);
        }

        await _prefs!.setStringList('pinned_chats', pinned);
        await _prefs!.setStringList('archived_chats', archived);
        await _prefs!.setStringList('blocked_chats', blocked);

        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Note: Syncing settings from Supabase skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final breederProvider = Provider.of<BreederProvider>(context);

    // Filter online breeders/traders (active in the app)
    final onlineBreeders = breederProvider.breeders.where((b) {
      if (b.userId == _chatService.currentUserId) return false;
      if (_isOffline) return true; // Show all cached breeders if offline to keep UI populated
      return _presenceService.isUserOnline(b.userId) ||
          (!_presenceService.isReady && b.lastSeen != null && DateTime.now().toUtc().difference(b.lastSeen!.toUtc()).inSeconds < 35);
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiUtils.getOverlayStyle(
          isDark: isDark,
          navBarColor: theme.scaffoldBackgroundColor,
        ),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              centerTitle: false,
              title: const Text(
                'Chats',
                style: TextStyle(
                  color: Color(0xFF2D6A4F),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF2D6A4F), size: 28),
                  onPressed: _showChatSettingsMenu,
                  tooltip: 'Chat Settings',
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (_isOffline) SliverToBoxAdapter(child: _buildOfflineBanner(isDark)),
            SliverToBoxAdapter(child: _buildSearchBar(isDark)),
            
            if (_searchQuery.isEmpty) ...[
              // Active Breeders and Traders Section (Only if any are online)
              if (onlineBreeders.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      'Active Breeders & Traders',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildOnlineUsersHorizontalList(onlineBreeders, isDark),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showArchivedOnly ? 'Archived Messages' : 'Messages',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (_prefs != null && ((_prefs!.getStringList('archived_chats')?.isNotEmpty == true) || _showArchivedOnly))
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showArchivedOnly = !_showArchivedOnly;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _showArchivedOnly ? Icons.chat_bubble_outline_rounded : Icons.archive_outlined,
                                  size: 16,
                                  color: const Color(0xFF2D6A4F),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showArchivedOnly ? 'All Chats' : 'Archived (${_prefs!.getStringList('archived_chats')?.length ?? 0})',
                                  style: const TextStyle(
                                    color: Color(0xFF2D6A4F),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _chatService.getConversationsStream(),
                builder: (context, snapshot) {
                  List<Map<String, dynamic>> conversations = snapshot.data ?? _cachedConversations;

                  if (snapshot.hasData) {
                    _saveConversationsToCache(snapshot.data!);
                  }

                  if (snapshot.connectionState == ConnectionState.waiting && conversations.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Center(child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(),
                      )),
                    );
                  }

                  if (snapshot.hasError && conversations.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text(
                                _isOffline ? 'Offline Mode' : 'Waiting for connection...',
                                style: TextStyle(color: Colors.grey[500], fontSize: 14),
                              ),
                              if (_isOffline) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Reconnect to see new messages',
                                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  
                  // Filter and Sort Conversations (Delete, Archive, Block, Pin)
                  if (_prefs != null) {
                    final pinnedList = _prefs!.getStringList('pinned_chats') ?? [];
                    final archivedList = _prefs!.getStringList('archived_chats') ?? [];
                    final blockedList = _prefs!.getStringList('blocked_chats') ?? [];

                    conversations = conversations.where((msg) {
                      final myId = _chatService.currentUserId;
                      final otherId = msg['sender_id'] == myId ? msg['receiver_id'] : msg['sender_id'];
                      
                      // Check block state
                      if (blockedList.contains(otherId)) return false;

                      // Check archive state
                      final isArchived = archivedList.contains(otherId);
                      if (_showArchivedOnly) {
                        if (!isArchived) return false;
                      } else {
                        if (isArchived) return false;
                      }

                      // Check deleted state
                      final deletedAtStr = _prefs!.getString('deleted_at_$otherId');
                      if (deletedAtStr != null) {
                        final deletedAt = DateTime.parse(deletedAtStr);
                        final msgAt = DateTime.parse(msg['created_at']);
                        if (!msgAt.isAfter(deletedAt)) return false;
                      }
                      
                      return true;
                    }).toList();

                    // Sort pinned conversations to top
                    conversations.sort((a, b) {
                      final myId = _chatService.currentUserId;
                      final otherIdA = a['sender_id'] == myId ? a['receiver_id'] : a['sender_id'];
                      final otherIdB = b['sender_id'] == myId ? b['receiver_id'] : b['sender_id'];

                      final isPinnedA = pinnedList.contains(otherIdA);
                      final isPinnedB = pinnedList.contains(otherIdB);

                      if (isPinnedA && !isPinnedB) return -1;
                      if (!isPinnedA && isPinnedB) return 1;

                      final timeA = DateTime.parse(a['created_at']);
                      final timeB = DateTime.parse(b['created_at']);
                      return timeB.compareTo(timeA);
                    });
                  }

                  if (conversations.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Column(
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text('No messages yet', style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final lastMsg = conversations[index];
                        final myId = _chatService.currentUserId;
                        final otherId = lastMsg['sender_id'] == myId ? lastMsg['receiver_id'] : lastMsg['sender_id'];
                        final lastMsgTime = DateTime.parse(lastMsg['created_at']);
                        final isFromOther = lastMsg['sender_id'] != myId;
                        
                        // Priority 1: BreederProvider data
                        final breederMatch = breederProvider.breeders.where((b) => b.userId == otherId).firstOrNull;
                        if (breederMatch != null) {
                          return _buildChatTileWithData(
                            otherId, 
                            {'full_name': breederMatch.name, 'avatar_url': breederMatch.imageUrl}, 
                            lastMsg, lastMsgTime, isDark, isFromOther
                          );
                        }

                        // Priority 2: Cache or Future
                        final cachedUser = ChatService.getUserCache()[otherId];
                        if (cachedUser != null) {
                          return _buildChatTileWithData(otherId, cachedUser, lastMsg, lastMsgTime, isDark, isFromOther);
                        }

                        return FutureBuilder<Map<String, dynamic>?>(
                          future: _chatService.getUserDetails(otherId),
                          builder: (context, userSnapshot) {
                            final userData = userSnapshot.data;
                            final bool isLoading = userSnapshot.connectionState == ConnectionState.waiting;
                            
                            if (userData != null) {
                              return _buildChatTileWithData(otherId, userData, lastMsg, lastMsgTime, isDark, isFromOther);
                            }

                            final String senderName = isFromOther ? (userData?['full_name']?.split(' ')[0] ?? 'User') : 'You';
                            final String lastMessageText = _getDisplayLastMessage(lastMsg, senderName);

                            return _buildChatTile(
                              otherId,
                              isLoading ? '...' : (userData?['full_name'] ?? 'User'),
                              userData?['avatar_url'],
                              lastMessageText,
                              lastMsgTime,
                              isDark,
                              false,
                            );
                          },
                        );
                      },
                      childCount: conversations.length,
                    ),
                  );
                },
              ),
            ] else ...[
              // Search Results Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Search Results',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              _buildSearchResults(breederProvider, isDark),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
  Widget _buildSearchResults(BreederProvider breederProvider, bool isDark) {
    // 1. Get all unique users from BreederProvider and Chat Cache
    final Map<String, Map<String, dynamic>> allUsers = {};
    
    // Add all breeders/traders
    for (var b in breederProvider.breeders) {
      if (b.userId == _chatService.currentUserId) continue;
      allUsers[b.userId] = {
        'id': b.userId,
        'full_name': b.name,
        'avatar_url': b.imageUrl,
        'role': b.role,
      };
    }
    
    // Add from Chat Service cache (might have users not in breeders list)
    ChatService.getUserCache().forEach((id, data) {
      if (id == _chatService.currentUserId) return;
      if (!allUsers.containsKey(id)) {
        allUsers[id] = {
          'id': id,
          'full_name': data['full_name'],
          'avatar_url': data['avatar_url'],
          'role': 'User',
        };
      }
    });

    // 2. Filter by search query
    final filteredUsers = allUsers.values.where((user) {
      final name = (user['full_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery);
    }).toList();

    if (filteredUsers.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('No users found matching "$_searchQuery"', style: TextStyle(color: Colors.grey[500])),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final user = filteredUsers[index];
          return _buildSearchTile(user, isDark);
        },
        childCount: filteredUsers.length,
      ),
    );
  }

  Widget _buildSearchTile(Map<String, dynamic> user, bool isDark) {
    final String id = user['id'];
    final String name = user['full_name'] ?? 'User';
    final String? avatarUrl = user['avatar_url'];
    final String role = user['role'] ?? 'User';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              breederId: id,
              breederName: name,
              breederAvatarUrl: avatarUrl,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: isDark ? Colors.grey[900] : const Color(0xFFE9F5F2),
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null || avatarUrl.isEmpty 
                  ? Icon(Icons.person, color: isDark ? Colors.grey[700] : const Color(0xFF52B788).withValues(alpha: 0.5), size: 30)
                  : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600, 
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      role,
                      style: const TextStyle(
                        color: Color(0xFF2D6A4F),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chat_bubble_outline_rounded, size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildOnlineUsersHorizontalList(List<Breeder> onlineUsers, bool isDark) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: onlineUsers.length,
        itemBuilder: (context, index) {
          final user = onlineUsers[index];
          final name = user.name.split(' ')[0];

          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    breederId: user.userId,
                    breederName: user.name,
                    breederAvatarUrl: user.imageUrl,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: isDark ? Colors.grey[800] : const Color(0xFFE9F5F2),
                          backgroundImage: user.imageUrl.isNotEmpty ? NetworkImage(user.imageUrl) : null,
                          child: user.imageUrl.isEmpty 
                            ? Icon(Icons.person, size: 32, color: isDark ? Colors.grey[400] : const Color(0xFF52B788))
                            : null,
                        ),
                      ),
                      if (!_isOffline &&
                          (_presenceService.isUserOnline(user.id) ||
                              (!_presenceService.isReady &&
                                  user.lastSeen != null &&
                                  DateTime.now().toUtc().difference(user.lastSeen!.toUtc()).inSeconds < 35)))
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            height: 12,
                            width: 12,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: isDark ? Colors.black : Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name, 
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[300] : Colors.black87
                    )
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getDisplayLastMessage(Map<String, dynamic> lastMsg, String senderName) {
    if (lastMsg['is_deleted'] == true) {
      return 'Unsent a message';
    }
    
    String rawText = lastMsg['message_text']?.toString() ?? '';
    if (rawText.startsWith('{"reply":')) {
      try {
        final decoded = jsonDecode(rawText);
        if (decoded is Map && decoded.containsKey('text')) {
          rawText = decoded['text']?.toString() ?? '';
        }
      } catch (_) {}
    }

    if (rawText.trim().isEmpty) {
      if (lastMsg['image_url'] != null && lastMsg['image_url'].toString().isNotEmpty) {
        return '$senderName sent a photo';
      }
      return '';
    }
    return rawText;
  }

  Widget _buildChatTileWithData(String otherId, Map<String, dynamic> userData, Map<String, dynamic> lastMsg, DateTime lastMsgTime, bool isDark, bool isFromOther) {
    final name = userData['full_name'] ?? 'User';
    final avatarUrl = userData['avatar_url'];

    bool isUnread = false;
    if (isFromOther && _prefs != null) {
      final lastReadStr = _prefs!.getString('last_read_$otherId');
      if (lastReadStr == null) {
        isUnread = true;
      } else {
        final lastRead = DateTime.parse(lastReadStr);
        isUnread = lastMsgTime.isAfter(lastRead);
      }
    }

    final String senderName = isFromOther ? name.split(' ')[0] : 'You';
    final String lastMessageText = _getDisplayLastMessage(lastMsg, senderName);

    return _buildChatTile(
      otherId,
      name,
      avatarUrl,
      lastMessageText,
      lastMsgTime,
      isDark,
      isUnread,
    );
  }

  Widget _buildChatTile(String otherId, String name, String? avatarUrl, String lastMessage, DateTime time, bool isDark, bool isUnread) {
    final isPinned = _prefs?.getStringList('pinned_chats')?.contains(otherId) == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                breederId: otherId,
                breederName: name,
                breederAvatarUrl: avatarUrl,
              ),
            ),
          );
          await _initPrefs();
        },
        onLongPress: () => _showChatOptionsMenu(otherId, name, avatarUrl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: isDark ? Colors.grey[900] : const Color(0xFFE9F5F2),
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null || avatarUrl.isEmpty 
                  ? Icon(Icons.person, color: isDark ? Colors.grey[700] : const Color(0xFF52B788).withValues(alpha: 0.5), size: 35)
                  : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isUnread ? FontWeight.bold : FontWeight.w600, 
                                    fontSize: 16,
                                    color: isDark ? Colors.white : (isUnread ? Colors.black : Colors.black87)
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isPinned) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: Color(0xFF2D6A4F),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          DateFormat('hh:mm a').format(time.toUtc().add(const Duration(hours: 8))),
                          style: TextStyle(
                            color: isUnread ? const Color(0xFF2D6A4F) : (isDark ? Colors.grey[600] : Colors.grey[500]), 
                            fontSize: 12,
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isUnread 
                          ? (isDark ? Colors.white : Colors.black) 
                          : (isDark ? Colors.grey[500] : Colors.grey[600]),
                        fontSize: 14,
                        fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChatSettingsMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final archivedList = _prefs?.getStringList('archived_chats') ?? [];
    final blockedList = _prefs?.getStringList('blocked_chats') ?? [];
    final seenArchivedCount = _prefs?.getInt('seen_archived_count') ?? 0;
    final seenBlockedCount = _prefs?.getInt('seen_blocked_count') ?? 0;

    final unreadArchivedCount = archivedList.length - seenArchivedCount;
    final unreadBlockedCount = blockedList.length - seenBlockedCount;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF242424) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12, top: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        'Chat Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.archive_outlined, color: Color(0xFF2D6A4F), size: 22),
                  ),
                  title: Text(
                    'Archived Chats',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    archivedList.isEmpty
                        ? 'No archived chats'
                        : '${archivedList.length} archived conversation${archivedList.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                  trailing: unreadArchivedCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D6A4F),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$unreadArchivedCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    _showArchivedChatsBottomSheet();
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.block_outlined, color: Colors.red, size: 22),
                  ),
                  title: Text(
                    'Blocked Accounts',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    blockedList.isEmpty
                        ? 'No blocked accounts'
                        : '${blockedList.length} blocked account${blockedList.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                  trailing: unreadBlockedCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$unreadBlockedCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    _showBlockedUsersBottomSheet();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showArchivedChatsBottomSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final archivedIds = _prefs?.getStringList('archived_chats') ?? [];
    await _prefs?.setInt('seen_archived_count', archivedIds.length);
    if (mounted) setState(() {});

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Archived Chats',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: archivedIds.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.archive_outlined, size: 56, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No archived chats',
                                style: TextStyle(color: Colors.grey[500], fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: archivedIds.length,
                          itemBuilder: (context, index) {
                            final otherId = archivedIds[index];
                            final breederProvider = Provider.of<BreederProvider>(context, listen: false);
                            final breederMatch = breederProvider.breeders.where((b) => b.userId == otherId).firstOrNull;
                            final cachedUser = ChatService.getUserCache()[otherId];

                            final name = breederMatch?.name ?? cachedUser?['full_name'] ?? 'User';
                            final avatarUrl = breederMatch?.imageUrl ?? cachedUser?['avatar_url'];

                            return ListTile(
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: isDark ? Colors.grey[800] : const Color(0xFFE9F5F2),
                                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                                child: avatarUrl == null || avatarUrl.isEmpty
                                    ? Icon(Icons.person, color: isDark ? Colors.grey[400] : const Color(0xFF52B788))
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              subtitle: const Text('Archived chat', style: TextStyle(fontSize: 12)),
                              trailing: TextButton.icon(
                                icon: const Icon(Icons.unarchive_outlined, size: 18),
                                label: const Text('Unarchive'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF2D6A4F),
                                ),
                                onPressed: () async {
                                  final updated = List<String>.from(archivedIds)..remove(otherId);
                                  await _prefs?.setStringList('archived_chats', updated);
                                  _chatService.updateChatSetting(targetUserId: otherId, isArchived: false);
                                  if (mounted) {
                                    setState(() {});
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Chat unarchived'),
                                        backgroundColor: Color(0xFF2D6A4F),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      breederId: otherId,
                                      breederName: name,
                                      breederAvatarUrl: avatarUrl,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBlockedUsersBottomSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockedIds = _prefs?.getStringList('blocked_chats') ?? [];
    await _prefs?.setInt('seen_blocked_count', blockedIds.length);
    if (mounted) setState(() {});

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Blocked Accounts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: blockedIds.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.block_outlined, size: 56, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No blocked accounts',
                                style: TextStyle(color: Colors.grey[500], fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: blockedIds.length,
                          itemBuilder: (context, index) {
                            final otherId = blockedIds[index];
                            final breederProvider = Provider.of<BreederProvider>(context, listen: false);
                            final breederMatch = breederProvider.breeders.where((b) => b.userId == otherId).firstOrNull;
                            final cachedUser = ChatService.getUserCache()[otherId];

                            final name = breederMatch?.name ?? cachedUser?['full_name'] ?? 'User';
                            final avatarUrl = breederMatch?.imageUrl ?? cachedUser?['avatar_url'];

                            return ListTile(
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: isDark ? Colors.grey[800] : const Color(0xFFE9F5F2),
                                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                                child: avatarUrl == null || avatarUrl.isEmpty
                                    ? Icon(Icons.person, color: isDark ? Colors.grey[400] : const Color(0xFF52B788))
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              subtitle: const Text('Blocked account', style: TextStyle(fontSize: 12, color: Colors.red)),
                              trailing: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2D6A4F),
                                  side: const BorderSide(color: Color(0xFF2D6A4F)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () async {
                                  final updated = List<String>.from(blockedIds)..remove(otherId);
                                  await _prefs?.setStringList('blocked_chats', updated);
                                  _chatService.updateChatSetting(targetUserId: otherId, isBlocked: false);
                                  if (mounted) {
                                    setState(() {});
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('User unblocked'),
                                        backgroundColor: Color(0xFF2D6A4F),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Unblock'),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChatOptionsMenu(String otherId, String name, String? avatarUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pinnedList = _prefs?.getStringList('pinned_chats') ?? [];
    final archivedList = _prefs?.getStringList('archived_chats') ?? [];
    final blockedList = _prefs?.getStringList('blocked_chats') ?? [];

    final isPinned = pinnedList.contains(otherId);
    final isArchived = archivedList.contains(otherId);
    final isBlocked = blockedList.contains(otherId);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF242424) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12, top: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 22,
                  ),
                  title: Text(
                    isPinned ? 'Unpin' : 'Pin',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final updated = List<String>.from(pinnedList);
                    if (isPinned) {
                      updated.remove(otherId);
                    } else {
                      updated.add(otherId);
                    }
                    await _prefs?.setStringList('pinned_chats', updated);
                    _chatService.updateChatSetting(targetUserId: otherId, isPinned: !isPinned);
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  leading: Icon(
                    isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 22,
                  ),
                  title: Text(
                    isArchived ? 'Unarchive' : 'Archive',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final updated = List<String>.from(archivedList);
                    if (isArchived) {
                      updated.remove(otherId);
                    } else {
                      updated.add(otherId);
                    }
                    await _prefs?.setStringList('archived_chats', updated);
                    _chatService.updateChatSetting(targetUserId: otherId, isArchived: !isArchived);
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(isArchived ? 'Chat unarchived' : 'Chat archived'),
                          backgroundColor: const Color(0xFF2D6A4F),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    isBlocked ? Icons.block_flipped : Icons.block_outlined,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 22,
                  ),
                  title: Text(
                    isBlocked ? 'Unblock user' : 'Block user',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final updated = List<String>.from(blockedList);
                    if (isBlocked) {
                      updated.remove(otherId);
                    } else {
                      updated.add(otherId);
                    }
                    await _prefs?.setStringList('blocked_chats', updated);
                    _chatService.updateChatSetting(targetUserId: otherId, isBlocked: !isBlocked);
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(isBlocked ? 'User unblocked' : 'User blocked'),
                          backgroundColor: const Color(0xFF2D6A4F),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                    size: 22,
                  ),
                  title: const Text(
                    'Delete',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(otherId, name);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(String otherId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete conversation with $name?'),
        content: const Text('This will delete all messages in this conversation. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final prefs = await SharedPreferences.getInstance();
              navigator.pop();
              try {
                await prefs.setString('deleted_at_$otherId', DateTime.now().toIso8601String());
                await prefs.remove('last_read_$otherId');
                if (mounted) {
                  setState(() { _initPrefs(); });
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Conversation deleted for you'),
                      backgroundColor: Color(0xFF2D6A4F),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('Failed to delete: ${e.toString()}'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search conversations...',
            hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[500], fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2D6A4F)),
            suffixIcon: _searchQuery.isNotEmpty 
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 20),
                  onPressed: () => _searchController.clear(),
                )
              : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 20),
          SizedBox(width: 12),
          Text(
            'No Internet Connection',
            style: TextStyle(
              color: Color(0xFF991B1B),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
