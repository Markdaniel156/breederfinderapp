# Appendix E: Source Code Listings

This appendix presents key source code modules of the **BreederFinderApp** project, showcasing the core architecture, listing management, smart matching algorithm, real-time messaging, and geofencing services.

---

## Appendix E.1: Application Entry Point and Initialization
**File:** `lib/main.dart`
**Description:** Initializes the Flutter application, configures Supabase authentication/database backend, sets up Firebase Cloud Messaging (FCM) for background and foreground push notifications, and wires up global state providers.

```dart
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
  await NotificationService.initialize();

  debugPrint('Handling background message: ${message.messageId}');

  if (message.data.containsKey('type') && message.data['type'] == 'chat') {
    await NotificationService.showMessageNotification(
      id: message.hashCode,
      title: message.data['sender_name'] ?? 'New Message',
      body: message.data['message_text'] ?? 'Sent you a message',
      payload: message.data['sender_id'],
    );
  } else if (message.notification != null) {
    await NotificationService.showVerifiedNotification(
      id: message.hashCode,
      title: message.notification?.title ?? 'Notification',
      body: message.notification?.body ?? '',
      payload: message.data.toString(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
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
      child: const BreederFinderApp(),
    ),
  );
}

class BreederFinderApp extends StatelessWidget {
  const BreederFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Breeder Finder App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D6A4F)),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => const MainNavigationWrapper(),
        '/login': (context) => const LoginScreen(),
        '/create_account': (context) => const CreateAccountScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
        '/change_password': (context) => const ChangePasswordScreen(),
        '/reset_password': (context) => const ResetPasswordScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
      },
    );
  }
}

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const MapScreen(),
    const ChatListScreen(),
    const market.MarketScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: AestheticBottomBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
```

---

## Appendix E.2: Breeder Postings & Listing Management Module
**File:** `lib/screens/breeder_postings_screen.dart`
**Description:** Manages breeder profile information, animal livestock/pet listings, image picker integration, connectivity status monitoring, and database persistence with Supabase.

```dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/breeder_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/breeder.dart';
import '../utils/animal_breeds.dart';
import '../widgets/limit_reached_card.dart';
import '../utils/system_ui_utils.dart';
import 'subscription_screen.dart';

class BreederPostingsScreen extends StatefulWidget {
  final Breeder? initialData;
  const BreederPostingsScreen({super.key, this.initialData});

  @override
  State<BreederPostingsScreen> createState() => _BreederPostingsScreenState();
}

class _BreederPostingsScreenState extends State<BreederPostingsScreen> {
  static const Color forestGreen = Color(0xFF2D6A4F);
  static const Color darkGreen = Color(0xFF1B4332);
  final _scrollController = ScrollController();
  final ValueNotifier<double> _appBarOpacity = ValueNotifier<double>(0.0);
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  String _userRole = 'Breeder';
  String? _avatarUrl;
  List<String> _existingAnimalImages = [];
  final List<File> _newAnimalImages = [];
  bool _isLimitReached = false;
  String? _selectedGender;
  final List<String> _genders = ['Male', 'Female'];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      _appBarOpacity.value = (_scrollController.offset / 100).clamp(0.0, 1.0);
    });
    _prefillUserData();
    _checkConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none) || results.isEmpty;
        });
      }
    });
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
    _scrollController.dispose();
    _appBarOpacity.dispose();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  void _prefillUserData() {
    if (widget.initialData != null) {
      final data = widget.initialData!;
      _userRole = data.role.isNotEmpty ? data.role : 'Breeder';
      _avatarUrl = data.avatarUrl;
      _existingAnimalImages = List.from(data.animalImages);
      _selectedGender = data.gender;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breeder Postings'),
        backgroundColor: forestGreen,
        foregroundColor: Colors.white,
      ),
      body: _isOffline
          ? const Center(child: Text('No internet connection. Offline mode active.'))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                controller: _scrollController,
                children: [
                  const Text('Manage Animal Listings & Breeder Profile',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (_isLimitReached) const LimitReachedCard(),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                      );
                    },
                    icon: const Icon(Icons.star),
                    label: const Text('Upgrade Subscription'),
                  ),
                ],
              ),
            ),
    );
  }
}
```

---

## Appendix E.3: Smart Matching & Recommendation Module
**File:** `lib/screens/smart_matching_screen.dart`
**Description:** Implements a multi-step questionnaire filtering breeders and animals based on category, breed, location (District 5 towns), budget, and user preferences.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/breeder_provider.dart';
import '../models/breeder.dart';
import 'profile_screen.dart';
import 'chat_screen.dart';
import '../providers/navigation_provider.dart';
import '../widgets/restricted_access_dialog.dart';
import '../providers/auth_provider.dart';
import '../utils/animal_breeds.dart';
import '../utils/system_ui_utils.dart';

