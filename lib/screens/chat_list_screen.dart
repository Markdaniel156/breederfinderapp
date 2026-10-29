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
import '../utils/system_ui_utils.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  SharedPreferences? _prefs;
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<Map<String, dynamic>> _cachedConversations = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _checkConnectivity();
    _loadCachedConversations();
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
    _connectivitySubscription.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final breederProvider = Provider.of<BreederProvider>(context);

    // Filter online breeders/traders (active in last 5 mins)
    // If offline, just show recently active ones from cache regardless of 5 min limit
    final onlineBreeders = breederProvider.breeders.where((b) {
      if (b.userId == _chatService.currentUserId) return false;
      if (b.lastSeen == null) return _isOffline; // Show offline breeders if we are offline
      if (_isOffline) return true; // Show all cached breeders if offline to keep UI populated
      return DateTime.now().difference(b.lastSeen!).inMinutes < 5;
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
                  onPressed: () {},
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
                  child: Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
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
                  
                  // Locally filter out conversations that were recently "deleted"
                  if (_prefs != null) {
                    conversations = conversations.where((msg) {
                      final myId = _chatService.currentUserId;
                      final otherId = msg['sender_id'] == myId ? msg['receiver_id'] : msg['sender_id'];
                      final deletedAtStr = _prefs!.getString('deleted_at_$otherId');
                      if (deletedAtStr == null) return true;
                      
                      final deletedAt = DateTime.parse(deletedAtStr);
                      final msgAt = DateTime.parse(msg['created_at']);
                      return msgAt.isAfter(deletedAt);
                    }).toList();
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
                            
                            String lastMessageText;
                            if (lastMsg['is_deleted'] == true) {
                              lastMessageText = 'Unsent a message';
                            } else {
                              lastMessageText = (lastMsg['message_text'] == null || lastMsg['message_text'].toString().isEmpty)
                                  ? (lastMsg['image_url'] != null ? '$senderName sent a photo' : '')
                                  : lastMsg['message_text'];
                            }

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
                      if (!_isOffline && user.lastSeen != null && DateTime.now().difference(user.lastSeen!).inMinutes < 5)
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
    
    String lastMessageText;
    if (lastMsg['is_deleted'] == true) {
      lastMessageText = 'Unsent a message';
    } else {
      lastMessageText = (lastMsg['message_text'] == null || lastMsg['message_text'].toString().isEmpty)
          ? (lastMsg['image_url'] != null ? '$senderName sent a photo' : '')
          : lastMsg['message_text'];
    }

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
        onLongPress: () => _showDeleteConfirmation(otherId, name),
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
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600, 
                            fontSize: 16,
                            color: isDark ? Colors.white : (isUnread ? Colors.black : Colors.black87)
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
