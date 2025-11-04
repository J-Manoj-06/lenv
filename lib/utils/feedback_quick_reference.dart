/// ⚡ FEEDBACK SYSTEM - QUICK REFERENCE
/// See: feedback_handler.dart for full documentation
/// See: FEEDBACK_SYSTEM_README.md for complete guide

// Import in your screen:
// import '../utils/feedback_handler.dart';

// ============================================================================
// COMMON USAGE PATTERNS
// ============================================================================

// Success message (auto-dismiss 3s)
// showSuccessSnackbar(context, 'Login successful!', role: 'student');

// Error message (auto-dismiss 3s)
// showErrorSnackbar(context, 'Invalid email', role: 'teacher');

// Convert Firebase errors to friendly text:
// showErrorSnackbar(context, getFriendlyErrorMessage(e), role: 'student');

// Error dialog with retry:
// showErrorDialog(
//   context,
//   'Connection failed',
//   role: 'teacher',
//   showRetry: true,
//   onRetry: () => _handleLogin(),
// );

// Loading dialog (must close manually):
// showLoadingDialog(context, message: 'Uploading...', role: 'student');
// // ... async work ...
// Navigator.of(context).pop();

// Confirmation dialog:
// final confirmed = await showConfirmationDialog(
//   context,
//   title: 'Delete Account?',
//   message: 'This cannot be undone.',
//   role: 'teacher',
//   isDangerous: true,
// );

// ============================================================================
// ROLE COLORS
// ============================================================================
// student   → #F27F0D (Orange)
// teacher   → #7E57C2 (Violet)
// parent    → #009688 (Teal)
// institute → #1976D2 (Blue)
