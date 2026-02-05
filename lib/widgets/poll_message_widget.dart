/// Poll Message Widget - Displays poll in chat with real-time voting
/// Supports single-select and multi-select polls with animated progress bars
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/poll_model.dart';
import '../services/poll_service.dart';
import '../core/constants/app_colors.dart';
import '../providers/auth_provider.dart' as local_auth;

class PollMessageWidget extends StatefulWidget {
  final PollModel poll;
  final String chatId;
  final String chatType; // 'community', 'group', 'individual'
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

class _PollMessageWidgetState extends State<PollMessageWidget> {
  final PollService _pollService = PollService();
  bool _isVoting = false;

  Future<void> _handleVote(String optionId, String userId) async {
    if (_isVoting) return;

    setState(() {
      _isVoting = true;
    });

    try {
      await _pollService.vote(
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
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVoting = false;
        });
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
    final primaryColor = Theme.of(context).colorScheme.primary;

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
        final userVotes = poll.getUserVotes(currentUserId);
        final hasVoted = poll.hasUserVotedAny(currentUserId);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: primaryColor.withOpacity(0.3), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poll icon and type indicator
                  Row(
                    children: [
                      Icon(Icons.poll, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        widget.poll.allowMultiple
                            ? 'MULTIPLE CHOICE'
                            : 'SINGLE CHOICE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Question
                  Text(
                    poll.question,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Options
                  ...poll.options.map((option) {
                    final isSelected = userVotes.contains(option.id);
                    final percentage = poll.totalVotes > 0
                        ? (option.voteCount / poll.totalVotes * 100)
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PollOptionWidget(
                        option: option,
                        isSelected: isSelected,
                        percentage: percentage,
                        allowMultiple: poll.allowMultiple,
                        primaryColor: primaryColor,
                        onTap: _isVoting
                            ? null
                            : () => _handleVote(option.id, currentUserId),
                      ),
                    );
                  }),

                  // Footer info
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${poll.totalVotes} ${poll.totalVotes == 1 ? 'vote' : 'votes'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (hasVoted)
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: primaryColor,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'You voted',
                              style: TextStyle(
                                fontSize: 13,
                                color: primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PollOptionWidget extends StatelessWidget {
  final PollOption option;
  final bool isSelected;
  final double percentage;
  final bool allowMultiple;
  final Color primaryColor;
  final VoidCallback? onTap;

  const _PollOptionWidget({
    super.key,
    required this.option,
    required this.isSelected,
    required this.percentage,
    required this.allowMultiple,
    required this.primaryColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? primaryColor : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isSelected ? primaryColor.withOpacity(0.05) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Option text and checkbox/radio
              Row(
                children: [
                  // Selection indicator
                  Icon(
                    allowMultiple
                        ? (isSelected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank)
                        : (isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked),
                    color: isSelected ? primaryColor : Colors.grey[400],
                    size: 22,
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
                            : FontWeight.normal,
                        color: isSelected ? primaryColor : Colors.black87,
                      ),
                    ),
                  ),

                  // Vote count
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${option.voteCount}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Progress bar
              Stack(
                children: [
                  // Background bar
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Progress bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    height: 6,
                    width:
                        MediaQuery.of(context).size.width * (percentage / 100),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Percentage text
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