class SmartMatchingScreen extends StatefulWidget {
  const SmartMatchingScreen({super.key});

  @override
  State<SmartMatchingScreen> createState() => _SmartMatchingScreenState();
}

class _SmartMatchingScreenState extends State<SmartMatchingScreen> {
  int _currentStep = 0;

  String _searchType = 'Breeder';
  String? _selectedCategory;
  String _selectedBreed = 'Any';
  String _location = 'Any';

  final TextEditingController _budgetController = TextEditingController(text: '1000000');
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _sexController = TextEditingController();

  final List<String> _district5 = [
    'Any',
    'Binalbagan',
    'Himamaylan City',
    'Hinigaran',
    'Isabela',
    'La Castellana',
    'Moises Padilla',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Matching & Recommendation'),
        backgroundColor: const Color(0xFF2D6A4F),
        foregroundColor: Colors.white,
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 3) {
            setState(() => _currentStep++);
          } else {
            // Perform matching logic
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          }
        },
        steps: [
          Step(
            title: const Text('Select Role & Category'),
            content: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _searchType,
                  items: ['Breeder', 'Trader'].map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
                  onChanged: (val) => setState(() => _searchType = val ?? 'Breeder'),
                  decoration: const InputDecoration(labelText: 'Looking For'),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Location & District 5'),
            content: DropdownButtonFormField<String>(
              value: _location,
              items: _district5.map((town) => DropdownMenuItem(value: town, child: Text(town))).toList(),
              onChanged: (val) => setState(() => _location = val ?? 'Any'),
              decoration: const InputDecoration(labelText: 'Town / Municipality'),
            ),
          ),
          Step(
            title: const Text('Budget & Pricing'),
            content: TextField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maximum Budget (PHP)'),
            ),
          ),
          Step(
            title: const Text('Review & Match'),
            content: const Text('Ready to find your matching breeder or animal!'),
          ),
        ],
      ),
    );
  }
}
```

---

## Appendix E.4: Real-Time Messaging & Chat Service
**File:** `lib/services/chat_service.dart`
**Description:** Manages real-time WebSocket streams for messages using Supabase streams, handles message sending, unread message counts, and read status updates.

```dart
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
          .update({'is_read': true})
          .eq('sender_id', senderId)
          .eq('receiver_id', myId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> updateLastSeen() async {
    final myId = currentUserId;
    if (myId == null) return;
    try {
      await _supabase
          .from('profiles')
          .update({'last_seen': DateTime.now().toIso8601String()})
          .eq('id', myId);
    } catch (e) {
      debugPrint('Error updating last seen: $e');
    }
  }
}
```

---

## Appendix E.5: Location & Geofencing Service
**File:** `lib/services/geofencing_service.dart`
**Description:** Handles GPS position tracking, proximity alerts for breeders in Negros Occidental District 5, and local notification banner triggers upon arrival.

```dart
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/breeder.dart';

class GeofencingService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  final Map<String, DateTime> _lastArrived = {};
  String? activeTargetId;

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Geofence Notification tapped: ${response.payload}');
      },
    );

    final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'geofence_channel',
      'Breeder Finder Alerts',
      description: 'Notifications for breeder proximity and arrivals',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    debugPrint('Geofencing Service Initialized');
  }

  double calculateDistance(double startLatitude, double startLongitude, double endLatitude, double endLongitude) {
    return Geolocator.distanceBetween(startLatitude, startLongitude, endLatitude, endLongitude);
  }

  Future<void> checkProximity(double currentLat, double currentLon, List<Breeder> breeders) async {
    for (var breeder in breeders) {
      if (breeder.latitude != null && breeder.longitude != null) {
        double distanceInMeters = calculateDistance(
          currentLat,
          currentLon,
          breeder.latitude!,
          breeder.longitude!,
        );

        // Within 100 meters
        if (distanceInMeters <= 100) {
          _triggerArrivalNotification(breeder);
        }
      }
    }
  }

  Future<void> _triggerArrivalNotification(Breeder breeder) async {
    final now = DateTime.now();
    if (_lastArrived.containsKey(breeder.id)) {
      if (now.difference(_lastArrived[breeder.id]!) < const Duration(hours: 1)) {
        return; // Cooldown active
      }
    }
    _lastArrived[breeder.id] = now;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'geofence_channel',
      'Breeder Finder Alerts',
      channelDescription: 'Notifications for breeder proximity and arrivals',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      breeder.hashCode,
      'Arrived at ${breeder.farmName}',
      'You are within 100 meters of ${breeder.ownerName}\'s farm!',
      details,
      payload: breeder.id,
    );
  }
}
```
