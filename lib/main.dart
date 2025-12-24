import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'routes/app_router.dart';
import 'services/local_cache_service.dart';

// Initial route is always '/' (Splash) which will resolve and redirect.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (with duplicate check for hot reload)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');

    // Initialize Local Cache Service for media messaging
    await LocalCacheService().initialize();
    print('✅ Local cache service initialized');

    // Enable offline persistence for Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    print('✅ Firestore offline persistence enabled');

    // Test Firestore connection
    try {
      print('🔥 Testing Firestore connection...');
      final testQuery = await FirebaseFirestore.instance
          .collection('schools')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      print('✅ Firestore connected! Found ${testQuery.docs.length} schools');
      if (testQuery.docs.isNotEmpty) {
        print('   Sample school: ${testQuery.docs.first.data()}');
      }
    } catch (firestoreError) {
      print('❌ Firestore connection error: $firestoreError');
      print('   This usually means:');
      print('   1. Firestore rules deny access');
      print('   2. Collection does not exist');
      print('   3. Network/internet issue');
      print('   App will use cached data if available');
    }
  } catch (e) {
    // If Firebase is already initialized (e.g., hot reload), ignore the error
    if (!e.toString().contains('duplicate-app')) {
      print('❌ Firebase initialization error: $e');
      rethrow;
    } else {
      print('ℹ️ Firebase already initialized (hot reload)');
    }
  }

  // Note: Removed client-side auto-publish sweep on startup to avoid
  // permission/index errors for student users. This operation should
  // be performed only from teacher/admin contexts or backend cron.

  runApp(const MyApp());
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
              print('🔄 User logged out - clearing daily challenge state');
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
            initialRoute: '/',
          );
        },
      ),
    );
  }
}
