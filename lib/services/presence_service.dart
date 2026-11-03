import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_service.dart';

/// App-wide presence service that tracks whether the current user is active inside the app
/// or inactive when leaving the app. Uses Supabase Realtime Presence as the primary source,
/// combined with database heartbeat/last_seen updates.
class PresenceService with ChangeNotifier, WidgetsBindingObserver {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final ChatService _chatService = ChatService();

  RealtimeChannel? _presenceChannel;
  Timer? _heartbeatTimer;
  Timer? _inactiveDebounceTimer;
  StreamSubscription<AuthState>? _authSubscription;
  bool _isInitialized = false;
  bool _isInForeground = true;
  bool _isSubscribed = false;

  final Set<String> _onlineUserIds = <String>{};

  Set<String> get onlineUserIds => Set.unmodifiable(_onlineUserIds);

  bool get isReady => _isSubscribed;

  bool isUserOnline(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return _onlineUserIds.contains(userId);
  }

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    WidgetsBinding.instance.addObserver(this);
    _setupAuthListener();

    if (_supabase.auth.currentUser != null) {
      _startPresence();
    }
  }

  void _setupAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed) {
        if (_isInForeground) {
          _startPresence();
        }
      } else if (event == AuthChangeEvent.signedOut) {
        _stopPresence();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _inactiveDebounceTimer?.cancel();
      _inactiveDebounceTimer = null;
      _isInForeground = true;
      _startPresence();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached ||
               state == AppLifecycleState.hidden) {
      _inactiveDebounceTimer?.cancel();
      _inactiveDebounceTimer = null;
      _isInForeground = false;
      _pausePresence();
    } else if (state == AppLifecycleState.inactive) {
      // Inactive can be a transient transition (e.g. system dialog or app switcher).
      // If it does not resume within 1.5 seconds, mark as backgrounded.
      _inactiveDebounceTimer?.cancel();
      _inactiveDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!_isInForeground) return;
        _isInForeground = false;
        _pausePresence();
      });
    }
  }

  Future<void> _startPresence() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    // 1. Immediately update last_seen in database
    _chatService.updateLastSeen();

    // 2. Setup Realtime Presence channel if needed
    if (_presenceChannel == null) {
      _presenceChannel = _supabase.channel('app_online_presence');

      _presenceChannel!
        .onPresenceSync((_) => _updateOnlineUsersFromState())
        .onPresenceJoin((_) => _updateOnlineUsersFromState())
        .onPresenceLeave((_) => _updateOnlineUsersFromState());

      _presenceChannel!.subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _isSubscribed = true;
          if (_isInForeground) {
            await _trackPresence();
          }
          _updateOnlineUsersFromState();
        } else if (status == RealtimeSubscribeStatus.closed ||
                   status == RealtimeSubscribeStatus.channelError) {
          _isSubscribed = false;
        }
      });
    } else if (_isSubscribed && _isInForeground) {
      await _trackPresence();
    }

    // 3. Heartbeat timer every 25 seconds while in foreground
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_isInForeground && _supabase.auth.currentUser != null) {
        _chatService.updateLastSeen();
        if (_isSubscribed) {
          _trackPresence();
        }
      }
    });
  }

  Future<void> _trackPresence() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || _presenceChannel == null) return;
    try {
      await _presenceChannel!.track({
        'user_id': myId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error tracking presence: $e');
    }
  }

  Future<void> _pausePresence() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Immediately untrack from realtime presence channel so others see inactive immediately
    try {
      await _presenceChannel?.untrack();
    } catch (e) {
      debugPrint('Error untracking presence: $e');
    }

    // Update last_seen to the exact departure time in database
    final myId = _supabase.auth.currentUser?.id;
    if (myId != null) {
      try {
        await _supabase
            .from('create_account')
            .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
            .eq('id', myId);
      } catch (e) {
        debugPrint('Error updating last_seen on app pause: $e');
      }
    }
  }

  Future<void> _stopPresence() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inactiveDebounceTimer?.cancel();
    _inactiveDebounceTimer = null;
    _onlineUserIds.clear();
    _isSubscribed = false;
    notifyListeners();

    try {
      await _presenceChannel?.untrack();
      await _presenceChannel?.unsubscribe();
    } catch (_) {}
    _presenceChannel = null;
  }

  void _updateOnlineUsersFromState() {
    final states = _presenceChannel?.presenceState() ?? [];
    final newSet = <String>{};
    for (final state in states) {
      for (final presence in state.presences) {
        final uid = presence.payload['user_id']?.toString();
        if (uid != null && uid.isNotEmpty) {
          newSet.add(uid);
        }
      }
    }
    _onlineUserIds.clear();
    _onlineUserIds.addAll(newSet);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _inactiveDebounceTimer?.cancel();
    try {
      _presenceChannel?.untrack();
      _presenceChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }
}
