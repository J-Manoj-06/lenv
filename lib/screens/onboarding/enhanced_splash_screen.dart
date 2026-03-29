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
                  colors: [
                    AppColors.primary.withValues(alpha: 0.1),
                    AppColors.primary.withValues(alpha: 0.05),
                  ],
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Logo/Icon
                  _buildLogo(isCustomSplash, schoolLogo),

                  const SizedBox(height: 40),

                  // Title
                  if (isCustomSplash)
                    _buildCustomSplashTitle(schoolName)
                  else
                    _buildDefaultSplashTitle(),

                  const Spacer(),

                  // Powered by text
                  _buildPoweredByText(),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build logo widget (circular with school or default icon)
  Widget _buildLogo(bool isCustom, String? schoolLogo) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(70),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: isCustom && schoolLogo != null && schoolLogo.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(70),
              child: Image.network(
                schoolLogo,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.school_rounded,
                    size: 80,
                    color: AppColors.primary,
                  );
                },
              ),
            )
          : Icon(Icons.school_rounded, size: 80, color: AppColors.primary),
    );
  }

  /// Build default Lenv splash title
  Widget _buildDefaultSplashTitle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          'Lenv',
          style: TextStyle(
            fontSize: 60,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.textLight : Colors.white,
            letterSpacing: 2,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Learning Ecosystem',
          style: TextStyle(
            fontSize: 18,
            color: isDark ? AppColors.textLight : Colors.white,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Build custom school splash title
  Widget _buildCustomSplashTitle(String? schoolName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          schoolName ?? 'School',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.textDark : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Powered by Lenv',
          style: TextStyle(
            fontSize: 14,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  /// Build "Powered by Lenv" text at bottom
  Widget _buildPoweredByText() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final schoolId = schoolStorageService.schoolId;
    final isCustom = schoolId != null && schoolId.isNotEmpty;

    return Text(
      isCustom ? 'Educational Ecosystem' : 'Start Your Journey',
      style: TextStyle(
        fontSize: 14,
        color: isDark
            ? AppColors.textSecondaryDark
            : (isCustom
                  ? AppColors.textSecondaryLight
                  : Colors.white.withValues(alpha: 0.9)),
        fontWeight: FontWeight.w300,
        letterSpacing: 0.5,
      ),
    );
  }
}
