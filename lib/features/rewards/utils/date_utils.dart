/// Date and time utility functions for reward system
class DateUtils {
  /// Standard lock duration for rewards (21 days)
  static const int lockDurationDays = 21;

  /// Reminder thresholds (in days before expiry)
  static const List<int> reminderDaysBeforeExpiry = [3, 7, 14];

  /// Get lock expiration timestamp
  static DateTime getLockExpirationTime({DateTime? fromDate}) {
    final now = fromDate ?? DateTime.now();
    return now.add(const Duration(days: lockDurationDays));
  }

  /// Check if date should trigger a reminder
  static bool shouldRemind(
    DateTime lockExpiresAt, {
    required int daysBeforeExpiry,
  }) {
    final now = DateTime.now();
    final daysDiff = lockExpiresAt.difference(now).inDays;
    // Trigger reminder when remaining days are exactly equal or just passed threshold
    return daysDiff >= 0 && daysDiff <= daysBeforeExpiry;
  }

  /// Get remaining days until lock expires
  static int getRemainingDays(DateTime lockExpiresAt) {
    final now = DateTime.now();
    final diff = lockExpiresAt.difference(now);
    return diff.inDays;
  }

  /// Check if lock has expired
  static bool isLockExpired(DateTime lockExpiresAt) {
    return DateTime.now().isAfter(lockExpiresAt);
  }

  /// Format remaining time as readable string
  static String formatRemainingTime(DateTime lockExpiresAt) {
    final remaining = getRemainingDays(lockExpiresAt);
    if (remaining < 0) {
      return 'Expired';
    } else if (remaining == 0) {
      return 'Expires today';
    } else if (remaining == 1) {
      return 'Expires tomorrow';
    } else if (remaining <= 7) {
      return 'Expires in $remaining days';
    } else {
      return 'Expires in ${(remaining / 7).ceil()} weeks';
    }
  }

  /// Get next reminder time
  static DateTime? getNextReminderTime(DateTime lockExpiresAt) {
    final now = DateTime.now();
    for (final days in reminderDaysBeforeExpiry) {
      final reminderTime = lockExpiresAt.subtract(Duration(days: days));
      if (reminderTime.isAfter(now)) {
        return reminderTime;
      }
    }
    return null;
  }

  /// Format date for display
  static String formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Format date and time for display
  static String formatDateTime(DateTime dateTime) {
    final date = formatDate(dateTime);
    final time =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Check if date is within specified days
  static bool isWithinDays(DateTime date, int days) {
    final now = DateTime.now();
    final diff = date.difference(now);
    return diff.inDays >= 0 && diff.inDays <= days;
  }
}
