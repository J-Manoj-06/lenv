import 'package:flutter/material.dart';
import 'dart:async';
import '../../utils/session_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../share/share_controller.dart';
import '../../share/share_target_screen.dart';
import '../../providers/auth_provider.dart' as local_auth;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();

    // Decide the next route based on stored session and restored auth
    // Use post-frame callback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveAndNavigate();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFD4B3), // Lighter peachy orange
              Color(0xFFFFB380), // Light orange
              Color(0xFFF97316), // Main orange #F97316
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Spacer(),
                // Main Content
                Column(
                  children: [
                    // Logo/Icon
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        size: 80,
                        color: Color(0xFFF97316), // Orange icon
                      ),
                    ),
                    const SizedBox(height: 40),
                    // App Name
                    const Text(
                      'LenV',
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 3,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Tagline
                    const Text(
                      'Welcome to your Portal',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 50),
                    // Loading indicator
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 4,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Version at bottom
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    children: [
                      Text(
                        'Educational Ecosystem',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w300,
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
    );
  }

  Future<void> _resolveAndNavigate() async {
    try {
      // Initialize auth provider first
      final authProvider = Provider.of<local_auth.AuthProvider>(
        context,
        listen: false,
      );

      // Ensure auth is initialized before checking user
      // Use a timeout so Firestore hangs don't block navigation indefinitely
      await authProvider.ensureInitialized().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint(
            '⚠️ Auth initialization timed out, proceeding with cached state',
          );
        },
      );

      // Parallelize auth check and session retrieval for faster startup
      final results = await Future.wait([
        _getFirebaseUser(),
        SessionManager.getInitialScreen(),
      ]);

      final initialRoute = results[1];

      // Minimal splash delay for smooth animation
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Check for share intent
      final shareController = Provider.of<ShareController>(
        context,
        listen: false,
      );

      // Check if we have share data BEFORE checking user
      final hasShare = shareController.hasShareData;
      final shareData = shareController.shareData;

      if (hasShare && shareData != null) {
        // Get current user to check role
        final currentUser = authProvider.currentUser;

        if (currentUser == null) {
          // User not logged in - clear share data and go to login
          shareController.clearShareData();
          Navigator.pushReplacementNamed(context, '/role-selection');
          return;
        }

        // Clear from controller AFTER we have the data
        shareController.clearShareData();

        // Navigate to comprehensive share target screen for all roles
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ShareTargetScreen(shareData: shareData),
          ),
        );
        return;
      }

      // Normal navigation
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, initialRoute as String);
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/role-selection');
    }
  }

  /// Get Firebase user with timeout to avoid waiting too long
  Future<User?> _getFirebaseUser() async {
    final auth = FirebaseAuth.instance;
    User? user = auth.currentUser;
    if (user == null) {
      try {
        user = await auth.authStateChanges().first.timeout(
          const Duration(milliseconds: 800),
          onTimeout: () => null,
        );
      } catch (_) {}
    }
    return user;
  }
}
