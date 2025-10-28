import 'package:flutter/material.dart';
import '../../models/test_model.dart';
import 'take_test_screen.dart';

class TestRulesScreen extends StatelessWidget {
  final TestModel test;

  const TestRulesScreen({Key? key, required this.test}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F5),
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
                      child: const Icon(
                        Icons.arrow_back,
                        size: 28,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Timer Display
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${test.duration} Mins',
                        style: const TextStyle(
                          color: Color(0xFFFF7B00),
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
                    const Text(
                      'Before You Start the Test',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Please read the following instructions carefully before beginning your test.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mascot Image
                    Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.asset(
                          'assets/images/mascot.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF7B00).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.school,
                                size: 120,
                                color: Color(0xFFFF7B00),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Instruction Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          // Rule 1: No Tab Switching
                          _buildRuleItem(
                            icon: Icons.tab_unselected,
                            title: 'No Tab Switching',
                            description:
                                'Leaving the app or switching tabs will automatically submit your test.',
                          ),
                          // Rule 2: Stable Connection
                          _buildRuleItem(
                            icon: Icons.wifi,
                            title: 'Stable Connection',
                            description:
                                'Ensure you have a stable internet connection throughout the test.',
                          ),
                          // Rule 3: Timer Warning
                          _buildRuleItem(
                            icon: Icons.timer,
                            title: 'Timer Cannot Be Paused',
                            description:
                                'Once you start, the timer cannot be paused or stopped.',
                          ),
                          // Rule 4: Focus Required
                          _buildRuleItem(
                            icon: Icons.visibility,
                            title: 'Stay Focused',
                            description:
                                'Keep the test window in focus. Any distraction will auto-submit.',
                          ),
                          // Rule 5: Honest Attempt
                          _buildRuleItem(
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
              color: const Color(0xFFF8F7F5),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Start Test Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TakeTestScreen(test: test),
                          ),
                        );
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
              color: const Color(0xFFFF7B00).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFFF7B00), size: 24),
          ),
          const SizedBox(width: 16),
          // Text Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
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
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                    height: 1.5,
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
