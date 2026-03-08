/// 🎨 LENV SNACKBAR SYSTEM
///
/// A modern, animated, floating snackbar widget for the Lenv education platform.
/// Inspired by Duolingo / Notion design — clean, readable, and role-aware.
///
/// Usage:
///   showLenvSnackBar(context, 'Your message here', Icons.wifi_off, Colors.orange);
///
/// Convenience shortcuts:
///   showLenvLoginError(context, message)  ← auto-detects error type + icon + color
///   showLenvSuccess(context, message)
///   showLenvWarning(context, message)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CORE FUNCTION
// ─────────────────────────────────────────────────────────────────────────────

/// Shows a modern floating animated snackbar.
///
/// [icon]    – Leading icon (e.g. Icons.wifi_off)
/// [color]   – Accent/background color
/// [message] – Body text
/// [duration]– How long the snackbar is visible (default 3 s)
void showLenvSnackBar(
  BuildContext context,
  String message,
  IconData icon,
  Color color, {
  Duration duration = const Duration(seconds: 3),
}) {
  // Dismiss any existing snackbar first so they never stack
  ScaffoldMessenger.of(context).hideCurrentSnackBar();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: _LenvSnackBarContent(icon: icon, message: message, color: color),
      // Make the SnackBar itself fully transparent — our content widget
      // carries all styling (color, border-radius, shadow).
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: EdgeInsets.zero,
      duration: duration,
      dismissDirection: DismissDirection.horizontal,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT WIDGET (animated)
// ─────────────────────────────────────────────────────────────────────────────

class _LenvSnackBarContent extends StatefulWidget {
  const _LenvSnackBarContent({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  State<_LenvSnackBarContent> createState() => _LenvSnackBarContentState();
}

class _LenvSnackBarContentState extends State<_LenvSnackBarContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Derive a readable text color and a tinted background
    final bg = isDark
        ? Color.lerp(const Color(0xFF1C1C1E), widget.color, 0.18)!
        : Color.lerp(Colors.white, widget.color, 0.08)!;
    final iconBg = widget.color.withOpacity(0.15);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1D21);
    final subtleStroke = widget.color.withOpacity(isDark ? 0.35 : 0.25);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: subtleStroke, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Icon pill ──────────────────────────────────────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: widget.color, size: 22),
              ),
              const SizedBox(width: 12),

              // ── Message ────────────────────────────────────────────────────
              Expanded(
                child: Text(
                  widget.message,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    letterSpacing: 0.1,
                  ),
                ),
              ),

              // ── Accent strip on the right ──────────────────────────────────
              const SizedBox(width: 8),
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN ERROR — auto-picks icon + color from message content
// ─────────────────────────────────────────────────────────────────────────────

/// Automatically resolves the right icon and color for login error messages,
/// then shows the Lenv snackbar.
///
///   showLenvLoginError(context, 'Incorrect password. Please try again.');
void showLenvLoginError(BuildContext context, String message) {
  final resolved = _resolveLoginError(message);
  HapticFeedback.mediumImpact();
  showLenvSnackBar(context, message, resolved.icon, resolved.color);
}

/// Internal: maps an error message string → icon + color pair.
_LoginError _resolveLoginError(String message) {
  final m = message.toLowerCase();

  if (m.contains('internet') ||
      m.contains('network') ||
      m.contains('connection') ||
      m.contains('offline')) {
    return _LoginError(Icons.wifi_off_rounded, const Color(0xFFF57C00));
  }

  if (m.contains('wrong-password') ||
      m.contains('incorrect password') ||
      m.contains('invalid') ||
      m.contains('invalid-credential') ||
      m.contains('password') && !m.contains('reset')) {
    return _LoginError(Icons.lock_outline_rounded, const Color(0xFFD32F2F));
  }

  if (m.contains('role') ||
      m.contains('access denied') ||
      m.contains('teacher-only') ||
      m.contains('parent-only') ||
      m.contains('student-only') ||
      m.contains('institute-only') ||
      m.contains('school does not match') ||
      m.contains('account type') ||
      m.contains('not linked')) {
    return _LoginError(Icons.person_off_outlined, const Color(0xFF7B1FA2));
  }

  if (m.contains('user-not-found') ||
      m.contains('no account') ||
      m.contains('user not found') ||
      m.contains('check your email')) {
    return _LoginError(Icons.person_search_rounded, const Color(0xFF1565C0));
  }

  if (m.contains('too-many-requests') || m.contains('too many')) {
    return _LoginError(Icons.timer_off_outlined, const Color(0xFFBF360C));
  }

  if (m.contains('disabled') || m.contains('banned')) {
    return _LoginError(Icons.block_rounded, const Color(0xFF4E342E));
  }

  if (m.contains('school') || m.contains('select')) {
    return _LoginError(Icons.school_outlined, const Color(0xFF0277BD));
  }

  // Default → server / generic error
  return _LoginError(Icons.error_outline_rounded, const Color(0xFFBF360C));
}

class _LoginError {
  const _LoginError(this.icon, this.color);
  final IconData icon;
  final Color color;
}

// ─────────────────────────────────────────────────────────────────────────────
// CONVENIENCE SHORTCUTS
// ─────────────────────────────────────────────────────────────────────────────

/// Green success snackbar.
void showLenvSuccess(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  HapticFeedback.lightImpact();
  showLenvSnackBar(
    context,
    message,
    Icons.check_circle_outline_rounded,
    const Color(0xFF2E7D32),
    duration: duration,
  );
}

/// Amber warning snackbar.
void showLenvWarning(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  HapticFeedback.selectionClick();
  showLenvSnackBar(
    context,
    message,
    Icons.warning_amber_rounded,
    const Color(0xFFF9A825),
    duration: duration,
  );
}

/// Blue info snackbar.
void showLenvInfo(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  showLenvSnackBar(
    context,
    message,
    Icons.info_outline_rounded,
    const Color(0xFF0277BD),
    duration: duration,
  );
}
