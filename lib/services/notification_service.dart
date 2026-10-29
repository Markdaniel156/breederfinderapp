import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/chat_screen.dart';
import '../main.dart';

// Use a single global instance for consistency
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint('Notification tapped in background: ${notificationResponse.payload}');
}

class NotificationService {
  static String? activeChatId;
  static String? pendingPayload;

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final NotificationAppLaunchDetails? notificationAppLaunchDetails =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (notificationAppLaunchDetails != null &&
        notificationAppLaunchDetails.didNotificationLaunchApp) {
      pendingPayload = notificationAppLaunchDetails.notificationResponse?.payload;
      debugPrint('App launched from notification payload: $pendingPayload');
    }

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification tapped: ${response.payload}');
        handleNotificationTap(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Create Chat Channel with high importance for heads-up (banner)
    const AndroidNotificationChannel chatChannel = AndroidNotificationChannel(
      'chat_messages',
      'Chat Messages',
      description: 'Notifications for new messages',
      importance: Importance.max, // Required for heads-up
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Create Verified Channel
    const AndroidNotificationChannel verifiedChannel = AndroidNotificationChannel(
      'verified_notifications',
      'Verified Notifications',
      description: 'Status updates for your account',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Register channels with the system
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(chatChannel);
    await androidImplementation?.createNotificationChannel(verifiedChannel);

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    await androidPlugin?.createNotificationChannel(chatChannel);
    await androidPlugin?.createNotificationChannel(verifiedChannel);
    
    // Request permission for Android 13+
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Don't show notification if we're already in the chat with this person
    if (payload != null && payload == activeChatId) {
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      channelDescription: 'Notifications for new messages',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      category: AndroidNotificationCategory.message,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'chat_messages',
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  static Future<void> showVerifiedNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'verified_notifications',
      'Verified Notifications',
      channelDescription: 'Status updates for your account',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  static Future<void> handleNotificationTap(String? payload) async {
    if (payload == null) return;

    if (navigatorKey.currentState == null) {
      pendingPayload = payload;
      debugPrint('Navigator not ready. Stored pending payload: $payload');
      return;
    }

    pendingPayload = null;
    if (payload.startsWith('chat:')) {
      final senderId = payload.substring(5);
      await navigateToChat(senderId);
    } else {
      navigatorKey.currentState?.pushNamed('/notifications');
    }
  }

  static Future<void> checkPendingPayload() async {
    if (pendingPayload != null && navigatorKey.currentState != null) {
      final payload = pendingPayload;
      pendingPayload = null;
      await handleNotificationTap(payload);
    }
  }

  static Future<void> handleRemoteMessageTap(Map<String, dynamic> data) async {
    final type = data['type'];
    if (type == 'chat') {
      final senderId = data['sender_id'];
      if (senderId != null) {
        await navigateToChat(senderId);
      }
    } else {
      navigatorKey.currentState?.pushNamed('/notifications');
    }
  }

  static Future<void> navigateToChat(String senderId) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('create_account')
          .select('full_name, avatar_url')
          .eq('id', senderId)
          .maybeSingle();

      final name = response?['full_name'] ?? 'Chat';
      final avatarUrl = response?['avatar_url'];

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            breederId: senderId,
            breederName: name,
            breederAvatarUrl: avatarUrl,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error navigating to chat from notification: $e');
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            breederId: senderId,
            breederName: 'Chat',
          ),
        ),
      );
    }
  }
}
