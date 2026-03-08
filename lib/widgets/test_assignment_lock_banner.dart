import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/test_assignment_lock.dart';

/// A banner displayed at the top of the test-creation form when another
/// teacher's lock is active for the selected class and subject.
///
/// Pass [currentTeacherId] so the banner is hidden when the lock belongs to
/// the currently logged-in teacher (they assigned it themselves).
///
/// Pass `lock: null` (or a lock where [TestAssignmentLock.isActive] is false)
/// to hide the banner with an animated collapse.
class TestAssignmentLockBanner extends StatelessWidget {
  final TestAssignmentLock? lock;

  /// UID of the currently logged-in teacher. When the lock's [teacherId]
  /// matches this value the banner will not be shown.
  final String? currentTeacherId;

  const TestAssignmentLockBanner({
    super.key,
    required this.lock,
    this.currentTeacherId,
  });

  @override
  Widget build(BuildContext context) {
    // Only show if: lock exists, is still active, AND belongs to a different teacher.
    final active =
        lock != null &&
        lock!.isActive &&
        (currentTeacherId == null || lock!.teacherId != currentTeacherId);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: active ? _buildBanner(context, lock!) : const SizedBox.shrink(),
    );
  }

  Widget _buildBanner(BuildContext context, TestAssignmentLock activeLock) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nextTime = _formatDateTime(activeLock.nextAvailableTimestamp);
    final teacherName = activeLock.assignedByTeacherName;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D1B00) : const Color(0xFFFFF3CD),
        border: Border.all(
          color: isDark ? const Color(0xFFB45309) : const Color(0xFFF59E0B),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_clock_rounded,
                color: Color(0xFFB45309),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test Already Assigned',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFFFCD34D)
                            : const Color(0xFF78350F),
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: teacherName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(
                          text:
                              ' has already assigned a test for this class.\n',
                        ),
                        const TextSpan(
                          text: 'Next assignment available after ',
                        ),
                        TextSpan(
                          text: nextTime,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: '.'),
                      ],
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

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isTomorrow =
        dt.year == now.year && dt.month == now.month && dt.day == now.day + 1;
    final timeStr = DateFormat('h:mm a').format(dt);
    if (isToday) return timeStr;
    if (isTomorrow) return 'tomorrow $timeStr';
    return DateFormat('d MMM, h:mm a').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Disabled-button tooltip wrapper
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps a button child so that a tooltip is shown when [isDisabled] is true.
class LockedButtonWrapper extends StatelessWidget {
  final bool isDisabled;
  final Widget child;
  final String tooltip;

  const LockedButtonWrapper({
    super.key,
    required this.isDisabled,
    required this.child,
    this.tooltip = 'Another teacher has already assigned a test',
  });

  @override
  Widget build(BuildContext context) {
    if (!isDisabled) return child;
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      child: AbsorbPointer(child: Opacity(opacity: 0.45, child: child)),
    );
  }
}
