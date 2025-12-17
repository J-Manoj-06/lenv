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
          color: isDark ? Colors.grey[850] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _SegmentButton(
              label: 'Catalog',
              selected: isCatalogActive,
              onTap: () {
                if (!isCatalogActive) {
                  RewardsModule.navigateToCatalog(context);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF2800D) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFFF2800D).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
        ),
      ),
    );
  }
}
