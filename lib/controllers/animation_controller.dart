import 'package:flutter/animation.dart';

/// Shared animation timing and curve configuration for dashboard UI effects.
class DashboardAnimationConfig {
  static const Duration fast = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 1600);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve smooth = Curves.easeInOutCubic;
  static const Curve gentle = Curves.easeOutQuart;

  static const Duration cardAutoSlide = Duration(seconds: 4);
  static const Duration pageTransition = Duration(milliseconds: 340);
}
