/// ⚡ UNIVERSAL FEEDBACK AND ERROR HANDLING SYSTEM (Multi-Role Themed)
///
/// A complete, reusable Flutter error and feedback popup system that adapts
/// visually based on the user's role (Student, Teacher, Parent, Institute).
///
/// 🎨 ROLE-BASED THEMES:
/// - Student → Orange / Amber (#f27f0d)
/// - Teacher → Violet / Purple (#7e57c2)
/// - Parent → Green (#14a670)
/// - Institute → Blue (#1976d2)
library;

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

/// Get theme color based on user role
Color getRoleColor(String role) {
  switch (role.toLowerCase()) {
    case 'student':
      return const Color(0xFFF27F0D);
    case 'teacher':
      return const Color(0xFF7E57C2);
    case 'parent':
      return const Color(0xFF14A670);
    case 'institute':
      return const Color(0xFF1976D2);
    default:
      return const Color(0xFF355872); // Fallback color
  }
}

/// Get light version of role color for backgrounds
Color getRoleLightColor(String role) {
  switch (role.toLowerCase()) {
    case 'student':
      return const Color(0xFFFFF5EB);
    case 'teacher':
      return const Color(0xFFF3E5F5);
    case 'parent':
      return const Color(0xFFF0F5FF);
    case 'institute':
      return const Color(0xFFE3F2FD);
    default:
      return const Color(0xFFF5F5F5);
  }
}

/// Get gradient colors for role
List<Color> getRoleGradient(String role) {
  switch (role.toLowerCase()) {
    case 'student':
      return [const Color(0xFFFFA726), const Color(0xFFF27F0D)];
    case 'teacher':
      return [const Color(0xFFA78BFA), const Color(0xFF7B61FF)];
    case 'parent':
      return [const Color(0xFFD4F4E8), const Color(0xFF14A670)];
    case 'institute':
      return [const Color(0xFF42A5F5), const Color(0xFF1976D2)];
    default:
      return [const Color(0xFF355872), const Color(0xFF4F46E5)];
  }
}

/// 1️⃣ **SUCCESS SNACKBAR** - For positive feedback
void showSuccessSnackbar(
  BuildContext context,
  String message, {
  String role = 'student',
  Duration duration = const Duration(seconds: 3),
}) {
  final color = getRoleColor(role);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: duration,
      elevation: 6,
    ),
  );

  // Optional haptic feedback
  HapticFeedback.lightImpact();
}

/// 2️⃣ **ERROR SNACKBAR** - For non-critical issues
void showErrorSnackbar(
  BuildContext context,
  String message, {
  String role = 'student',
  Duration duration = const Duration(seconds: 3),
}) {
  final color = getRoleColor(role);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, color: Colors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.red.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3), width: 2),
      ),
      margin: const EdgeInsets.all(16),
      duration: duration,
      elevation: 6,
    ),
  );

  // Optional haptic feedback for error
  HapticFeedback.mediumImpact();
}

/// 3️⃣ **WARNING SNACKBAR** - For cautionary messages
void showWarningSnackbar(
  BuildContext context,
  String message, {
  String role = 'student',
  Duration duration = const Duration(seconds: 3),
}) {
  final color = getRoleColor(role);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3), width: 2),
      ),
      margin: const EdgeInsets.all(16),
      duration: duration,
      elevation: 6,
    ),
  );

  // Optional haptic feedback
  HapticFeedback.lightImpact();
}

/// 4️⃣ **INFO SNACKBAR** - For informational messages
void showInfoSnackbar(
  BuildContext context,
  String message, {
  String role = 'student',
  Duration duration = const Duration(seconds: 3),
}) {
  final color = getRoleColor(role);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.info_outline, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: duration,
      elevation: 6,
    ),
  );
}

/// 5️⃣ **SUCCESS DIALOG** - Beautiful modal with Lottie animation
Future<void> showSuccessDialog(
  BuildContext context,
  String message, {
  String role = 'student',
  String? title,
  VoidCallback? onDismiss,
}) async {
  final result = await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => _SuccessDialog(
      message: message,
      title: title ?? 'Success!',
      role: role,
    ),
  );

  if (result == true && onDismiss != null) {
    onDismiss();
  }
}

