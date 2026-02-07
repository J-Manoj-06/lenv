/// Poll Message Widget - Redesigned premium UI matching Insights style
/// Displays poll in chat with calm teal accent, smooth animations, premium feel
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/poll_model.dart';
import '../models/user_model.dart';
import '../services/poll_service.dart';
import '../core/constants/app_colors.dart';
import '../providers/auth_provider.dart' as local_auth;

class PollMessageWidget extends StatefulWidget {
  final PollModel poll;
  final String chatId;
  final String chatType;
  final bool isOwnMessage;

  const PollMessageWidget({
    super.key,
    required this.poll,
    required this.chatId,
    required this.chatType,
    this.isOwnMessage = false,
  });

  @override
  State<PollMessageWidget> createState() => _PollMessageWidgetState();
}

class _PollMessageWidgetState extends State<PollMessageWidget>
    with SingleTickerProviderStateMixin {
  final PollService _pollService = PollService();
  String? _tappedOptionId;
  late AnimationController _animController;

  Color _getAccentColor(UserRole? role) {
    switch (role) {
      case UserRole.teacher:
        return AppColors.teacherColor;
      case UserRole.student:
        return AppColors.studentColor;
      case UserRole.parent:
        return AppColors.parentColor;
      case UserRole.institute:
      default:
        return AppColors.insightsTeal;
    }
  }

  Color _getAccentDark(Color color) {
    return Color.lerp(color, Colors.black, 0.2) ?? color;
  }

  LinearGradient _getAccentGradient(Color base, Color dark) {
    return LinearGradient(
      colors: [base, dark],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // BACKEND INTEGRATION POINT: Keep existing vote() logic unchanged
  Future<void> _handleVote(String optionId, String userId) async {
    // Optimistic update - don't block UI, allow rapid switching
    _animController.forward().then((_) => _animController.reverse());

    try {
      // Fire and forget - UI updates via stream
      _pollService.vote(
        chatId: widget.chatId,
        messageId: widget.poll.id!,
        optionId: optionId,
        userId: userId,
        chatType: widget.chatType,
        allowMultiple: widget.poll.allowMultiple,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to vote: ${e.toString()}'),
            backgroundColor: AppColors.accentDanger,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<local_auth.AuthProvider>(
      context,
      listen: false,
    );
    final currentUserId = authProvider.currentUser?.uid ?? '';
    final currentUserRole = authProvider.currentUser?.role;
    final accentColor = _getAccentColor(currentUserRole);
    final accentDark = _getAccentDark(accentColor);
    final accentGradient = _getAccentGradient(accentColor, accentDark);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use real-time stream for live updates
    return StreamBuilder<PollModel?>(
      stream: _pollService.pollStream(
        chatId: widget.chatId,
        messageId: widget.poll.id!,
        chatType: widget.chatType,
      ),
      initialData: widget.poll,
      builder: (context, snapshot) {
        final poll = snapshot.data ?? widget.poll;
        final userVotes = poll.getUserVotes(currentUserId).toSet();
        final hasVoted = poll.hasUserVotedAny(currentUserId);
        final totalVotes = poll.totalVotes;

        return Align(
          alignment: widget.isOwnMessage
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(
              top: 6,
              bottom: 6,
              left: widget.isOwnMessage ? 60 : 0,
              right: widget.isOwnMessage ? 12 : 30,
            ),
            constraints: const BoxConstraints(maxWidth: 600),
            child: _buildPollCard(
              poll: poll,
              hasVoted: hasVoted,
              userVotes: userVotes,
              totalVotes: totalVotes,
              currentUserId: currentUserId,
              isDark: isDark,
              accentColor: accentColor,
              accentGradient: accentGradient,
            ),
          ),
        );
      },
    );
  }

  // Main poll card with premium styling
  Widget _buildPollCard({
    required PollModel poll,
    required bool hasVoted,
    required Set<String> userVotes,
    required int totalVotes,
    required String currentUserId,
    required bool isDark,
    required Color accentColor,
    required LinearGradient accentGradient,
  }) {
    final cardColor = isDark ? AppColors.surfaceCard : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16), // Premium radius 16-18px
        border: Border.all(
          color: isDark
              ? AppColors.borderMedium
              : accentColor.withOpacity(0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: type badge + "You voted" indicator
            _buildHeader(poll, hasVoted, isDark, accentColor),
            const SizedBox(height: 12),

            // Question text
            _buildQuestion(poll, isDark),
            const SizedBox(height: 16),

            // Options list
            ...poll.options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              final isSelected = userVotes.contains(option.id);
              final percentage = totalVotes > 0
                  ? (option.voteCount / totalVotes) * 100
                  : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildOptionRow(
                  option: option,
                  index: index,
                  isSelected: isSelected,
                  percentage: percentage,
                  hasVoted: hasVoted,
                  allowMultiple: poll.allowMultiple,
                  currentUserId: currentUserId,
                  isDark: isDark,
                  accentColor: accentColor,
                  accentGradient: accentGradient,
                ),
              );
            }),

            const SizedBox(height: 8),

            // Footer: total votes summary
            _buildFooter(totalVotes, hasVoted, isDark),
          ],
        ),
      ),
    );
  }

  // Header with type badge and "You voted" indicator
  Widget _buildHeader(
    PollModel poll,
    bool hasVoted,
    bool isDark,
    Color accentColor,
  ) {
    return Row(
      children: [
        // Type badge: SINGLE CHOICE / MULTIPLE CHOICE
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: accentColor.withOpacity(0.4), width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                poll.allowMultiple
                    ? Icons.check_box_outlined
                    : Icons.radio_button_checked_outlined,
                size: 14,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Text(
                poll.allowMultiple ? 'MULTIPLE CHOICE' : 'SINGLE CHOICE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // "You voted" badge
        if (hasVoted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accentSuccess.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.check_circle,
                  size: 14,
                  color: AppColors.accentSuccess,
                ),
                SizedBox(width: 4),
                Text(
                  'You voted',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentSuccess,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Question text with proper typography
  Widget _buildQuestion(PollModel poll, bool isDark) {
    return Text(
      poll.question,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
      ),
    );
  }

  // Option row with circular label, text, percentage, progress bar
  Widget _buildOptionRow({
    required PollOption option,
    required int index,
    required bool isSelected,
    required double percentage,
    required bool hasVoted,
    required bool allowMultiple,
    required String currentUserId,
    required bool isDark,
    required Color accentColor,
    required LinearGradient accentGradient,
  }) {
    final label = String.fromCharCode(65 + index); // A, B, C, ...
    final isTapped = _tappedOptionId == option.id;

    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _tappedOptionId = option.id;
        });
      },
      onTapUp: (_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _tappedOptionId = null;
            });
          }
        });
      },
      onTapCancel: () {
        setState(() {
          _tappedOptionId = null;
        });
      },
      onTap: () => _handleVote(option.id, currentUserId),
      child: AnimatedScale(
        scale: isTapped ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                      ? accentColor.withOpacity(0.12)
                      : accentColor.withOpacity(0.08))
                : (isDark
                      ? AppColors.surfaceDark.withOpacity(0.5)
                      : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : (isDark ? AppColors.borderSubtle : Colors.grey.shade300),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: label + text + percentage/count
                Row(
                  children: [
                    // Circular label (A/B/C) - animated
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accentColor
                            : (isDark
                                  ? AppColors.textMuted.withOpacity(0.2)
                                  : Colors.grey.shade300),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                      ? AppColors.textMuted
                                      : Colors.grey.shade700),
                          ),
                          child: Text(label),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Option text
                    Expanded(
                      child: Text(
                        option.text,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? AppColors.textOnDark : accentColor)
                              : (isDark
                                    ? AppColors.textOnDark
                                    : AppColors.textPrimary),
                        ),
                      ),
                    ),
                    // Vote count / percentage bubble (after vote only)
                    if (hasVoted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accentColor
                              : (isDark
                                    ? AppColors.textMuted.withOpacity(0.2)
                                    : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${percentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                      ? AppColors.textOnDark
                                      : Colors.grey.shade700),
                          ),
                        ),
                      ),
                  ],
                ),
                // Progress bar (shown after vote)
                if (hasVoted) ...[
                  const SizedBox(height: 10),
                  Stack(
                    children: [
                      // Background bar
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceDark
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      // Progress fill (animated)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        height: 6,
                        width:
                            MediaQuery.of(context).size.width *
                            (percentage / 100) *
                            0.8, // Approximate width
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? accentGradient
                              : LinearGradient(
                                  colors: [
                                    AppColors.textMuted.withOpacity(0.5),
                                    AppColors.textMuted.withOpacity(0.3),
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Small vote count text
                  Text(
                    '${option.voteCount} vote${option.voteCount != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textMuted
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Footer with total votes and placeholder text
  Widget _buildFooter(int totalVotes, bool hasVoted, bool isDark) {
    if (totalVotes == 0) {
      return Text(
        'Be the first to vote',
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: isDark ? AppColors.textMuted : Colors.grey.shade500,
        ),
      );
    }

    return Row(
      children: [
        Icon(
          Icons.how_to_vote_outlined,
          size: 16,
          color: isDark ? AppColors.textMuted : Colors.grey.shade600,
        ),
        const SizedBox(width: 6),
        Text(
          '$totalVotes vote${totalVotes != 1 ? 's' : ''}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textMuted : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
