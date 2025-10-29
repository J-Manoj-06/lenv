import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart' as local_auth;
import 'providers/role_provider.dart';
import 'providers/test_provider.dart';
import 'providers/reward_provider.dart';
import 'providers/student_provider.dart';
import 'routes/app_router.dart';
import 'services/firestore_service.dart';

Future<String> getInitialScreen() async {
  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final role = prefs.getString('userRole');
  final user = FirebaseAuth.instance.currentUser;
  if (isLoggedIn && user != null) {
    if (role == 'teacher') {
      return '/teacher-dashboard';
    } else if (role == 'student') {
      return '/student-dashboard';
    }
  }
  // No session: go to role selection (valid route)
  return '/role-selection';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (with duplicate check for hot reload)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');

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

  // Best-effort: run an auto-publish sweep once on app start
  try {
    final updated = await FirestoreService().autoPublishExpiredTests();
    if (updated > 0) {
      // ignore: avoid_print
      print('📣 Auto-published $updated expired tests on startup');
    }
  } catch (e) {
    // ignore: avoid_print
    print('⚠️ Auto-publish on startup failed: $e');
  }

  final initialRoute = await getInitialScreen();
  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => local_auth.AuthProvider()),
        ChangeNotifierProvider(create: (_) => RoleProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => RewardProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
      ],
      child: MaterialApp(
        title: 'LenV - Educational Ecosystem',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        onGenerateRoute: AppRouter.generateRoute,
        initialRoute: initialRoute,
      ),
    );
  }
}