/// 6️⃣ **ERROR DIALOG** - For serious issues requiring user attention
Future<bool> showErrorDialog(
  BuildContext context,
  String message, {
  String role = 'student',
  String? title,
  bool showRetry = false,
  VoidCallback? onRetry,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ErrorDialog(
      message: message,
      title: title ?? 'Error',
      role: role,
      showRetry: showRetry,
      onRetry: onRetry,
    ),
  );

  return result ?? false;
}

/// 7️⃣ **NETWORK ERROR DIALOG** - Specific for network issues
Future<void> showNetworkDialog(
  BuildContext context, {
  String role = 'student',
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NetworkErrorDialog(role: role),
  );
}

/// 8️⃣ **CONFIRMATION DIALOG** - For actions requiring confirmation
Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String role = 'student',
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  bool isDangerous = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmationDialog(
      title: title,
      message: message,
      role: role,
      confirmText: confirmText,
      cancelText: cancelText,
      isDangerous: isDangerous,
    ),
  );

  return result ?? false;
}

/// 9️⃣ **LOADING DIALOG** - For async operations
void showLoadingDialog(
  BuildContext context, {
  String message = 'Please wait...',
  String role = 'student',
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _LoadingDialog(message: message, role: role),
  );
}

/// 🔟 **TOP BANNER** - Sliding banner from top
void showTopBanner(
  BuildContext context,
  String message, {
  String role = 'student',
  BannerType type = BannerType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => _TopBanner(
      message: message,
      role: role,
      type: type,
      onDismiss: () => overlayEntry.remove(),
    ),
  );

  overlay.insert(overlayEntry);

  // Auto-dismiss after duration
  Future.delayed(duration + const Duration(milliseconds: 500), () {
    if (overlayEntry.mounted) {
      overlayEntry.remove();
    }
  });
}

/// 1️⃣1️⃣ **NETWORK STATUS BANNER** - Auto-showing network indicator
void showNetworkStatusBanner(
  BuildContext context, {
  required bool isOnline,
  String role = 'student',
}) {
  showTopBanner(
    context,
    isOnline ? 'Back online!' : 'You\'re offline — reconnecting…',
    role: role,
    type: isOnline ? BannerType.success : BannerType.error,
  );
}

/// Banner type enum
enum BannerType { success, error, warning, info }

/// Convert Firebase error to user-friendly message
String getFriendlyErrorMessage(dynamic error) {
  final errorString = error.toString().toLowerCase();

  if (errorString.contains('network') || errorString.contains('connection')) {
    return 'Check your internet connection and try again.';
  } else if (errorString.contains('user-not-found')) {
    return 'No account found with this email.';
  } else if (errorString.contains('wrong-password')) {
    return 'Incorrect password. Please try again.';
  } else if (errorString.contains('invalid-credential') ||
      errorString.contains('invalid-login-credentials') ||
      errorString.contains('invalid credentials')) {
    return 'Invalid email or password. Please try again.';
  } else if (errorString.contains('email-already-in-use')) {
    return 'This email is already registered.';
  } else if (errorString.contains('weak-password')) {
    return 'Password is too weak. Use at least 6 characters.';
  } else if (errorString.contains('invalid-email')) {
    return 'Please enter a valid email address.';
  } else if (errorString.contains('too-many-requests')) {
    return 'Too many attempts. Please try again later.';
  } else if (errorString.contains('user-disabled')) {
    return 'This account has been disabled. Please contact support.';
  } else if (errorString.contains('operation-not-allowed')) {
    return 'This sign-in method is not enabled. Please contact support.';
  } else if (errorString.contains('requires-recent-login')) {
    return 'Please sign in again to continue.';
  } else if (errorString.contains('account-exists-with-different-credential')) {
    return 'An account already exists with a different sign-in method.';
  } else if (errorString.contains('timeout')) {
    return 'Request timed out. Please try again.';
  } else if (errorString.contains('permission-denied')) {
    return 'You don\'t have permission to perform this action.';
  } else if (errorString.contains('not-found')) {
    return 'Requested data not found.';
  }

  return 'Something went wrong. Please try again.';
}

// ============================================================================
// DIALOG WIDGETS
// ============================================================================

/// Success Dialog Widget
class _SuccessDialog extends StatefulWidget {
  final String message;
  final String title;
  final String role;

