import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart' as local_auth;
import 'providers/role_provider.dart';
import 'providers/test_provider.dart';
import 'providers/reward_provider.dart';
import 'providers/student_provider.dart';
import 'providers/daily_challenge_provider.dart';
import 'providers/parent_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/unread_count_provider.dart';
import 'utils/navigation_debounce_observer.dart';
import 'routes/app_router.dart';
import 'services/local_cache_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_cache_manager.dart';
import 'share/share_controller.dart';
import 'share/share_receiver_service.dart';

// Initial route is always '/' (Splash) which will resolve and redirect.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (with duplicate check for hot reload)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Hive once before any service uses it
    await Hive.initFlutter();

    // Enable offline persistence for Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

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
    // Run all service initializations in parallel
    await Future.wait([
      LocalCacheService().initialize(),
      OfflineCacheManager().initialize(),
      ConnectivityService().initialize(),
      ShareReceiverService().initialize(),
    ], eagerError: false); // Continue even if one fails
  } catch (e) {
    // Services failed to initialize, but app can still run
    print('⚠️ Service initialization error: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
        ChangeNotifierProvider(create: (_) => RewardProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => ParentProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UnreadCountProvider()),
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
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            onGenerateRoute: AppRouter.generateRoute,
            navigatorObservers: [NavigationDebounceObserver()],
            initialRoute: '/',
          );
        },
      ),
    );
  }
}
