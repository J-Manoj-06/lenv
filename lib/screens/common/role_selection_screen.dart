import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/role_provider.dart';
import '../../services/school_storage_service.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final roleProvider = Provider.of<RoleProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompactHeight = screenHeight < 760;
    final isVeryCompactHeight = screenHeight < 700;
    final horizontalPadding = isCompactHeight ? 20.0 : 24.0;
    final topSpacing = isVeryCompactHeight
        ? 8.0
        : (isCompactHeight ? 14.0 : 30.0);
    final titleFontSize = isVeryCompactHeight
        ? 34.0
        : (isCompactHeight ? 38.0 : 42.0);
    final subTitleFontSize = isCompactHeight ? 16.0 : 18.0;
    final rolePromptTopSpacing = isCompactHeight ? 20.0 : 35.0;
    final rolePromptBottomSpacing = isCompactHeight ? 14.0 : 25.0;
    final roleCardGap = isCompactHeight ? 12.0 : 18.0;
    final roleCardHeight = isVeryCompactHeight
        ? 150.0
        : (isCompactHeight ? 165.0 : 190.0);
    final footerBottomPadding = isCompactHeight ? 16.0 : 25.0;
    final storedName = schoolStorageService.schoolName?.trim();
    final schoolDisplayName = (storedName == null || storedName.isEmpty)
        ? 'Your School'
        : storedName;

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
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              children: [
                SizedBox(height: topSpacing),
                // Title
                Text(
                  schoolDisplayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
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
                Text(
                  'Welcome to your Portal',
                  style: TextStyle(
                    fontSize: subTitleFontSize,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await schoolStorageService.clearSchoolData();
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/school-selection',
                          (route) => false,
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Unable to change school right now.'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Change School'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
                SizedBox(height: rolePromptTopSpacing),
                Text(
                  'Choose your role to login',
                  style: TextStyle(
                    fontSize: isCompactHeight ? 16 : 17,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: rolePromptBottomSpacing),
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
                                cardHeight: roleCardHeight,
                                isCompact: isCompactHeight,
                                onTap: () {
                                  roleProvider.setRole(UserRole.student);
                                  Navigator.pushNamed(
                                    context,
                                    '/student-login',
                                  );
                                },
                              ),
                            ),
                            SizedBox(width: roleCardGap),
                            Expanded(
                              child: _buildRoleCard(
                                context,
                                role: UserRole.teacher,
                                title: 'Teacher',
                                icon: Icons.menu_book_rounded,
                                cardHeight: roleCardHeight,
                                isCompact: isCompactHeight,
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
                        SizedBox(height: roleCardGap),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRoleCard(
                                context,
                                role: UserRole.parent,
                                title: 'Parent',
                                icon: Icons.family_restroom_rounded,
                                cardHeight: roleCardHeight,
                                isCompact: isCompactHeight,
                                onTap: () {
                                  roleProvider.setRole(UserRole.parent);
                                  Navigator.pushNamed(context, '/parent-login');
                                },
                              ),
                            ),
                            SizedBox(width: roleCardGap),
                            Expanded(
                              child: _buildRoleCard(
                                context,
                                role: UserRole.institute,
                                title: 'Institute',
                                icon: Icons.business_rounded,
                                cardHeight: roleCardHeight,
                                isCompact: isCompactHeight,
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
                        SizedBox(height: isCompactHeight ? 12 : 25),
                      ],
                    ),
                  ),
                ),
                // Version at bottom
                Padding(
                  padding: EdgeInsets.only(bottom: footerBottomPadding),
                  child: Column(
                    children: [
                      Text(
                        'Educational Ecosystem',
                        style: TextStyle(
                          fontSize: isCompactHeight ? 12 : 13,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontSize: isCompactHeight ? 11 : 12,
                          color: Colors.white.withValues(alpha: 0.85),
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
    required double cardHeight,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: cardHeight,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(isCompact ? 20 : 24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 16 : 20),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFF97316,
                ).withValues(alpha: isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: isCompact ? 44 : 55,
                color: const Color(0xFFF97316), // Orange icon color
              ),
            ),
            SizedBox(height: isCompact ? 12 : 16),
            Text(
              title,
              style: TextStyle(
                fontSize: isCompact ? 17 : 19,
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
