import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart' as local_auth;
import 'providers/profile_dp_provider.dart';
import 'providers/role_provider.dart';
import 'providers/test_provider.dart';
import 'providers/reward_provider.dart';
import 'providers/student_provider.dart';
import 'providers/daily_challenge_provider.dart';
import 'providers/test_assignment_lock_provider.dart';
import 'providers/parent_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/unread_count_provider.dart';
import 'utils/navigation_debounce_observer.dart';
import 'routes/app_router.dart';
import 'services/local_cache_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_cache_manager.dart';
import 'services/offline_data_service.dart';
import 'services/offline_first_initializer.dart';
import 'services/notification_service.dart';
import 'services/background_download_service.dart';
import 'services/school_storage_service.dart';
import 'models/local_message.dart';
import 'share/share_controller.dart';
import 'share/share_receiver_service.dart';
import 'config/dashboard_setup.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Initial route is always '/' (Splash) which will resolve and redirect.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait-only orientation across the app.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize School Storage first (for onboarding flow)
  await schoolStorageService.initialize();

  // Initialize Firebase (with duplicate check for hot reload)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Firebase Messaging background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize Hive once before any service uses it
    await Hive.initFlutter();

    // STEP 1: Register Hive adapters for offline-first messaging
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(LocalMessageAdapter());
    }

    // Enable offline persistence for Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Initialize dashboard setup
    await DashboardSetup.initialize();

    // Initialize services asynchronously without blocking app startup
    // These will complete in the background
    _initializeServicesAsync();
  } catch (e) {
    // If Firebase is already initialized (e.g., hot reload), ignore the error
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    } else {}
  }

  // Note: Removed client-side auto-publish sweep on startup to avoid
  // permission/index errors for student users. This operation should
  // be performed only from teacher/admin contexts or backend cron.

  runApp(const MyApp());
}

/// Initialize services asynchronously to avoid blocking startup
Future<void> _initializeServicesAsync() async {
  try {
    // Initialize connectivity first so Firestore network state is applied
    // before any other services start Firestore reads/writes.
    await ConnectivityService().initialize();

    // Run all service initializations in parallel
    await Future.wait([
      LocalCacheService().initialize(),
      OfflineCacheManager().initialize(),
      OfflineDataService().initialize(), // ✅ Added new offline service
      ShareReceiverService().initialize(),
      NotificationService().initialize(), // ✅ Initialize notification service
      BackgroundDownloadService()
          .initialize(), // ✅ Initialize download notifications
    ], eagerError: false); // Continue even if one fails
  } catch (e) {
    // Services failed to initialize, but app can still run
    debugPrint('⚠️ Service initialization error: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<Map<String, dynamic>>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    _notificationTapSub = NotificationService().notificationTapStream.listen(
      _handleNotificationTap,
    );
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    super.dispose();
  }

  void _handleNotificationTap(Map<String, dynamic> payload) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    final route = payload['deepLinkRoute']?.toString();
    final targetRoute = (route != null && route.isNotEmpty)
        ? route
        : '/notifications';

    navigator.pushNamed(targetRoute, arguments: payload);
  }

  @override
  Widget build(BuildContext context) {
    return DashboardSetup.wrapWithProviders(
      child: MultiProvider(
        providers: [
          // STEP 2: Add OfflineMessageProvider for offline-first messaging
          ChangeNotifierProvider(
            create: (_) => OfflineMessageProvider()..initialize(),
          ),
          ChangeNotifierProvider(
            create: (_) {
              final authProvider = local_auth.AuthProvider();
              // Initialize auth state from Firebase
              authProvider.initializeAuth();
              return authProvider;
            },
          ),
          ChangeNotifierProvider(
            create: (_) {
              final shareController = ShareController();
              shareController.initialize();
              return shareController;
            },
          ),
          ChangeNotifierProvider(create: (_) => RoleProvider()),
          ChangeNotifierProvider(create: (_) => TestProvider()),
          ChangeNotifierProvider(create: (_) => TestAssignmentLockProvider()),
          ChangeNotifierProvider(create: (_) => RewardProvider()),
          ChangeNotifierProvider(create: (_) => StudentProvider()),
          ChangeNotifierProxyProvider<local_auth.AuthProvider, ParentProvider>(
            create: (_) => ParentProvider(),
            update: (context, auth, previous) {
              final provider = previous ?? ParentProvider();
              if (auth.currentUser == null || auth.isSigningOut) {
                provider.clear();
              }
              return provider;
            },
          ),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProxyProvider<
            local_auth.AuthProvider,
            ProfileDPProvider
          >(
            create: (_) => ProfileDPProvider(),
            update: (context, auth, previous) {
              final provider = previous ?? ProfileDPProvider();
              if (auth.currentUser == null || auth.isSigningOut) {
                provider.clearSession();
              }
              return provider;
            },
          ),
          ChangeNotifierProxyProvider<
            local_auth.AuthProvider,
            UnreadCountProvider
          >(
            create: (_) => UnreadCountProvider(),
            update: (context, auth, previous) {
              final provider = previous ?? UnreadCountProvider();
              if (auth.currentUser != null && !auth.isSigningOut) {
                provider.initialize(auth.currentUser!.uid);
              } else {
                provider.logout();
              }
              return provider;
            },
          ),
          ChangeNotifierProxyProvider<
            local_auth.AuthProvider,
            DailyChallengeProvider
          >(
            create: (_) => DailyChallengeProvider(),
            update: (context, auth, previous) {
              // When user logs out, clear all cached challenge state
              if (auth.currentUser == null && previous != null) {
                previous.clearAllState();
              }
              return previous ?? DailyChallengeProvider();
            },
          ),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return MaterialApp(
              title: 'LenV - Educational Ecosystem',
              debugShowCheckedModeBanner: false,
              navigatorKey: appNavigatorKey,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
              onGenerateRoute: AppRouter.generateRoute,
              navigatorObservers: [NavigationDebounceObserver()],
              initialRoute: '/',
            );
          },
        ),
      ),
    );
  }
}
