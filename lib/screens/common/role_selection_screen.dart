import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/role_provider.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final roleProvider = Provider.of<RoleProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1A1A1A), // Dark background
                    const Color(0xFF2A2A2A), // Slightly lighter
                    const Color(0xFF3A3A3A), // Medium dark
                  ]
                : [
                    const Color(0xFFFFD4B3), // Lighter peachy orange
                    const Color(0xFFFFB380), // Light orange
                    const Color(0xFFF97316), // Main orange #F97316
                  ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 30),
                // Title
                const Text(
                  'LenV',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Welcome to your Portal',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 35),
                const Text(
                  'Choose your role to login',
                  style: TextStyle(
                    fontSize: 17,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 25),
                // Role Cards Grid
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildRoleCard(
                                context,
                                role: UserRole.student,
                                title: 'Student',
                                icon: Icons.school_rounded,
                                onTap: () {
                                  roleProvider.setRole(UserRole.student);
                                  Navigator.pushNamed(
                                    context,
                                    '/student-login',
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: _buildRoleCard(
                                context,
                                role: UserRole.teacher,
                                title: 'Teacher',
                                icon: Icons.menu_book_rounded,
                                onTap: () {
                                  roleProvider.setRole(UserRole.teacher);
                                  Navigator.pushNamed(
                                    context,
                                    '/teacher-login',
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRoleCard(
                                context,
                                role: UserRole.parent,
                                title: 'Parent',
                                icon: Icons.family_restroom_rounded,
                                onTap: () {
                                  roleProvider.setRole(UserRole.parent);
                                  Navigator.pushNamed(context, '/parent-login');
                                },
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: _buildRoleCard(
                                context,
                                role: UserRole.institute,
                                title: 'Institute',
                                icon: Icons.business_rounded,
                                onTap: () {
                                  roleProvider.setRole(UserRole.institute);
                                  Navigator.pushNamed(
                                    context,
                                    '/institute-login',
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),
                      ],
                    ),
                  ),
                ),
                // Version at bottom
                Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: Column(
                    children: [
                      Text(
                        'Educational Ecosystem',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.85),
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

  Widget _buildRoleCard(
    BuildContext context, {
    required UserRole role,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.15),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withOpacity(isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 55,
                color: const Color(0xFFF97316), // Orange icon color
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF2D2D2D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
