import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/test_model.dart';
import '../../providers/auth_provider.dart';
import 'take_test_screen.dart';

class TestRulesScreen extends StatelessWidget {
  final TestModel test;

  const TestRulesScreen({super.key, required this.test});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
        backgroundColor: isDark ? Colors.black : Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Back Button
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.centerLeft,
                      child: Icon(
                            Icons.arrow_back,
                            size: 28,
                            color: Theme.of(context).iconTheme.color,
                          ),
                    ),
                  ),
                  const Spacer(),
                  // Timer Display
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 20,
                        color: Theme.of(context).iconTheme.color?.withOpacity(0.75),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${test.duration} Mins',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    // Headline and Body Text
                      Text(
                        'Before You Start the Test',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                      ),
                    const SizedBox(height: 12),
                      Text(
                        'Please read the following instructions carefully before beginning your test.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).textTheme.bodySmall?.color,
                              fontSize: 16,
                              height: 1.5,
                            ),
                      ),
                    const SizedBox(height: 16),

                      // Centered GIF inside a rounded card to match design and
                      // avoid visible black gap. Increased size for better visibility.
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 300),
                        padding: const EdgeInsets.all(24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            color: isDark ? Colors.black : Theme.of(context).cardColor,
                            alignment: Alignment.center,
                            child: Image.asset(
                              'assets/animations/walking_student.gif',
                              fit: BoxFit.contain,
                              width: 300,
                              height: 220,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: isDark ? Colors.black : Theme.of(context).cardColor,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(24),
                                  child: Icon(
                                    Icons.school,
                                    size: 120,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Instruction Card
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          // Rule 1: No Tab Switching
                          _buildRuleItem(
                            context: context,
                            icon: Icons.tab_unselected,
                            title: 'No Tab Switching',
                            description:
                                'Leaving the app or switching tabs will automatically submit your test.',
                          ),
                          // Rule 2: Stable Connection
                          _buildRuleItem(
                            context: context,
                            icon: Icons.wifi,
                            title: 'Stable Connection',
                            description:
                                'Ensure you have a stable internet connection throughout the test.',
                          ),
                          // Rule 3: Timer Warning
                          _buildRuleItem(
                            context: context,
                            icon: Icons.timer,
                            title: 'Timer Cannot Be Paused',
                            description:
                                'Once you start, the timer cannot be paused or stopped.',
                          ),
                          // Rule 4: Focus Required
                          _buildRuleItem(
                            context: context,
                            icon: Icons.visibility,
                            title: 'Stay Focused',
                            description:
                                'Keep the test window in focus. Any distraction will auto-submit.',
                          ),
                          // Rule 5: Honest Attempt
                          _buildRuleItem(
                            context: context,
                            icon: Icons.verified_user,
                            title: 'Academic Integrity',
                            description:
                                'Complete the test independently without external help.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100), // Space for fixed buttons
                  ],
                ),
              ),
            ),

            // Fixed Action Buttons at Bottom
              Container(
                color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Start Test Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        // Check schedule windows
                        final now = DateTime.now();
                        // Not started yet
                        if (now.isBefore(test.startDate)) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Test not started'),
                              content: Text(
                                'This test will be available starting on ${'${test.startDate.toLocal()}'.split('.')[0]}. Please try again later.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }
                        // Expired
                        if (now.isAfter(test.endDate)) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Test Expired'),
                              content: const Text(
                                'This test has ended and is no longer available. The allocated time has passed.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context); // Close dialog
                                    Navigator.pop(
                                      context,
                                    ); // Go back to tests list
                                  },
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        final auth = Provider.of<AuthProvider>(
                          context,
                          listen: false,
                        );
                        final studentId = auth.currentUser?.uid;
                        if (studentId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please login as student'),
                            ),
                          );
                          return;
                        }

                        // Check if test has expired
                        if (DateTime.now().isAfter(test.endDate)) {
                          await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Test Expired'),
                              content: const Text(
                                'This test has ended and is no longer available. The allocated time has passed.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context); // Close dialog
                                    Navigator.pop(
                                      context,
                                    ); // Go back to test list
                                  },
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        // Check if already submitted (status: completed or submitted)
                        final existing = await FirebaseFirestore.instance
                            .collection('testResults')
                            .where('studentId', isEqualTo: studentId)
                            .where('testId', isEqualTo: test.id)
                            .limit(1)
                            .get();

                        if (existing.docs.isNotEmpty) {
                          final status =
                              existing.docs.first.data()['status'] as String?;
                          final isSubmitted =
                              status == 'completed' || status == 'submitted';

                          // Only show "Already Submitted" if actually completed/submitted
                          if (isSubmitted) {
                            final endPassed = DateTime.now().isAfter(
                              test.endDate,
                            );
                            if (endPassed) {
                              // Navigate to results page
                              final resultId = existing.docs.first.id;
                              if (context.mounted) {
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/student-test-result',
                                  arguments: {'resultId': resultId},
                                );
                              }
                            } else {
                              // Show info dialog
                              if (context.mounted) {
                                await showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Already Submitted'),
                                    content: const Text(
                                      'You have already completed this test. Results will be available after the due time.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                                Navigator.pop(context);
                              }
                            }
                            return; // Exit only if actually submitted
                          }
                          // If status is 'assigned' or 'started', allow continuing the test
                        }

                        if (context.mounted) {
                          // Minimal smooth transition to test screen
                          Navigator.pushReplacement(
                            context,
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      TakeTestScreen(test: test),
                              transitionsBuilder:
                                  (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                    child,
                                  ) {
                                    final offsetTween =
                                        Tween<Offset>(
                                          begin: const Offset(0.0, 0.04),
                                          end: Offset.zero,
                                        ).chain(
                                          CurveTween(
                                            curve: Curves.easeOutCubic,
                                          ),
                                        );
                                    final fadeTween = Tween<double>(
                                      begin: 0.0,
                                      end: 1.0,
                                    ).chain(CurveTween(curve: Curves.easeOut));
                                    return FadeTransition(
                                      opacity: animation.drive(fadeTween),
                                      child: SlideTransition(
                                        position: animation.drive(offsetTween),
                                        child: child,
                                      ),
                                    );
                                  },
                              transitionDuration: const Duration(
                                milliseconds: 180,
                              ),
                              reverseTransitionDuration: const Duration(
                                milliseconds: 150,
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF8A00), Color(0xFFFF6A00)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          alignment: Alignment.center,
                          child: const Text(
                            'Start Test',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Go Back Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF7B00),
                        side: const BorderSide(
                          color: Color(0xFFFF7B00),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Go Back',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Icon Container
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          // Text Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        height: 1.5,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
