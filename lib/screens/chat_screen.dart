import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/breeder_provider.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import 'profile_screen.dart';
import '../utils/system_ui_utils.dart';

class ChatScreen extends StatefulWidget {
  final String breederId;
  final String breederName;
  final String? breederAvatarUrl;

  const ChatScreen({
    super.key,
    required this.breederId,
    required this.breederName,
    this.breederAvatarUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ChatService _chatService = ChatService();
  final ScrollController _scrollController = ScrollController();
  late Stream<List<ChatMessage>> _messagesStream;
  SharedPreferences? _prefs;
  Map<String, dynamic>? _otherUserData;
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  Timer? _statusTimer;
  Timer? _activityTimer;

  @override
  void initState() {
    super.initState();
    // Set active chat for notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).setActiveChat(widget.breederId);
    });
    
    _messagesStream = _chatService.getMessagesStream(widget.breederId).map((messages) {
      if (messages.isNotEmpty && !messages.first.isMe && messages.first.readAt == null) {
        _chatService.markMessagesAsRead(widget.breederId);
      }
      return messages;
    });
    _initPrefs();
    _markAsRead();
    _checkConnectivity();
    _startStatusUpdates();
    _updateMyActivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        final wasOffline = _isOffline;
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
        });
        if (wasOffline && !_isOffline) {
          _updateMyActivity();
          _loadOtherUserDetails();
        }
      }
    });
    
    // 1. Check Provider first for instant real-name display
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final breederProvider = Provider.of<BreederProvider>(context, listen: false);
        final match = breederProvider.breeders.where((b) => b.userId == widget.breederId).firstOrNull;
        if (match != null) {
          setState(() {
            _otherUserData = {
              'full_name': match.name,
              'avatar_url': match.imageUrl,
              'last_seen': match.lastSeen?.toIso8601String(),
            };
          });
        }
      }
    });

    // 2. Check Service Cache
    final cachedData = ChatService.getUserCache()[widget.breederId];
    if (cachedData != null && _isBetterName(cachedData['full_name'], _otherUserData?['full_name'])) {
      _otherUserData = cachedData;
    }

    _loadOtherUserDetails();
  }

  void _startStatusUpdates() {
    // Initial load
    _loadOtherUserDetails();
    
    // Refresh other user's status every 20 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _loadOtherUserDetails();
    });

    // Update my own "last seen" every 1 minute while in chat
    _activityTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateMyActivity();
    });
  }

  Future<void> _updateMyActivity() async {
    await _chatService.updateLastSeen();
  }

  bool _isBetterName(String? newName, String? oldName) {
    if (newName == null || newName == '...' || newName == 'Loading...') return false;
    if (oldName == null || oldName == 'User' || oldName == '...' || oldName == 'Loading...') return true;
    return false; // Both are real names, keep the one we have
  }

  Future<void> _loadOtherUserDetails() async {
    final data = await _chatService.getUserDetails(widget.breederId);
    if (mounted && data != null) {
      final String? newName = data['full_name'];
      final String? newLastSeen = data['last_seen'];
      final String currentName = _otherUserData?['full_name'] ?? widget.breederName;
      final String? currentLastSeen = _otherUserData?['last_seen'];

      if (newName != currentName || newLastSeen != currentLastSeen || _otherUserData == null) {
        if (_isBetterName(newName, currentName) || _otherUserData == null) {
          setState(() {
            _otherUserData = data;
          });
        }
      }
    }
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {});
  }

  Future<void> _markAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_read_${widget.breederId}', DateTime.now().toIso8601String());
    await _chatService.markMessagesAsRead(widget.breederId);
  }

  void _sendMessage() async {
    if (_isOffline) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    try {
      await _chatService.sendMessage(widget.breederId, text);
      // Scroll after the frame renders the new message
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    }
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
    // Clear active chat for notifications
    Provider.of<ChatProvider>(context, listen: false).setActiveChat(null);
    _statusTimer?.cancel();
    _activityTimer?.cancel();
    _connectivitySubscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendImage(ImageSource source) async {
    if (_isOffline) return;
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 70, // Compress image
      );

      if (pickedFile != null) {
        final File imageFile = File(pickedFile.path);
        
        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sending image...'), duration: Duration(seconds: 1)),
          );
        }

        await _chatService.sendImageMessage(widget.breederId, imageFile);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending image: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String rawName = _otherUserData?['full_name'] ?? widget.breederName;
    final String displayName = (rawName == 'Loading...' || rawName == '...') ? 'User' : rawName;
    
    String? displayAvatar = _otherUserData?['avatar_url'] ?? widget.breederAvatarUrl;
    if (displayAvatar != null && displayAvatar.isNotEmpty && !displayAvatar.startsWith('http')) {
      displayAvatar = Supabase.instance.client.storage.from('avatars').getPublicUrl(displayAvatar);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiUtils.getOverlayStyle(
        isDark: isDark,
        navBarColor: theme.scaffoldBackgroundColor,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(65),
          child: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            leadingWidth: 40,
            titleSpacing: 8,
            centerTitle: true,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF2D6A4F), size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: widget.breederId),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF52B788), Color(0xFF2D6A4F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                      backgroundImage: displayAvatar != null && displayAvatar.isNotEmpty
                          ? NetworkImage(displayAvatar)
                          : null,
                      child: displayAvatar == null || displayAvatar.isEmpty
                          ? Text(
                        displayName.isNotEmpty ? displayName[0] : '?',
                        style: const TextStyle(
                          color: Color(0xFF2D6A4F),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: -0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        _buildStatusRow(isDark, theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: const [
              SizedBox(width: 48), // Balancing the leading icon for true center
            ],
          ),
        ),
        body: Column(
          children: [
            if (_isOffline) _buildOfflineBanner(),
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError && !snapshot.hasData) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            _isOffline ? 'Offline Mode' : 'Connection Lost',
                            style: TextStyle(color: Colors.grey[500], fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isOffline 
                              ? 'You can still view previous messages' 
                              : 'Waiting for network to reconnect...',
                            style: TextStyle(color: Colors.grey[400], fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  // Locally filter out messages that were part of a deleted conversation
                  List<ChatMessage> visibleMessages = messages;
                  if (_prefs != null) {
                    final deletedAtStr = _prefs!.getString('deleted_at_${widget.breederId}');
                    final deletedAt = deletedAtStr != null ? DateTime.parse(deletedAtStr) : null;

                    visibleMessages = messages.where((msg) {
                      if (deletedAt != null && msg.createdAt.isBefore(deletedAt)) return false;
                      return true; // We don't filter individual deleted messages anymore, we show placeholders
                    }).toList();
                  }

                  final displayMessages = visibleMessages;

                  if (displayMessages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.grey[500], fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a conversation with ${widget.breederName}',
                            style: TextStyle(color: Colors.grey[400], fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    cacheExtent: 1000,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: displayMessages.length,
                    itemBuilder: (context, index) {
                      final msg = displayMessages[index];
                      final isMe = msg.isMe;
                      final bool isLocallyDeleted = _prefs?.getBool('msg_deleted_${msg.id}') == true;
                      final bool isRemoved = msg.isDeleted || isLocallyDeleted;

                      return GestureDetector(
                        onLongPress: isRemoved ? null : () => _showDeleteMessageDialog(msg),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMe) ...[
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(0xFFE9F5F2),
                                      backgroundImage: displayAvatar != null && displayAvatar.isNotEmpty
                                          ? NetworkImage(displayAvatar)
                                          : null,
                                      child: displayAvatar == null || displayAvatar.isEmpty
                                          ? Text(
                                        displayName.isNotEmpty ? displayName[0] : '?',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2D6A4F),
                                        ),
                                      )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                                      ),
                                      padding: (msg.imageUrl != null && !isRemoved)
                                        ? const EdgeInsets.all(2)
                                        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isRemoved 
                                          ? Colors.transparent 
                                          : ((msg.imageUrl != null) 
                                              ? Colors.transparent 
                                              : (isMe ? const Color(0xFF2D6A4F) : (isDark ? Colors.grey[900] : Colors.grey[100]))),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(20),
                                          topRight: const Radius.circular(20),
                                          bottomLeft: Radius.circular(isMe ? 20 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 20),
                                        ),
                                        border: isRemoved ? Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!) : null,
                                      ),
                                      child: isRemoved
                                        ? Text(
                                            (msg.imageUrl != null || msg.text.isEmpty) ? 'Photo unsent' : 'Message unsent',
                                            style: TextStyle(
                                              color: isDark ? Colors.grey[600] : Colors.grey[500],
                                              fontSize: 14,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          )
                                        : (msg.imageUrl != null
                                          ? GestureDetector(
                                            onTap: () {
                                              // Full screen preview
                                              showDialog(
                                                context: context,
                                                builder: (context) => Dialog.fullscreen(
                                                  backgroundColor: Colors.black,
                                                  child: Stack(
                                                    children: [
                                                      Center(child: Image.network(msg.imageUrl!)),
                                                      Positioned(
                                                        top: 40,
                                                        left: 20,
                                                        child: IconButton(
                                                          icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                                          onPressed: () => Navigator.pop(context),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(16),
                                              child: Image.network(
                                                msg.imageUrl!,
                                                fit: BoxFit.cover,
                                                loadingBuilder: (context, child, loadingProgress) {
                                                  if (loadingProgress == null) return child;
                                                  return Container(
                                                    width: 200,
                                                    height: 200,
                                                    color: isDark ? Colors.grey[850] : Colors.grey[200],
                                                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                                  );
                                                },
                                              ),
                                            ),
                                          )
                                        : Text(
                                            msg.text,
                                            style: TextStyle(
                                              color: isMe ? Colors.white : (isDark ? Colors.grey[300] : Colors.black87),
                                              fontSize: 15,
                                              height: 1.3,
                                            ),
                                          )),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: EdgeInsets.only(
                                  left: isMe ? 0 : 40,
                                  right: isMe ? 4 : 0,
                                  top: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat('hh:mm a').format(msg.createdAt.toUtc().add(const Duration(hours: 8))),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark ? Colors.grey[600] : Colors.grey[500],
                                      ),
                                    ),
                                    if (isMe && index == 0) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        msg.readAt != null ? '· Seen' : '· Sent',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _buildMessageInput(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFFFEF2F2),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 16),
          SizedBox(width: 8),
          Text(
            'No Internet Connection',
            style: TextStyle(color: Color(0xFF991B1B), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(bool isDark, ThemeData theme) {
    String statusText = 'Inactive';
    bool isOnline = false;

    if (_isOffline) {
      statusText = 'Waiting for network...';
    } else if (_otherUserData != null) {
      final lastSeenStr = _otherUserData!['last_seen'];
      if (lastSeenStr != null) {
        final lastSeen = DateTime.parse(lastSeenStr).toUtc();
        final difference = DateTime.now().toUtc().difference(lastSeen);
        
        if (difference.inMinutes < 3) {
          statusText = 'Active now';
          isOnline = true;
        } else if (difference.inMinutes < 60) {
          statusText = 'Inactive ${difference.inMinutes}m ago';
        } else if (difference.inHours < 24) {
          statusText = 'Inactive ${difference.inHours}h ago';
        } else {
          statusText = 'Inactive ${difference.inDays}d ago';
        }
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: isOnline ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          statusText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _showDeleteMessageDialog(ChatMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove message?'),
        content: Text(message.isMe 
          ? 'Who do you want to remove this message for?' 
          : 'This will remove the message for you. Other people in the chat will still be able to see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_prefs != null) {
                await _prefs!.setBool('msg_deleted_${message.id}', true);
                if (mounted) setState(() {});
              }
            },
            child: const Text('Remove for me', style: TextStyle(color: Colors.red)),
          ),
          if (message.isMe)
            TextButton(
              onPressed: () async {
              Navigator.pop(context);
              try {
                await _chatService.deleteMessage(message.id);
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Message removed for everyone'), behavior: SnackBarBehavior.floating),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Failed to remove: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                  );
                }
              }
            },
              child: const Text('Unsend for everyone', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: isDark ? Colors.grey[850]! : Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.camera_alt_rounded, 
              color: _isOffline ? Colors.grey : const Color(0xFF2D6A4F), 
              size: 24
            ),
            onPressed: _isOffline ? null : () => _sendImage(ImageSource.camera),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.photo_rounded, 
              color: _isOffline ? Colors.grey : const Color(0xFF2D6A4F), 
              size: 24
            ),
            onPressed: _isOffline ? null : () => _sendImage(ImageSource.gallery),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                enabled: !_isOffline,
                style: const TextStyle(fontSize: 14),
                maxLines: 5,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: _isOffline ? 'Offline - can\'t send messages' : 'Type a message...',
                  hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[500]),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.send_rounded, 
              color: _isOffline ? Colors.grey : const Color(0xFF2D6A4F), 
              size: 28
            ),
            onPressed: _isOffline ? null : _sendMessage,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}