/// 📚 FEEDBACK HANDLER - USAGE EXAMPLES
///
/// This file demonstrates how to use the universal feedback system
/// across different roles and scenarios.

import 'package:flutter/material.dart';
import 'feedback_handler.dart';

/// Example: Login Screen Error Handling
class LoginExamples {
  static void handleLoginError(
    BuildContext context,
    dynamic error,
    String role,
  ) {
    final friendlyMessage = getFriendlyErrorMessage(error);
    showErrorDialog(
      context,
      friendlyMessage,
      role: role,
      title: 'Login Failed',
      showRetry: true,
      onRetry: () {
        // Retry login logic here
      },
    );
  }

  static void handleNetworkError(BuildContext context, String role) {
    showNetworkDialog(context, role: role);
  }

  static void showLoginSuccess(BuildContext context, String role) {
    showSuccessSnackbar(context, 'Welcome back! Login successful.', role: role);
  }
}

/// Example: Test Submission
class TestSubmissionExamples {
  static void showSubmittingLoading(BuildContext context, String role) {
    showLoadingDialog(
      context,
      message: 'Submitting your answers...',
      role: role,
    );
  }

  static void showSubmissionSuccess(BuildContext context, String role) {
    // Close loading dialog
    Navigator.of(context).pop();

    // Show success dialog
    showSuccessDialog(
      context,
      'Your test has been submitted successfully!',
      role: role,
      title: 'Test Submitted',
    );
  }

  static void showSubmissionError(
    BuildContext context,
    String role,
    dynamic error,
  ) {
    // Close loading dialog
    Navigator.of(context).pop();

    // Show error with retry
    showErrorDialog(
      context,
      getFriendlyErrorMessage(error),
      role: role,
      title: 'Submission Failed',
      showRetry: true,
      onRetry: () {
        // Retry submission logic
      },
    );
  }
}

/// Example: Reward Redemption
class RewardExamples {
  static Future<bool> confirmRedemption(
    BuildContext context,
    String rewardName,
    int pointsCost,
    String role,
  ) async {
    return await showConfirmationDialog(
      context,
      title: 'Redeem Reward?',
      message:
          'Are you sure you want to redeem "$rewardName" for $pointsCost points?',
      role: role,
      confirmText: 'Redeem',
      cancelText: 'Cancel',
    );
  }

  static void showRedemptionSuccess(BuildContext context, String role) {
    showSuccessDialog(
      context,
      'Reward redeemed successfully! Check your rewards section.',
      role: role,
      title: 'Success!',
    );
  }

  static void showInsufficientPoints(BuildContext context, String role) {
    showWarningSnackbar(
      context,
      'You don\'t have enough points for this reward.',
      role: role,
    );
  }
}

/// Example: File Upload
class FileUploadExamples {
  static void showUploadProgress(BuildContext context, String role) {
    showLoadingDialog(context, message: 'Uploading file...', role: role);
  }

  static void showUploadSuccess(BuildContext context, String role) {
    Navigator.of(context).pop(); // Close loading
    showSuccessSnackbar(context, 'File uploaded successfully!', role: role);
  }

  static void showUploadError(BuildContext context, String role) {
    Navigator.of(context).pop(); // Close loading
    showErrorDialog(
      context,
      'Failed to upload file. Please check your connection and try again.',
      role: role,
      title: 'Upload Failed',
      showRetry: true,
    );
  }
}

/// Example: Data Fetching
class DataFetchExamples {
  static void showNoDataFound(BuildContext context, String role) {
    showInfoSnackbar(context, 'No records found.', role: role);
  }

  static void showFetchError(BuildContext context, String role, dynamic error) {
    showErrorSnackbar(context, getFriendlyErrorMessage(error), role: role);
  }
}

/// Example: Network Status
class NetworkStatusExamples {
  static void showOfflineBanner(BuildContext context, String role) {
    showNetworkStatusBanner(context, isOnline: false, role: role);
  }

  static void showOnlineBanner(BuildContext context, String role) {
    showNetworkStatusBanner(context, isOnline: true, role: role);
  }
}

