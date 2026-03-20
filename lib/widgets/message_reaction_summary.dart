import 'package:flutter/material.dart';

class MessageReactionSummary extends StatelessWidget {
  final Map<String, int> summary;
  final bool isMe;

  const MessageReactionSummary({
    super.key,
    required this.summary,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final items = summary.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topItems = items.take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: topItems.map((entry) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(
                  0.8,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Text(
                '${entry.key} ${entry.value}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
