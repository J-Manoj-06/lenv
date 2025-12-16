import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            _SegmentButton(
              label: 'Catalog',
              selected: isCatalogActive,
              onTap: () {
                if (!isCatalogActive) {
                  context.go('/rewards/catalog');
                }
              },
            ),
            _SegmentButton(
              label: 'My Rewards',
              selected: !isCatalogActive,
              onTap: () {
                if (isCatalogActive) {
                  final id = studentId;
                  if (id != null && id.isNotEmpty) {
                    context.go('/rewards/requests/$id');
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
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF2800D) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}
