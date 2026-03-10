import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/daily_challenge_provider.dart';
import '../providers/student_provider.dart';
import '../services/daily_challenge_service.dart';
import 'daily_result_screen.dart';

/// Daily Challenge Card Widget
/// Uses DailyChallengeProvider for state management and caching
/// Prevents unnecessary reloads and maintains state across navigation
class DailyChallengeCard extends StatefulWidget {
  final String studentId;
  final String studentEmail;

  const DailyChallengeCard({
    super.key,
    required this.studentId,
    required this.studentEmail,
  });

  @override
  State<DailyChallengeCard> createState() => _DailyChallengeCardState();
}

class _DailyChallengeCardState extends State<DailyChallengeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    // Initialize provider once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized && mounted) {
        _initialized = true;
        context.read<DailyChallengeProvider>().initialize(widget.studentId);
      }
    });
  }

  @override
  void didUpdateWidget(DailyChallengeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If studentId changes (new student logged in), re-initialize
    if (oldWidget.studentId != widget.studentId) {
      _initialized = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initialized = true;
          context.read<DailyChallengeProvider>().initialize(widget.studentId);
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Submit the selected answer
  Future<void> _submitAnswer(DailyChallengeProvider provider) async {
    final isCorrect = await provider.submitAnswer(
      widget.studentId,
      widget.studentEmail,
    );

    if (!mounted) return;

    // Also save to SharedPreferences via service
    await DailyChallengeService().saveDailyResult(
      widget.studentId,
      isCorrect,
      5.0, // Points earned for daily challenge
    );

    // Wait for Firestore write to complete before refreshing UI
    await Future.delayed(const Duration(milliseconds: 800));

    // Refresh student data to update Firestore streak in UI
    if (mounted) {
      final studentProvider = context.read<StudentProvider>();
      await studentProvider.refreshStudentStreak(widget.studentId);
    }

    if (isCorrect) {
      // Trigger success animation
      _animationController.forward().then((_) {
        _animationController.reverse();
      });
    }

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isCorrect ? Icons.check_circle : Icons.cancel,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isCorrect
                    ? '🎉 Correct! +5 Reward Points!'
                    : '❌ Wrong answer. Better luck tomorrow!',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isCorrect
            ? const Color(0xFF4CAF50)
            : const Color(0xFFF44336),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<DailyChallengeProvider>(
      builder: (context, provider, child) {
        // Get this student's cached challenge
        final cachedChallenge = provider.getCachedChallenge(widget.studentId);

        // Loading state (only show on first load, not on selection change)
        if (provider.isLoading(widget.studentId) && cachedChallenge == null) {
          return _buildLoadingCard(theme);
        }

        // Error state
        if (provider.errorMessage != null && cachedChallenge == null) {
          return _buildErrorCard(theme, provider.errorMessage!);
        }

        // No challenge available
        if (cachedChallenge == null) {
          return _buildNoChallengeCard(theme);
        }

        // If already answered today, show result screen
        if (provider.hasAnsweredToday(widget.studentId)) {
          return _buildResultView(provider);
        }

        final challenge = cachedChallenge;
        final question = challenge['question'] as String? ?? '';
        final options =
            (challenge['options'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final correctAnswer = challenge['correctAnswer'] as String? ?? '';

        return _buildChallengeCard(
          theme,
          provider,
          question,
          options,
          correctAnswer,
        );
      },
    );
  }

  /// Build result view after answering
  Widget _buildResultView(DailyChallengeProvider provider) {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, _) {
        final currentStreak = studentProvider.currentStudent?.streak ?? 0;

        return FutureBuilder<Map<String, dynamic>>(
          future: DailyChallengeService().getResultData(widget.studentId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFF27F0D),
                    ),
                  ),
                ),
              );
            }

            final resultData =
                snapshot.data ?? {'isCorrect': false, 'points': 5.0};

            return DailyResultScreen(
              isCorrect: resultData['isCorrect'] as bool,
              points: resultData['points'] as double,
              streak: currentStreak,
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCC6600), Color(0xFFF27F0D)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF27F0D).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          SizedBox(height: 16),
          Text(
            'Loading today\'s challenge...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Unable to load challenge',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again.',
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              context.read<DailyChallengeProvider>().fetchChallenge(
                widget.studentId,
                forceRefresh: true,
              );
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF27F0D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoChallengeCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.calendar_today, color: Colors.orange[300], size: 48),
          const SizedBox(height: 12),
          const Text(
            'No challenge available today',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back tomorrow for a new challenge!',
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeCard(
    ThemeData theme,
    DailyChallengeProvider provider,
    String question,
    List<String> options,
    String correctAnswer,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFCC6600), Color(0xFFF27F0D)],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Challenge',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Answer correctly to earn +5 points!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Question
                Text(
                  question,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),

                // Already answered today
                if (provider.hasAnsweredToday(widget.studentId)) ...[
                  _buildAnsweredState(
                    provider.getTodayResult(widget.studentId),
                  ),
                ] else ...[
                  // Options in 2-column grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.8,
                        ),
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      return _buildOptionTile(
                        options[index],
                        index,
                        options,
                        provider,
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: ElevatedButton(
                        onPressed:
                            provider.getSelectedAnswer(widget.studentId) ==
                                    null ||
                                provider.isSubmitting(widget.studentId)
                            ? null
                            : () => _submitAnswer(provider),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF27F0D),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          disabledBackgroundColor: Colors.grey[300],
                          disabledForegroundColor: Colors.grey[500],
                        ),
                        child: provider.isSubmitting(widget.studentId)
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Submit Answer',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(
    String option,
    int index,
    List<String> allOptions,
    DailyChallengeProvider provider,
  ) {
    final isSelected = provider.getSelectedAnswer(widget.studentId) == option;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        provider.setSelectedAnswer(widget.studentId, option);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF27F0D).withOpacity(0.1)
              : theme.brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF27F0D)
                : theme.brightness == Brightness.dark
                ? Colors.grey[700]!
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFF27F0D)
                      : theme.brightness == Brightness.dark
                      ? Colors.grey[600]!
                      : Colors.grey[400]!,
                  width: 2,
                ),
                color: isSelected
                    ? const Color(0xFFF27F0D)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFFF27F0D)
                      : theme.textTheme.bodyMedium?.color,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnsweredState(String? result) {
    final isCorrect = result == 'correct';
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCorrect
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorrect ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.cancel,
            color: isCorrect ? Colors.green : Colors.red,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCorrect ? 'Correct Answer!' : 'Incorrect Answer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isCorrect
                      ? 'You earned 5 reward points!'
                      : 'Try again tomorrow for a new challenge!',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
