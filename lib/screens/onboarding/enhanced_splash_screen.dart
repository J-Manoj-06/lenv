import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/school_storage_service.dart';
import '../../constants/app_colors.dart';
import '../../utils/session_manager.dart';
import '../../widgets/student_main_navigation.dart';

/// Enhanced splash screen that handles both first-time and returning users
class EnhancedSplashScreen extends StatefulWidget {
  const EnhancedSplashScreen({super.key});

  @override
  State<EnhancedSplashScreen> createState() => _EnhancedSplashScreenState();
}

class _EnhancedSplashScreenState extends State<EnhancedSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Fade animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // Slide animation
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();

    // Resolve and navigate after a delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveAndNavigate();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Resolve navigation based on stored school data
  Future<void> _resolveAndNavigate() async {
    debugPrint('🚀 [Splash] _resolveAndNavigate start');

    // Ensure storage is initialized
    await schoolStorageService.initialize();
    debugPrint(
      '🏫 [Splash] schoolStorage -> schoolId=${schoolStorageService.schoolId}, schoolName=${schoolStorageService.schoolName}',
    );

    // Determine next route based on school selection
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final session = await SessionManager.getLoginSession();
    final hasActiveSession = session['isLoggedIn'] == true;
    debugPrint(
      '🧠 [Splash] session -> hasActiveSession=$hasActiveSession, userId=${session['userId']}, userRole=${session['userRole']}',
    );

    if (hasActiveSession) {
      final resumeRoute = await SessionManager.getInitialScreen();
      debugPrint('➡️ [Splash] resumeRoute=$resumeRoute');
      if (mounted) {
        if (resumeRoute == '/student-dashboard') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const StudentMainNavigation(
                initialIndex: 0,
                shouldCheckUsagePermissionOnEntry: true,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacementNamed(resumeRoute);
        }
      }
      return;
    }

    final isSchoolSelected = schoolStorageService.isSchoolSelected;

    String nextRoute;
    if (!isSchoolSelected) {
      // Requirement-driven flow: no school selected means onboarding.
      nextRoute = '/onboarding';
    } else {
      // Returning user with selected school.
      nextRoute = '/role-selection';
    }

    debugPrint(
      '➡️ [Splash] fallback route=$nextRoute (isSchoolSelected=$isSchoolSelected)',
    );

    if (mounted) {
      Navigator.of(context).pushReplacementNamed(nextRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final schoolId = schoolStorageService.schoolId;
    final schoolName = schoolStorageService.schoolName;
    final schoolLogo = schoolStorageService.schoolLogo;

    // Determine if showing custom school splash or default Lenv splash
    final isCustomSplash = schoolId != null && schoolId.isNotEmpty;

    final defaultGradient = isDark
        ? const [Color(0xFF2A1806), Color(0xFF1D1105), Color(0xFF140C04)]
        : const [Color(0xFFFFC774), Color(0xFFF29A22), Color(0xFFD97B08)];

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isCustomSplash
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF1F1A14), Color(0xFF14110E)]
                      : const [Color(0xFFFFF8EF), Color(0xFFFFF2E2)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: defaultGradient,
                ),
          color: isDark ? AppColors.darkBackground : AppColors.background,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              if (!isCustomSplash) ...[
                Positioned(
                  top: -120,
                  right: -70,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.05 : 0.14,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 110,
                  left: -80,
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.20 : 0.06,
                      ),
                    ),
                  ),
                ),
              ],
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ScaleTransition(
                                  scale: _scaleAnimation,
                                  child: _buildLogo(isCustomSplash, schoolLogo),
                                ),
                                SizedBox(height: isCustomSplash ? 24 : 26),
                                Text(
                                  isCustomSplash
                                      ? (schoolName ?? 'School')
                                      : 'LenV',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontSize: isCustomSplash ? 24 : 30,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: isCustomSplash ? 0 : 0.2,
                                        color: isDark
                                            ? AppColors.textLight
                                            : AppColors.textDark,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Powered by Lenv',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontSize: isCustomSplash ? 15 : 17,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppColors.textSecondaryDark
                                            : Colors.white.withValues(
                                                alpha: 0.86,
                                              ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCustomSplash ? 0 : 16,
                          vertical: isCustomSplash ? 0 : 8,
                        ),
                        decoration: isCustomSplash
                            ? null
                            : BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: Colors.white.withValues(
                                  alpha: isDark ? 0.06 : 0.16,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: isDark ? 0.08 : 0.26,
                                  ),
                                ),
                              ),
                        child: Text(
                          'Educational Ecosystem',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 14,
                                color: isCustomSplash
                                    ? (isDark
                                              ? AppColors.textSecondaryDark
                                              : AppColors.textSecondaryLight)
                                          .withValues(alpha: 0.9)
                                    : Colors.white.withValues(alpha: 0.9),
                                fontWeight: isCustomSplash
                                    ? FontWeight.w400
                                    : FontWeight.w500,
                                letterSpacing: isCustomSplash ? 0.3 : 0.4,
                              ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build logo widget with balanced dimensions so text remains dominant.
  Widget _buildLogo(bool isCustom, String? schoolLogo) {
    return Container(
      width: isCustom ? 112 : 124,
      height: isCustom ? 112 : 124,
      decoration: BoxDecoration(
        gradient: isCustom
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFCF7), Color(0xFFF8F4EE)],
              ),
        color: isCustom ? Colors.white.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(isCustom ? 24 : 28),
        border: Border.all(
          color: Colors.white.withValues(alpha: isCustom ? 0.20 : 0.75),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isCustom ? 0.10 : 0.15),
            blurRadius: isCustom ? 14 : 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: isCustom && schoolLogo != null && schoolLogo.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(
                schoolLogo,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.school_rounded,
                    size: isCustom ? 56 : 60,
                    color: AppColors.primary,
                  );
                },
              ),
            )
          : Icon(
              Icons.school_rounded,
              size: isCustom ? 56 : 60,
              color: AppColors.primary,
            ),
    );
  }
}
