import 'package:flutter/material.dart';
import '../../rewards_module.dart';

class RewardsTopSwitcher extends StatelessWidget {
  final bool isCatalogActive;
  final String? studentId;

  const RewardsTopSwitcher({
    super.key,
    required this.isCatalogActive,
    this.studentId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isDark
              ? Theme.of(context).colorScheme.surface.withOpacity(0.6)
              : Theme.of(context).colorScheme.surfaceContainerHighest
                  .withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SegmentButton(
                label: 'Catalog',
                selected: isCatalogActive,
                onTap: () {
                  if (!isCatalogActive) {
                    RewardsModule.navigateToCatalog(context);
                  }
                },
              ),
            ),
            Expanded(
              child: _SegmentButton(
                label: 'My Rewards',
                selected: !isCatalogActive,
                onTap: () {
                  if (isCatalogActive) {
                    final id = studentId;
                    if (id != null && id.isNotEmpty) {
                      RewardsModule.navigateToStudentRequests(
                        context,
                        studentId: id,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sign in to view your rewards'),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFF97316);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).textTheme.bodyMedium?.color
                    ?.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
