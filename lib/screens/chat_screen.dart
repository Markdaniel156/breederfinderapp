import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../providers/breeder_provider.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/presence_service.dart';
import 'profile_screen.dart';
import '../utils/system_ui_utils.dart';

const Color _kGreen = Color(0xFF2D6A4F);
const Color _kGreenLight = Color(0xFF52B788);

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
  final PresenceService _presenceService = PresenceService();
  final ScrollController _scrollController = ScrollController();
  late Stream<List<ChatMessage>> _messagesStream;
  late final ChatProvider _chatProvider;
  SharedPreferences? _prefs;
  Map<String, dynamic>? _otherUserData;
  bool _isOffline = false;
  bool _isUserBlocked = false;
  bool _isBlockedByOther = false;
  bool _isLoadingBlockStatus = true;
  ChatMessage? _replyingTo;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Set active chat for notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatProvider.setActiveChat(widget.breederId);
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
    _presenceService.addListener(_onPresenceChanged);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        final wasOffline = _isOffline;
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
        });
        if (wasOffline && !_isOffline) {
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
  }

  void _onPresenceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startStatusUpdates() {
    // Initial load
    _loadOtherUserDetails();
    _checkBlockStatus();

    // Refresh other user's status and block status every 10 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadOtherUserDetails();
      _checkBlockStatus();
    });
  }

  bool _isBetterName(String? newName, String? oldName) {
    if (newName == null || newName == '...' || newName == 'Loading...') return false;
    if (oldName == null || oldName == 'User' || oldName == '...' || oldName == 'Loading...') return true;
    return false; // Both are real names, keep the one we have
  }

  Future<void> _loadOtherUserDetails() async {
    if (_otherUserData == null) {
      final data = await _chatService.getUserDetails(widget.breederId, forceRefresh: true);
      if (mounted && data != null) {
        setState(() {
          _otherUserData = data;
        });
      }
    } else {
      final lastSeen = await _chatService.getLastSeen(widget.breederId);
      if (mounted && lastSeen != null) {
        final iso = lastSeen.toUtc().toIso8601String();
        if (_otherUserData?['last_seen'] != iso) {
          setState(() {
            _otherUserData = {
              ...?_otherUserData,
              'last_seen': iso,
            };
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

  Future<void> _checkBlockStatus() async {
    final blockedByMe = await _chatService.isUserBlocked(widget.breederId);
    final eitherWay = await _chatService.isBlockedEitherWay(widget.breederId);
    if (mounted) {
      setState(() {
        _isUserBlocked = blockedByMe;
        _isBlockedByOther = eitherWay && !blockedByMe;
        _isLoadingBlockStatus = false;
      });
    }
  }

  /// Returns true (and tells the user) if this chat is blocked in either direction.
  Future<bool> _isChatBlocked() async {
    final blocked = await _chatService.isBlockedEitherWay(widget.breederId);
    if (blocked) {
      await _checkBlockStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can't send messages in this chat.")),
        );
      }
    }
    return blocked;
  }

  void _onReplyToMessage(ChatMessage msg) {
    if (msg.isDeleted) return;
    setState(() {
      _replyingTo = msg;
    });
  }

  String _getReplyHeaderText(ChatMessage msg, String otherUserName) {
    final rawSender = msg.replyToSender;
    final cleanOtherName = (otherUserName == 'Loading...' || otherUserName == '...') ? 'User' : otherUserName;

    if (msg.isMe) {
      String target;
      if (rawSender == 'You' || rawSender == null) {
        target = 'yourself';
      } else {
        target = rawSender;
      }
      return 'You replied to $target';
    } else {
      String target;
      if (rawSender == 'You' || rawSender == null) {
        target = 'you';
      } else if (rawSender == cleanOtherName) {
        target = 'themselves';
      } else {
        target = rawSender;
      }
      return '$cleanOtherName replied to $target';
    }
  }

  void _sendMessage() async {
    if (_isOffline || _isUserBlocked || _isBlockedByOther) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (await _isChatBlocked()) return;

    final reply = _replyingTo;
    if (_replyingTo != null) {
      setState(() {
        _replyingTo = null;
      });
    }

    _controller.clear();
    try {
      final senderName = reply == null
          ? null
          : (reply.isMe ? 'You' : (_otherUserData?['full_name'] ?? widget.breederName));

      await _chatService.sendMessage(
        widget.breederId,
        text,
        replyToId: reply?.id,
        replyToSender: senderName,
        replyToText: reply?.text,
        replyToImageUrl: reply?.imageUrl,
      );
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
    _chatProvider.setActiveChat(null);
    _presenceService.removeListener(_onPresenceChanged);
    _statusTimer?.cancel();
    _connectivitySubscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendImage(ImageSource source) async {
    if (_isOffline || _isUserBlocked || _isBlockedByOther) return;
    if (await _isChatBlocked()) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 70, // Compress image
      );

      if (pickedFile != null) {
        final File imageFile = File(pickedFile.path);

        final reply = _replyingTo;
        if (_replyingTo != null) {
          setState(() {
            _replyingTo = null;
          });
        }

        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sending image...'), duration: Duration(seconds: 1)),
          );
        }

        final senderName = reply == null
            ? null
            : (reply.isMe ? 'You' : (_otherUserData?['full_name'] ?? widget.breederName));

        await _chatService.sendImageMessage(
          widget.breederId,
          imageFile,
          replyToId: reply?.id,
          replyToSender: senderName,
          replyToText: reply?.text,
          replyToImageUrl: reply?.imageUrl,
        );
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

  Future<void> _sendVideo(ImageSource source) async {
    if (_isOffline || _isUserBlocked || _isBlockedByOther) return;
    if (await _isChatBlocked()) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile != null) {
        final File videoFile = File(pickedFile.path);

        // Check file size (max 50MB)
        final int fileSize = await videoFile.length();
        if (fileSize > 50 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video is too large. Maximum size is 50MB.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        final reply = _replyingTo;
        if (_replyingTo != null) {
          setState(() {
            _replyingTo = null;
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sending video...'), duration: Duration(seconds: 2)),
          );
        }

        final senderName = reply == null
            ? null
            : (reply.isMe ? 'You' : (_otherUserData?['full_name'] ?? widget.breederName));

        await _chatService.sendVideoMessage(
          widget.breederId,
          videoFile,
          replyToId: reply?.id,
          replyToSender: senderName,
          replyToText: reply?.text,
          replyToImageUrl: reply?.imageUrl,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending video: $e')),
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime _toLocal(DateTime d) => d.toUtc().add(const Duration(hours: 8));

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateLabel(DateTime d) {
    final now = _toLocal(DateTime.now());
    final local = _toLocal(d);
    if (_sameDay(now, local)) return 'Today';
    if (_sameDay(now.subtract(const Duration(days: 1)), local)) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(local);
  }

  bool get _isOtherOnline {
    if (_isOffline || _otherUserData == null) return false;
    // 1. Primary: Realtime Presence (live websocket presence from Supabase)
    if (_presenceService.isUserOnline(widget.breederId)) {
      return true;
    }
    // 2. Fallback: only if presence is still initializing on app start,
    // check if heartbeat is extremely recent (< 35 seconds).
    if (!_presenceService.isReady) {
      final s = _otherUserData!['last_seen'];
      if (s == null) return false;
      final parsed = DateTime.tryParse(s.toString());
      if (parsed == null) return false;
      final diff = DateTime.now().toUtc().difference(parsed.toUtc());
      return diff.inSeconds < 35;
    }
    return false;
  }

  String get _statusText {
    if (_isOffline) return 'Waiting for network...';
    if (_isOtherOnline) return 'Active now';

    final s = _otherUserData?['last_seen'];
    if (s == null) return 'Inactive';
    final parsed = DateTime.tryParse(s.toString());
    if (parsed == null) return 'Inactive';

    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    if (diff.isNegative || diff.inSeconds < 60) {
      return 'Inactive just now';
    } else if (diff.inMinutes < 60) {
      return 'Inactive ${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return 'Inactive ${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return 'Inactive ${diff.inDays}d ago';
    } else {
      return 'Inactive';
    }
  }

  Widget _buildAvatar(String name, String? url, double radius) {
    final hasUrl = url != null && url.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE9F5F2),
      backgroundImage: hasUrl ? NetworkImage(url) : null,
      child: hasUrl
          ? null
          : Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: _kGreen,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
        appBar: _buildAppBar(theme, isDark, displayName, displayAvatar),
        body: Column(
          children: [
            if (_isOffline) _buildOfflineBanner(),
            Expanded(child: _buildMessageList(displayName, displayAvatar, isDark)),
            if (_replyingTo != null) _buildReplyPreviewBanner(theme, isDark),
            _buildMessageInput(context),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      ThemeData theme,
      bool isDark,
      String displayName,
      String? displayAvatar,
      ) {
    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      titleSpacing: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kGreen, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileScreen(userId: widget.breederId)),
          );
        },
        child: Row(
          children: [
            Stack(
              children: [
                _buildAvatar(displayName, displayAvatar, 20),
                if (_isOtherOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: _isOtherOnline
                          ? Colors.green[600]
                          : (isDark ? Colors.grey[500] : Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 1,
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
    );
  }

  Widget _buildMessageList(String displayName, String? displayAvatar, bool isDark) {
    return StreamBuilder<List<ChatMessage>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kGreen));
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return _buildCenteredMessage(
            icon: Icons.wifi_off_rounded,
            title: _isOffline ? 'Offline mode' : 'Connection lost',
            subtitle: _isOffline
                ? 'You can still view previous messages'
                : 'Waiting for network to reconnect...',
          );
        }

        final messages = snapshot.data ?? [];

        // Locally filter out messages that were part of a deleted conversation
        List<ChatMessage> displayMessages = messages;
        if (_prefs != null) {
          final deletedAtStr = _prefs!.getString('deleted_at_${widget.breederId}');
          final deletedAt = deletedAtStr != null ? DateTime.parse(deletedAtStr) : null;

          displayMessages = messages.where((msg) {
            if (deletedAt != null && msg.createdAt.isBefore(deletedAt)) return false;
            return true; // Deleted messages show a placeholder instead
          }).toList();
        }

        if (displayMessages.isEmpty) {
          return _buildCenteredMessage(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'No messages yet',
            subtitle: 'Say hi to ${widget.breederName}',
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          cacheExtent: 1000,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          itemCount: displayMessages.length,
          itemBuilder: (context, index) => _buildMessageItem(
            messages: displayMessages,
            index: index,
            displayName: displayName,
            displayAvatar: displayAvatar,
            isDark: isDark,
          ),
        );
      },
    );
  }

  Widget _buildCenteredMessage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: _kGreen.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(color: Colors.grey[600], fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem({
    required List<ChatMessage> messages,
    required int index,
    required String displayName,
    required String? displayAvatar,
    required bool isDark,
  }) {
    final msg = messages[index];
    final older = index + 1 < messages.length ? messages[index + 1] : null; // earlier message
    final newer = index > 0 ? messages[index - 1] : null; // later message
    final isMe = msg.isMe;
    final localTime = _toLocal(msg.createdAt);

    final showDate = older == null || !_sameDay(_toLocal(older.createdAt), localTime);
    final groupedWithOlder = !showDate &&
        older != null &&
        older.isMe == isMe &&
        msg.createdAt.difference(older.createdAt).inMinutes.abs() < 5;
    final groupedWithNewer = newer != null &&
        newer.isMe == isMe &&
        _sameDay(_toLocal(newer.createdAt), localTime) &&
        newer.createdAt.difference(msg.createdAt).inMinutes.abs() < 5;

    final bool isLocallyDeleted = _prefs?.getBool('msg_deleted_${msg.id}') == true;
    final bool isRemoved = msg.isDeleted || isLocallyDeleted;

    final bool hasReply = !isRemoved &&
        (msg.replyToSender != null || msg.replyToText != null || msg.replyToImageUrl != null);
    final String replyHeaderText = hasReply ? _getReplyHeaderText(msg, displayName) : '';

    const double r = 18;
    const double t = 5;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe || !groupedWithOlder ? r : t),
      bottomLeft: Radius.circular(isMe || !groupedWithNewer ? r : t),
      topRight: Radius.circular(!isMe || !groupedWithOlder ? r : t),
      bottomRight: Radius.circular(!isMe || !groupedWithNewer ? r : t),
    );

    return Column(
      children: [
        if (showDate)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                _dateLabel(msg.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ),
          ),
        SwipeToReplyWrapper(
          onReply: () => _onReplyToMessage(msg),
          child: GestureDetector(
            onLongPress: isRemoved ? null : () => _showDeleteMessageDialog(msg),
            child: Padding(
              padding: EdgeInsets.only(bottom: groupedWithNewer ? 2 : 10),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isMe) ...[
                        SizedBox(
                          width: 28,
                          child: groupedWithNewer ? null : _buildAvatar(displayName, displayAvatar, 14),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasReply) _buildReplyQuote(msg, replyHeaderText, isDark),
                            _buildBubble(msg, isMe, isRemoved, isDark, radius),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!groupedWithNewer)
                    Padding(
                      padding: EdgeInsets.only(left: isMe ? 0 : 36, right: isMe ? 4 : 0, top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('hh:mm a').format(localTime),
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
                                fontWeight: FontWeight.w700,
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
          ),
        ),
      ],
    );
  }

  Widget _buildReplyQuote(ChatMessage msg, String header, bool isDark) {
    final isPhotoOnly =
        msg.replyToImageUrl != null && (msg.replyToText == null || msg.replyToText!.isEmpty);
    final textColor = isDark ? Colors.grey[300] : Colors.black87;

    return Column(
      crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.reply_rounded, size: 13, color: isDark ? Colors.grey[500] : Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                header,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: _kGreenLight),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: isPhotoOnly
                            ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              msg.replyToIsVideo ? Icons.videocam_rounded : Icons.camera_alt_rounded,
                              size: 14,
                              color: textColor,
                            ),
                            const SizedBox(width: 6),
                            Text(msg.replyToIsVideo ? 'Video' : 'Photo', style: TextStyle(fontSize: 13, color: textColor)),
                          ],
                        )
                            : Text(
                          msg.replyToText ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, height: 1.3, color: textColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(
      ChatMessage msg,
      bool isMe,
      bool isRemoved,
      bool isDark,
      BorderRadius radius,
      ) {
    final width = MediaQuery.of(context).size.width;

    if (isRemoved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
        ),
        child: Text(
          (msg.imageUrl != null || msg.text.isEmpty)
              ? (msg.isVideo ? 'Video unsent' : 'Photo unsent')
              : 'Message unsent',
          style: TextStyle(
            color: isDark ? Colors.grey[600] : Colors.grey[500],
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    if (msg.imageUrl != null) {
      if (msg.isVideo) {
        return ChatVideoBubble(
          videoUrl: msg.imageUrl!,
          createdAt: msg.createdAt,
          radius: radius,
          isMe: isMe,
          isDark: isDark,
        );
      }
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenImageViewer(
                imageUrl: msg.imageUrl!,
                createdAt: msg.createdAt,
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width * 0.6,
              maxHeight: 260,
              minWidth: 140,
              minHeight: 140,
            ),
            child: Image.network(
              msg.imageUrl!,
              fit: BoxFit.cover,
              width: width * 0.6,
              height: 220,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: 200,
                  height: 200,
                  color: isDark ? Colors.grey[850] : Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Container(
                width: 200,
                height: 160,
                color: isDark ? Colors.grey[850] : Colors.grey[200],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_rounded, color: Colors.grey[400], size: 32),
                    const SizedBox(height: 6),
                    Text('Failed to load image', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(maxWidth: width * 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: isMe ? _kGreen : (isDark ? const Color(0xFF262626) : const Color(0xFFF0F2F1)),
        borderRadius: radius,
      ),
      child: Text(
        msg.text,
        style: TextStyle(
          color: isMe ? Colors.white : (isDark ? Colors.grey[200] : Colors.black87),
          fontSize: 15,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: const Color(0xFFFEF2F2),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 14),
          SizedBox(width: 8),
          Text(
            'No internet connection',
            style: TextStyle(color: Color(0xFF991B1B), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
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
                      const SnackBar(
                        content: Text('Message removed for everyone'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to remove: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: const Text('Unsend for everyone',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Input area
  // ---------------------------------------------------------------------------

  Widget _buildBottomBar({required Widget child}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(top: false, child: child),
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoadingBlockStatus) {
      return const SizedBox.shrink();
    }

    if (_isBlockedByOther) {
      return _buildBottomBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Text(
            "You can't send messages in this chat.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.red[400] ?? Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (_isUserBlocked) {
      return _buildBottomBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'You blocked this user.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  try {
                    await _chatService.updateChatSetting(
                      targetUserId: widget.breederId,
                      isBlocked: false,
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not unblock: $e')),
                      );
                    }
                  }
                  _checkBlockStatus();
                },
                child: const Text(
                  'Unblock',
                  style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pillColor = isDark ? const Color(0xFF262626) : const Color(0xFFF0F2F1);

    return _buildBottomBar(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attach button
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: IconButton(
                onPressed: _isOffline ? null : _showAttachSheet,
                style: IconButton.styleFrom(
                  backgroundColor: _kGreen.withValues(alpha: 0.12),
                  fixedSize: const Size(42, 42),
                ),
                icon: Icon(
                  Icons.add_rounded,
                  size: 24,
                  color: _isOffline ? Colors.grey : _kGreen,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Text field pill
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  enabled: !_isOffline,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.3,
                  ),
                  maxLines: 5,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _isOffline ? 'Offline' : 'Message...',
                    hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button (turns green once there is text)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty && !_isOffline;
                  return GestureDetector(
                    onTap: canSend ? _sendMessage : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: canSend
                            ? _kGreen
                            : (isDark ? Colors.grey[800] : Colors.grey[300]),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        size: 22,
                        color: canSend ? Colors.white : Colors.grey[500],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Share Media',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _sendImage(ImageSource.camera);
                    },
                  ),
                  _buildAttachOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Photos',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _sendImage(ImageSource.gallery);
                    },
                  ),
                  _buildAttachOption(
                    icon: Icons.videocam_rounded,
                    label: 'Record Video',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _sendVideo(ImageSource.camera);
                    },
                  ),
                  _buildAttachOption(
                    icon: Icons.video_collection_rounded,
                    label: 'Videos',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _sendVideo(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _kGreen, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreviewBanner(ThemeData theme, bool isDark) {
    if (_replyingTo == null) return const SizedBox.shrink();

    final senderName = _replyingTo!.isMe
        ? 'You'
        : (_otherUserData?['full_name'] ?? widget.breederName);
    final previewText = (_replyingTo!.imageUrl != null && _replyingTo!.text.isEmpty)
        ? (_replyingTo!.isVideo ? '🎥 Video' : '📷 Photo')
        : _replyingTo!.text;

    return Container(
      color: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF6FAF8),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: _kGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Replying to $senderName',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _kGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[300] : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20, color: Colors.grey),
              onPressed: () => setState(() => _replyingTo = null),
            ),
          ],
        ),
      ),
    );
  }
}

class SwipeToReplyWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const SwipeToReplyWrapper({
    super.key,
    required this.child,
    required this.onReply,
  });

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper> {
  double _dragOffset = 0.0;
  static const double _threshold = 55.0;
  bool _hasTriggeredHaptic = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset = (_dragOffset + details.delta.dx).clamp(-80.0, 80.0);
          if (_dragOffset.abs() >= _threshold && !_hasTriggeredHaptic) {
            HapticFeedback.lightImpact();
            _hasTriggeredHaptic = true;
          }
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset.abs() >= _threshold) {
          widget.onReply();
        }
        setState(() {
          _dragOffset = 0.0;
          _hasTriggeredHaptic = false;
        });
      },
      onHorizontalDragCancel: () {
        setState(() {
          _dragOffset = 0.0;
          _hasTriggeredHaptic = false;
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_dragOffset > 0)
            Positioned(
              left: 8,
              child: Opacity(
                opacity: (_dragOffset / _threshold).clamp(0.0, 1.0),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2D6A4F),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.reply_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          if (_dragOffset < 0)
            Positioned(
              right: 8,
              child: Opacity(
                opacity: ((-_dragOffset) / _threshold).clamp(0.0, 1.0),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2D6A4F),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.reply_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final DateTime? createdAt;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.createdAt,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _isSaving = false;

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else if (_doubleTapDetails != null) {
      final position = _doubleTapDetails!.localPosition;
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0.0, 1.0)
        ..scaleByDouble(2.5, 2.5, 2.5, 1.0);
    }
  }

  Future<void> _saveImage() async {
    if (_isSaving) return;

    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    final key = 'saved_img_${widget.imageUrl}';

    if (prefs.getBool(key) == true) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Already Saved',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'This image is already saved at your phone gallery.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1F2937),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Saving to Gallery...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image (HTTP ${response.statusCode})');
      }

      final bytes = response.bodyBytes;
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/temp_bf_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);

      if (kIsWeb) {
        await launchUrl(Uri.parse(widget.imageUrl), mode: LaunchMode.externalApplication);
        if (mounted) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            const SnackBar(content: Text('Image opened in browser for download')),
          );
        }
        return;
      }

      bool savedToGallery = false;
      try {
        const platform = MethodChannel('com.example.breederfinderapp/gallery');
        final bool? result = await platform.invokeMethod('saveToGallery', {'filePath': tempFile.path});
        savedToGallery = result == true;
      } catch (e) {
        debugPrint('MethodChannel saveToGallery error: $e');
      }

      if (!savedToGallery && Platform.isAndroid) {
        final dcimDir = Directory('/storage/emulated/0/DCIM/BreederFinder');
        if (!await dcimDir.exists()) {
          await dcimDir.create(recursive: true);
        }
        final filename = 'BreederFinder_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedFile = File('${dcimDir.path}/$filename');
        await savedFile.writeAsBytes(bytes);
        savedToGallery = true;
      }

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (mounted) {
        messenger.hideCurrentSnackBar();
        if (savedToGallery) {
          await prefs.setBool(key, true);

          messenger.showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.photo_library_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text('Image saved to Phone Gallery!')),
                ],
              ),
              backgroundColor: const Color(0xFF2D6A4F),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        } else {
          await launchUrl(Uri.parse(widget.imageUrl), mode: LaunchMode.externalApplication);
          messenger.showSnackBar(
            const SnackBar(content: Text('Opened image in browser for saving')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      if (mounted) {
        messenger.hideCurrentSnackBar();
        try {
          await launchUrl(Uri.parse(widget.imageUrl), mode: LaunchMode.externalApplication);
        } catch (_) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Failed to save image: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? formattedDate = widget.createdAt != null
        ? DateFormat('MMM d, yyyy · hh:mm a').format(widget.createdAt!.toUtc().add(const Duration(hours: 8)))
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Zoomable Image
            Center(
              child: GestureDetector(
                onDoubleTapDown: _handleDoubleTapDown,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.5,
                  maxScale: 4.0,
                  clipBehavior: Clip.none,
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF52B788)),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                        SizedBox(height: 12),
                        Text('Failed to load image', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Top Control Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                    if (formattedDate != null)
                      Text(
                        formattedDate,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    IconButton(
                      icon: _isSaving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Icon(Icons.download_rounded, color: Colors.white, size: 26),
                      onPressed: _saveImage,
                      tooltip: 'Save image',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatVideoBubble extends StatefulWidget {
  final String videoUrl;
  final DateTime createdAt;
  final BorderRadius radius;
  final bool isMe;
  final bool isDark;

  const ChatVideoBubble({
    super.key,
    required this.videoUrl,
    required this.createdAt,
    required this.radius,
    required this.isMe,
    required this.isDark,
  });

  @override
  State<ChatVideoBubble> createState() => _ChatVideoBubbleState();
}

class _ChatVideoBubbleState extends State<ChatVideoBubble> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = controller;
      await controller.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing chat video preview: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bubbleWidth = width * 0.65;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenVideoViewer(
              videoUrl: widget.videoUrl,
              createdAt: widget.createdAt,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: widget.radius,
        child: Container(
          width: bubbleWidth,
          height: 200,
          color: widget.isDark ? Colors.grey[900] : const Color(0xFF1E293B),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (_isInitialized && _controller != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else if (_hasError)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_rounded, color: Colors.grey[400], size: 36),
                      const SizedBox(height: 6),
                      const Text(
                        'Video unavailable',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.isDark ? Colors.white70 : _kGreen,
                    ),
                  ),
                ),
              // Subtle dark gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              // Center Play button
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              // Bottom Duration Badge
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, color: Colors.white, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        _isInitialized && _controller != null
                            ? _formatDuration(_controller!.value.duration)
                            : 'Video',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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
    );
  }
}

class FullScreenVideoViewer extends StatefulWidget {
  final String videoUrl;
  final DateTime? createdAt;

  const FullScreenVideoViewer({
    super.key,
    required this.videoUrl,
    this.createdAt,
  });

  @override
  State<FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  bool _isMuted = false;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.play();
          _startHideTimer();
        }
      }).catchError((error) {
        debugPrint('Error playing video: $error');
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      });

    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls && _controller.value.isPlaying) {
      _startHideTimer();
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _hideControlsTimer?.cancel();
        _showControls = true;
      } else {
        _controller.play();
        _startHideTimer();
      }
    });
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _controller.value.duration;
    final position = _controller.value.position;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video content
            Center(
              child: _isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio > 0
                          ? _controller.value.aspectRatio
                          : 16 / 9,
                      child: VideoPlayer(_controller),
                    )
                  : (_hasError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'Unable to play video',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(widget.videoUrl),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Open in Browser'),
                            ),
                          ],
                        )
                      : const CircularProgressIndicator(color: Colors.white)),
            ),

            // Animated Controls Overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.createdAt != null
                                      ? DateFormat('MMM d, yyyy • h:mm a').format(widget.createdAt!.toLocal())
                                      : 'Video',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: _toggleMute,
                              ),
                              IconButton(
                                icon: const Icon(Icons.download_rounded, color: Colors.white),
                                onPressed: () async {
                                  try {
                                    await launchUrl(
                                      Uri.parse(widget.videoUrl),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Could not open video: $e')),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        // Center Play / Pause
                        if (_isInitialized)
                          GestureDetector(
                            onTap: _togglePlayPause,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white54, width: 2),
                              ),
                              child: Icon(
                                _controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 44,
                              ),
                            ),
                          ),

                        // Bottom Scrub Bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isInitialized)
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFF52B788),
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: const Color(0xFF52B788),
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    trackHeight: 3,
                                  ),
                                  child: Slider(
                                    min: 0.0,
                                    max: duration.inMilliseconds.toDouble() > 0
                                        ? duration.inMilliseconds.toDouble()
                                        : 1.0,
                                    value: position.inMilliseconds
                                        .toDouble()
                                        .clamp(0.0, duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0),
                                    onChanged: (val) {
                                      _controller.seekTo(Duration(milliseconds: val.toInt()));
                                    },
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}