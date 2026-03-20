import 'package:flutter/material.dart';

class MessageReactionSummary extends StatelessWidget {
  final Map<String, int> summary;
  final bool isMe;
  final VoidCallback? onTap;

  const MessageReactionSummary({
    super.key,
    required this.summary,
    required this.isMe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final items = summary.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topItems = items.take(3).toList();

    return Transform.translate(
      offset: const Offset(0, -6),
      child: Padding(
        padding: const EdgeInsets.only(top: 0, bottom: 2),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            children: topItems.map((entry) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.88,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Text(
                    '${entry.key} ${entry.value}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      height: 1.0,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
