import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'providers/breeder_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/report_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/market_screen.dart' as market;
import 'screens/breeder_postings_screen.dart';
import 'screens/trader_postings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/create_account_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/notification_screen.dart';
import 'dart:async';
import 'screens/splash_screen.dart';
import 'services/geofencing_service.dart';
import 'services/supabase_config.dart';
import 'services/connectivity_service.dart';
import 'utils/system_ui_utils.dart';
import 'services/notification_service.dart';

import 'widgets/aesthetic_bottom_bar.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Initialize notification service in the background isolate
  await NotificationService.initialize();
  
  debugPrint('Handling background message: ${message.messageId}');

  // Show notification even if app is in background/closed (if it's a data message)
  if (message.data.containsKey('type') && message.data['type'] == 'chat') {
    await NotificationService.showMessageNotification(
      id: message.hashCode,
      title: message.data['sender_name'] ?? 'New Message',
      body: message.data['message_text'] ?? 'Sent you a message',
      payload: 'chat:${message.data['sender_id']}',
    );
  } else if (message.notification != null) {
    // If it's a notification message, FCM usually handles it, but if you want 
    // to ensure it uses your local notification logic/channel:
    await NotificationService.showVerifiedNotification(
      id: message.hashCode,
      title: message.notification?.title ?? 'Notification',
      body: message.notification?.body ?? '',
      payload: message.data.toString(),
    );
  }
}

void _showLocalNotification(RemoteMessage message) {
  final notification = message.notification;
  final data = message.data;
  
  if (data['type'] == 'chat') {
    NotificationService.showMessageNotification(
      id: message.hashCode,
      title: data['sender_name'] ?? notification?.title ?? 'New Message',
      body: data['message_text'] ?? notification?.body ?? 'Sent you a message',
      payload: 'chat:${data['sender_id']}',
    );
  } else {
    NotificationService.showVerifiedNotification(
      id: message.hashCode,
      title: notification?.title ?? 'Notification',
      body: notification?.body ?? '',
      payload: data.toString(),
    );
  }
}

class NotificationNavigationHandler {
  static Map<String, dynamic>? pendingRemoteData;

  static Future<void> handleRemoteMessageTap(Map<String, dynamic> data) async {
    if (navigatorKey.currentState == null) {
      pendingRemoteData = data;
      debugPrint('Navigator not ready. Stored pending remote data: $data');
      return;
    }
    pendingRemoteData = null;
    final type = data['type'];
    if (type == 'chat') {
      final senderId = data['sender_id'];
      if (senderId != null) {
        await NotificationService.navigateToChat(senderId);
      }
    } else {
      navigatorKey.currentState?.pushNamed('/notifications');
    }
  }

  static Future<void> checkPendingRemoteData() async {
    if (pendingRemoteData != null && navigatorKey.currentState != null) {
      final data = pendingRemoteData;
      pendingRemoteData = null;
      await handleRemoteMessageTap(data!);
    }
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Firebase
  await Firebase.initializeApp();

  // ✅ Initialize notifications
  await NotificationService.initialize();

  // ✅ Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ✅ Request notification permissions
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // ✅ FOREGROUND notification handler — shows notification while app is open
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Foreground message received: ${message.messageId}');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    _showLocalNotification(message); // manually show it as local notification
  });

  // ✅ When notification is tapped and app was in BACKGROUND (not killed)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('Notification tapped (background): ${message.messageId}');
    NotificationNavigationHandler.handleRemoteMessageTap(message.data);
  });

  // ✅ When notification is tapped and app was TERMINATED
  final RemoteMessage? initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('App opened from terminated via notification: ${initialMessage.messageId}');
    NotificationNavigationHandler.handleRemoteMessageTap(initialMessage.data);
  }

  // ✅ Token refresh listener — keeps Supabase updated automatically
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await Supabase.instance.client
          .from('create_account')
          .update({'fcm_token': newToken})
          .eq('id', user.id);
      debugPrint('FCM Token refreshed and updated: $newToken');
    }
  });

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final geofenceService = GeofencingService();
  await geofenceService.initialize();

  // Update FCM token if user is already logged in
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (currentUser != null) {
    try {
      debugPrint('Fetching FCM Token for user: ${currentUser.id}...');
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        debugPrint('FCM Token found: $fcmToken');
        await Supabase.instance.client
            .from('create_account')
            .update({'fcm_token': fcmToken})
            .eq('id', currentUser.id);
        debugPrint('Supabase updated successfully with token.');
      } else {
        debugPrint('FCM Token is NULL. Ensure Google Play Services are available.');
      }
    } catch (e) {
      debugPrint('CRITICAL ERROR updating FCM token: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BreederProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ReportProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MyApp(geofenceService: geofenceService),
    ),
  );
}

