import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';

/// Reusable onboarding page widget
class OnboardingPage extends StatelessWidget {
  final String title;
  final String? description;
  final List<String>? bulletPoints;
  final IconData? icon;
  final LinearGradient? backgroundGradient;

  const OnboardingPage({
    Key? key,
    required this.title,
    this.description,
    this.bulletPoints,
    this.icon,
    this.backgroundGradient,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: backgroundGradient,
        color: isDark ? AppColors.darkBackground : AppColors.background,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top spacing
              const Spacer(flex: 2),

              // Icon/Illustration (if provided)
              if (icon != null)
                _buildIcon(icon!, isDark)
              else
                const SizedBox(height: 120),

              const SizedBox(height: 40),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textLight : AppColors.textDark,
                    ) ??
                    const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              // Description or Bullet Points
              if (bulletPoints != null)
                _buildBulletPoints(bulletPoints!, isDark)
              else if (description != null)
                _buildDescription(description!, isDark),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// Build icon widget with gradient background
  Widget _buildIcon(IconData icon, bool isDark) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.2),
            AppColors.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
      ),
      child: Icon(icon, size: 60, color: AppColors.primary),
    );
  }

  /// Build description text
  Widget _buildDescription(String description, bool isDark) {
    return Text(
      description,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 16,
        color: isDark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondaryLight,
        height: 1.6,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  /// Build bullet points list
  Widget _buildBulletPoints(List<String> points, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        points.length,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  points[index],
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? AppColors.textLight : AppColors.textDark,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
