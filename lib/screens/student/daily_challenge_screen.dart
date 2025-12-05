import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/daily_challenge_provider.dart';
import '../../providers/student_provider.dart';
import '../../services/daily_challenge_service.dart';

class DailyChallengeScreen extends StatefulWidget {
  final String studentId;
  final String studentEmail;

  const DailyChallengeScreen({
    super.key,
    required this.studentId,
    required this.studentEmail,
  });

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  String? selectedAnswer;
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Always reinitialize to check current status
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<DailyChallengeProvider>();
      // Force initialize to check if already answered
      await provider.initialize(widget.studentId);
    });
  }

  Future<void> _checkAnswer(
    BuildContext context,
    String correctAnswer,
    DailyChallengeProvider provider,
  ) async {
    if (selectedAnswer == null || isSubmitting) return;

    setState(() => isSubmitting = true);

    final isCorrect = selectedAnswer == correctAnswer;

    // Set the selected answer in provider before submitting
    provider.setSelectedAnswer(widget.studentId, selectedAnswer!);

    // Submit through provider
    await provider.submitAnswer(widget.studentId, widget.studentEmail);

    // Save to service
    await DailyChallengeService().saveDailyResult(
      widget.studentId,
      isCorrect,
      5.0,
    );

    // Refresh student data to get updated streak (but don't reinitialize provider yet)
    if (mounted) {
      final studentProvider = Provider.of<StudentProvider>(
        context,
        listen: false,
      );
      await studentProvider.refresh(widget.studentId);
    }

    if (!mounted) return;

    setState(() => isSubmitting = false);

    // Show result dialog
    await _showResultDialog(context, isCorrect);

    if (!mounted) return;

    // Navigate back to dashboard - the dashboard will refresh on return
    Navigator.pop(context, isCorrect);
  }

  Future<void> _showResultDialog(BuildContext context, bool isCorrect) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFF23190F),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF23190F),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Result Icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCorrect
                      ? const Color(0xFF28A745).withOpacity(0.1)
                      : const Color(0xFFDC3545).withOpacity(0.1),
                ),
                child: Icon(
                  isCorrect ? Icons.check_rounded : Icons.close_rounded,
                  size: 64,
                  color: isCorrect
                      ? const Color(0xFF28A745)
                      : const Color(0xFFDC3545),
                ),
              ),
              const SizedBox(height: 24),
              // Result Title
              Text(
                isCorrect ? 'Great Job!' : 'Nice Try!',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              // Result Description
              Text(
                isCorrect ? 'You earned +5 points!' : 'Better luck next time.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6F42C1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getOptionColor(String option) {
    if (selectedAnswer == null) {
      return const Color(0xFF2A2A2A); // Default
    }
    if (selectedAnswer == option) {
      return const Color(0xFFFF8E24).withOpacity(0.22); // Selected
    }
    return const Color(0xFF2A2A2A); // Default
  }

  Border _getOptionBorder(String option) {
    if (selectedAnswer == option) {
      return Border.all(color: const Color(0xFFFF8E24), width: 2);
    }
    return Border.all(color: Colors.transparent, width: 2);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DailyChallengeProvider>(
      builder: (context, provider, child) {
        final challenge = provider.getCachedChallenge(widget.studentId);
        final hasAnswered = provider.hasAnsweredToday(widget.studentId);
        final result = provider.getTodayResult(widget.studentId);

        if (provider.isLoading(widget.studentId) && challenge == null) {
          return Scaffold(
            backgroundColor: const Color(0xFF23190F),
            body: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8E24)),
              ),
            ),
          );
        }

        if (challenge == null) {
          return Scaffold(
            backgroundColor: const Color(0xFF23190F),
            appBar: AppBar(
              backgroundColor: const Color(0xFF23190F),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: const Center(
              child: Text(
                'No challenge available',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
          );
        }

        // If already answered and NOT currently submitting, show completion screen
        if (hasAnswered && !isSubmitting) {
          final isCorrect = result == 'correct';
          return Scaffold(
            backgroundColor: const Color(0xFF23190F),
            body: SafeArea(
              child: Column(
                children: [
                  // Top App Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'Daily Challenge',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Completion Status
                  Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCorrect
                                ? const Color(0xFF28A745).withOpacity(0.1)
                                : const Color(0xFFDC3545).withOpacity(0.1),
                          ),
                          child: Icon(
                            isCorrect
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 64,
                            color: isCorrect
                                ? const Color(0xFF28A745)
                                : const Color(0xFFDC3545),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          isCorrect
                              ? 'Already Completed!'
                              : 'Already Attempted',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isCorrect
                              ? 'You earned +5 points today!'
                              : 'Better luck tomorrow!',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Come back tomorrow for a new challenge',
                          style: TextStyle(fontSize: 14, color: Colors.white60),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Close Button
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6F42C1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final question = challenge['question'] as String? ?? '';
        final options =
            (challenge['options'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final correctAnswer = challenge['correctAnswer'] as String? ?? '';

        return Scaffold(
          backgroundColor: const Color(0xFF23190F),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top App Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Daily Challenge',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48), // Balance the close button
                    ],
                  ),
                ),

                // Question
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text(
                    question,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                ),

                // Options Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.2,
                          ),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedAnswer = option;
                            });
                            // Also update provider
                            provider.setSelectedAnswer(
                              widget.studentId,
                              option,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _getOptionColor(option),
                              border: _getOptionBorder(option),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                option,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Check Answer Button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedAnswer == null || isSubmitting
                          ? null
                          : () =>
                                _checkAnswer(context, correctAnswer, provider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8E24),
                        foregroundColor: const Color(0xFF23190F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFF2A2A2A),
                        disabledForegroundColor: Colors.white30,
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF23190F),
                                ),
                              ),
                            )
                          : const Text(
                              'Check Answer',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
