import 'package:flutter/material.dart';
import 'dart:async';
import '../../utils/session_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../share/share_controller.dart';
import '../../share/select_forward_chat_page.dart';
import '../../providers/auth_provider.dart' as local_auth;
import '../../models/user_model.dart';

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
    _resolveAndNavigate();
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
      // Give FirebaseAuth a brief moment to restore the user from disk
      final auth = FirebaseAuth.instance;
      User? user = auth.currentUser;
      if (user == null) {
        try {
          user = await auth.authStateChanges().first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
        } catch (_) {}
      }

      // Keep the splash visible for a short, smooth animation
      await Future.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;

      // Check for share intent
      final shareController = Provider.of<ShareController>(
        context,
        listen: false,
      );
      if (shareController.hasShareData) {
        // Get current user to check role
        final authProvider = Provider.of<local_auth.AuthProvider>(
          context,
          listen: false,
        );
        final currentUser = authProvider.currentUser;

        if (currentUser == null) {
          // User not logged in - go to login, share data will be handled after login
          Navigator.pushReplacementNamed(context, '/role-selection');
          return;
        }

        // Check if user is principal
        if (currentUser.role == UserRole.institute) {
          // Navigate to forward page
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  SelectForwardChatPage(shareData: shareController.shareData!),
            ),
          );
          return;
        } else {
          // Not principal - show message and clear share data
          shareController.clearShareData();

          // Show message after a brief delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ Forwarding allowed only for Principal'),
                  duration: Duration(seconds: 3),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          });
        }
      }

      // Normal navigation
      final route = await SessionManager.getInitialScreen();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/role-selection');
    }
  }
}
