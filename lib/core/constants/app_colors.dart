import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryLight = Color(0xFF9D97FF);
  static const Color primaryDark = Color(0xFF4A42E0);

  // Insights/Poll Colors (calm teal/green palette)
  static const Color insightsTeal = Color(0xFF168B8B); // Primary accent
  static const Color insightsTealDark = Color(0xFF0F6B6B); // Action/dark
  static const Color insightsTealLight = Color(0xFF23A9A9); // Light variant

  // Dark theme surfaces
  static const Color surfaceDark = Color(
    0xFF0F1113,
  ); // Deep charcoal background
  static const Color surfaceCard = Color(0xFF121516); // Card surface
  static const Color surfaceElevated = Color(0xFF1A1D1F); // Elevated surface

  // Text colors for dark theme
  static const Color textMuted = Color(0xFF9AA3A3); // Muted text
  static const Color textOnDark = Color(0xFFE5E7E7); // Primary text on dark

  // Accent colors
  static const Color accentSuccess = Color(0xFF23A455); // Subtle success
  static const Color accentDanger = Color(0xFFD9534F); // Delete/alert

  // Borders and dividers
  static const Color borderSubtle = Color(0x0AFFFFFF); // rgba(255,255,255,0.04)
  static const Color borderMedium = Color(0x1AFFFFFF); // rgba(255,255,255,0.1)

  // Role-based Colors
  static const Color instituteColor = Color(0xFF146D7A);
  static const Color teacherColor = Color(0xFF355872); // #355872
  static const Color studentColor = Color(0xFFF97316); // #F97316
  static const Color parentColor = Color(0xFF617089); // #617089

  // Background Colors
  static const Color background = Color(0xFFF5F5F5);
  static const Color cardBackground = Colors.white;
  static const Color darkBackground = Color(0xFF1E1E1E);

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textLight = Colors.white;

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Chart Colors
  static const List<Color> chartColors = [
    Color(0xFF6C63FF),
    Color(0xFF4CAF50),
    Color(0xFFFFC107),
    Color(0xFFE91E63),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
  ];

  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Insights Teal Gradient (subtle)
  static const LinearGradient insightsTealGradient = LinearGradient(
    colors: [insightsTeal, insightsTealDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