class MyApp extends StatefulWidget {
  final GeofencingService geofenceService;

  const MyApp({super.key, required this.geofenceService});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        debugPrint('Password recovery event detected!');
        navigatorKey.currentState?.pushNamed('/reset-password');
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    SystemChrome.setSystemUIOverlayStyle(SystemUiUtils.getOverlayStyle(isDark: isDark));

    return MaterialApp(
      title: 'BreederFinder',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Colors.white,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Color(0xFF121212),
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        ),
      ),
      builder: (context, child) {
        return AnimatedTheme(
          data: Theme.of(context),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          child: child!,
        );
      },
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
        '/change-password': (context) => const ChangePasswordScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/home': (context) => MainNavigation(geofenceService: widget.geofenceService),
        '/create-account': (context) => const CreateAccountScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        '/notifications': (context) => const NotificationScreen(),
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final GeofencingService geofenceService;
  const MainNavigation({super.key, required this.geofenceService});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final ConnectivityService _connectivityService = ConnectivityService();
  Timer? _approvalCheckTimer;

  @override
  void initState() {
    super.initState();
    _connectivityService.initialize(context);
    _startGeofencing();
    _fetchUserRole();
    _startApprovalCheckTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.checkPendingPayload();
      NotificationNavigationHandler.checkPendingRemoteData();
    });
  }

  void _startApprovalCheckTimer() {
    // Check for application approval every 30 seconds
    _approvalCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchUserRole(isPeriodic: true);
    });
  }

  Future<void> _fetchUserRole({bool isPeriodic = false}) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        
        // Sync role if an application was recently approved
        final newRole = await authProvider.syncUserRoleAfterApproval(user.id);
        
        if (newRole != null && mounted) {
          _showCongratsDialog(newRole);
        }

        final data = await Supabase.instance.client
            .from('create_account')
            .select('role')
            .eq('id', user.id)
            .single();
        if (mounted) {
          authProvider.setRole(data['role']?.toString());
        }
      }
    } catch (e) {
      if (!isPeriodic) {
        debugPrint('Error fetching role in navigation: $e');
      }
    }
  }

  void _showCongratsDialog(String role) {
    final roleText = role.toLowerCase().contains('breeder') && role.toLowerCase().contains('trader')
        ? 'Breeder and Trader'
        : (role.toLowerCase().contains('trader') ? 'Trader' : 'Breeder');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_rounded, color: Color(0xFF2D6A4F), size: 60),
            ),
            const SizedBox(height: 25),
            const Text(
              'Application Approved!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1B4332)),
            ),
            const SizedBox(height: 15),
            Text(
              'Congrats! Your requirements were approved to be a $roleText.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: const Text('Great, thanks!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _approvalCheckTimer?.cancel();
    _connectivityService.dispose();
    super.dispose();
  }

  void _startGeofencing() async {
    _updateFCMToken();
  }

  void _updateFCMToken() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        debugPrint('Nav: Requesting token...');
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          final res = await Supabase.instance.client
              .from('create_account')
              .update({'fcm_token': fcmToken})
              .eq('id', user.id)
              .select();

          if (res.isNotEmpty) {
            debugPrint('TOKEN SUCCESS: Token saved to Supabase: $fcmToken');
          } else {
            debugPrint('TOKEN FAILED: Row found but not updated. Check RLS Policies.');
          }
        } else {
          debugPrint('TOKEN FAILED: Firebase returned NULL token.');
        }
      }
    } catch (e) {
      debugPrint('TOKEN ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navProvider = Provider.of<NavigationProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final userRole = authProvider.role;
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    final List<Widget> screens = [
      const HomeScreen(),
      MapScreen(geofenceService: widget.geofenceService),
      const BreederPostingsScreen(),
      const market.MarketScreen(),
      const ChatListScreen(),
      const TraderPostingsScreen(),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: navProvider.selectedIndex,
        children: screens,
      ),
      floatingActionButton: isKeyboardVisible
          ? null
          : AestheticBottomBar.buildFloatingActionButton(context, isDark, userRole),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: isKeyboardVisible
          ? null
          : AestheticBottomBar.buildBottomNavigationBar(context, isDark),
    );
  }
}