  const _SuccessDialog({
    required this.message,
    required this.title,
    required this.role,
  });

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();

    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = getRoleGradient(widget.role);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lottie Animation
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Lottie.asset(
                    'assets/animations/success.json',
                    repeat: false,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to icon if Lottie fails
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          size: 80,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                Text(
                  widget.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Message
                Text(
                  widget.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Error Dialog Widget
class _ErrorDialog extends StatefulWidget {
  final String message;
  final String title;
  final String role;
  final bool showRetry;
  final VoidCallback? onRetry;

  const _ErrorDialog({
    required this.message,
    required this.title,
    required this.role,
    this.showRetry = false,
    this.onRetry,
  });

  @override
  State<_ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<_ErrorDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeDialog(bool retry) {
    _controller.reverse().then((_) {
      if (mounted) Navigator.of(context).pop(retry);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = getRoleColor(widget.role);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Error Icon with Lottie
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Lottie.asset(
                    'assets/animations/error.json',
                    repeat: false,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.error_outline,
                          size: 60,
                          color: Colors.red.shade600,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                Text(
                  widget.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Message
                Text(
                  widget.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  children: [
                    if (widget.showRetry) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _closeDialog(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: getRoleGradient(widget.role),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              _closeDialog(true);
                              widget.onRetry?.call();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: getRoleGradient(widget.role),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton(
                            onPressed: () => _closeDialog(false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Network Error Dialog Widget
class _NetworkErrorDialog extends StatefulWidget {
  final String role;

  const _NetworkErrorDialog({required this.role});

  @override
  State<_NetworkErrorDialog> createState() => _NetworkErrorDialogState();
}

class _NetworkErrorDialogState extends State<_NetworkErrorDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = getRoleColor(widget.role);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Network animation
              SizedBox(
                width: 100,
                height: 100,
                child: Lottie.asset(
                  'assets/animations/network.json',
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.wifi_off_rounded,
                      size: 80,
                      color: Colors.grey,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No Internet Connection',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Please check your internet connection and try again.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
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

/// Confirmation Dialog Widget
class _ConfirmationDialog extends StatefulWidget {
  final String title;
  final String message;
  final String role;
  final String confirmText;
  final String cancelText;
  final bool isDangerous;

  const _ConfirmationDialog({
    required this.title,
    required this.message,
    required this.role,
    required this.confirmText,
    required this.cancelText,
    required this.isDangerous,
  });

  @override
  State<_ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<_ConfirmationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeDialog(bool confirmed) {
    _controller.reverse().then((_) {
      if (mounted) Navigator.of(context).pop(confirmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = widget.isDangerous
        ? Colors.red.shade600
        : getRoleColor(widget.role);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.isDangerous
                      ? Icons.warning_amber_rounded
                      : Icons.help_outline,
                  size: 48,
                  color: color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.message,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _closeDialog(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withOpacity(0.3)
                              : Colors.grey.shade300,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.cancelText,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _closeDialog(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.confirmText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading Dialog Widget
class _LoadingDialog extends StatelessWidget {
  final String message;
  final String role;

  const _LoadingDialog({required this.message, required this.role});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = getRoleColor(role);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Top Banner Widget
class _TopBanner extends StatefulWidget {
  final String message;
  final String role;
  final BannerType type;
  final VoidCallback onDismiss;

  const _TopBanner({
    required this.message,
    required this.role,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  Timer? _autoTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    // Auto-dismiss
    _autoTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isDismissing) {
        _handleDismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    _autoTimer?.cancel();
    _controller.reverse().then((_) => widget.onDismiss());
  }

  Color _getBackgroundColor() {
    switch (widget.type) {
      case BannerType.success:
        return Colors.green.shade600;
      case BannerType.error:
        return Colors.red.shade600;
      case BannerType.warning:
        return Colors.orange.shade600;
      case BannerType.info:
        return getRoleColor(widget.role);
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case BannerType.success:
        return Icons.check_circle;
      case BannerType.error:
        return Icons.wifi_off_rounded;
      case BannerType.warning:
        return Icons.warning_amber_rounded;
      case BannerType.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null &&
                      details.primaryDelta! > 6) {
                    _handleDismiss();
                  }
                },
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null &&
                      details.primaryVelocity! > 250) {
                    _handleDismiss();
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getBackgroundColor(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(_getIcon(), color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _handleDismiss,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
