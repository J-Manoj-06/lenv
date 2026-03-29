import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/school_storage_service.dart';
import '../../constants/app_colors.dart';

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
    // Ensure storage is initialized
    await schoolStorageService.initialize();

    // Determine next route based on school selection
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final isSchoolSelected = schoolStorageService.isSchoolSelected;

    String nextRoute;
    if (!isSchoolSelected) {
      // Requirement-driven flow: no school selected means onboarding.
      nextRoute = '/onboarding';
    } else {
      // Returning user with selected school.
      nextRoute = '/role-selection';
    }

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
                  colors: isDark
                      ? [
                          AppColors.primaryDark.withValues(alpha: 0.9),
                          AppColors.primary.withValues(alpha: 0.7),
                        ]
                      : [AppColors.primaryLight, AppColors.primary],
                ),
          color: isDark ? AppColors.darkBackground : AppColors.background,
        ),
        child: SafeArea(
          child: FadeTransition(
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
                            const SizedBox(height: 24),
                            Text(
                              isCustomSplash
                                  ? (schoolName ?? 'School')
                                  : 'Lenv',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontSize: isCustomSplash ? 24 : 28,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.textLight
                                        : AppColors.textDark,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Powered by Lenv',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Educational Ecosystem',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color:
                          (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight)
                              .withValues(alpha: 0.9),
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build logo widget with balanced dimensions so text remains dominant.
  Widget _buildLogo(bool isCustom, String? schoolLogo) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isCustom ? 0.16 : 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
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
                    size: 56,
                    color: AppColors.primary,
                  );
                },
              ),
            )
          : Icon(Icons.school_rounded, size: 56, color: AppColors.primary),
    );
  }
}