/// Example: Delete Confirmation (Dangerous action)
class DeleteExamples {
  static Future<bool> confirmDelete(
    BuildContext context,
    String itemName,
    String role,
  ) async {
    return await showConfirmationDialog(
      context,
      title: 'Delete $itemName?',
      message:
          'This action cannot be undone. Are you sure you want to delete this $itemName?',
      role: role,
      confirmText: 'Delete',
      cancelText: 'Cancel',
      isDangerous: true,
    );
  }

  static void showDeleteSuccess(BuildContext context, String role) {
    showSuccessSnackbar(context, 'Deleted successfully!', role: role);
  }
}

/// Example: Form Validation
class FormValidationExamples {
  static void showEmptyFieldsWarning(BuildContext context, String role) {
    showWarningSnackbar(
      context,
      'Please fill in all required fields.',
      role: role,
    );
  }

  static void showInvalidEmailWarning(BuildContext context, String role) {
    showWarningSnackbar(
      context,
      'Please enter a valid email address.',
      role: role,
    );
  }

  static void showWeakPasswordWarning(BuildContext context, String role) {
    showWarningSnackbar(
      context,
      'Password must be at least 6 characters long.',
      role: role,
    );
  }
}

/// Example: Complete Login Flow with Role
class CompleteLoginFlowExample extends StatefulWidget {
  final String role;

  const CompleteLoginFlowExample({Key? key, required this.role})
    : super(key: key);

  @override
  State<CompleteLoginFlowExample> createState() =>
      _CompleteLoginFlowExampleState();
}

class _CompleteLoginFlowExampleState extends State<CompleteLoginFlowExample> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _handleLogin() async {
    // Validate
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      showWarningSnackbar(
        context,
        'Please enter email and password.',
        role: widget.role,
      );
      return;
    }

    // Show loading
    showLoadingDialog(context, message: 'Signing in...', role: widget.role);

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 2));

      // Simulate random success/failure
      final success = DateTime.now().second % 2 == 0;

      // Close loading
      if (mounted) Navigator.of(context).pop();

      if (success) {
        // Success
        showSuccessSnackbar(context, 'Welcome back!', role: widget.role);
      } else {
        // Error
        showErrorDialog(
          context,
          'Incorrect password. Please try again.',
          role: widget.role,
          title: 'Login Failed',
          showRetry: true,
          onRetry: _handleLogin,
        );
      }
    } catch (e) {
      // Close loading
      if (mounted) Navigator.of(context).pop();

      // Show error
      showErrorDialog(
        context,
        getFriendlyErrorMessage(e),
        role: widget.role,
        title: 'Error',
        showRetry: true,
        onRetry: _handleLogin,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = getRoleColor(widget.role);

    return Scaffold(
      appBar: AppBar(
        title: Text('Login - ${widget.role.toUpperCase()}'),
        backgroundColor: color,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Login',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Demo buttons
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => showSuccessSnackbar(
                    context,
                    'This is a success message!',
                    role: widget.role,
                  ),
                  child: const Text('Success Snackbar'),
                ),
                ElevatedButton(
                  onPressed: () => showErrorSnackbar(
                    context,
                    'This is an error message!',
                    role: widget.role,
                  ),
                  child: const Text('Error Snackbar'),
                ),
                ElevatedButton(
                  onPressed: () => showWarningSnackbar(
                    context,
                    'This is a warning!',
                    role: widget.role,
                  ),
                  child: const Text('Warning Snackbar'),
                ),
                ElevatedButton(
                  onPressed: () => showInfoSnackbar(
                    context,
                    'This is info!',
                    role: widget.role,
                  ),
                  child: const Text('Info Snackbar'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      showNetworkDialog(context, role: widget.role),
                  child: const Text('Network Dialog'),
                ),
                ElevatedButton(
                  onPressed: () => showTopBanner(
                    context,
                    'This is a top banner!',
                    role: widget.role,
                  ),
                  child: const Text('Top Banner'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
