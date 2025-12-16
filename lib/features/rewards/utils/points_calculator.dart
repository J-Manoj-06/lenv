/// Utility functions for points calculations
class PointsCalculator {
  /// Calculate points required for a given price: points = 2 * price
  static int calculatePointsRequired({
    required double price,
    required double pointsPerRupee,
    required int maxPoints,
  }) {
    final calculated = (price * 2).round();
    return calculated > maxPoints ? maxPoints : calculated;
  }

  /// Calculate deducted points for manual purchase with confirmed price
  static int calculateDeductedPoints({
    required int lockedPoints,
    required double confirmedPrice,
    required double pointsPerRupee,
  }) {
    final calculated = (confirmedPrice * pointsPerRupee).round();
    return calculated > lockedPoints ? lockedPoints : calculated;
  }

  /// Calculate released points
  static int calculateReleasedPoints({
    required int lockedPoints,
    required int deductedPoints,
  }) {
    return lockedPoints - deductedPoints;
  }

  /// Format points for display
  static String formatPoints(int points) {
    if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(1)}K';
    }
    return points.toString();
  }

  /// Calculate points badge color intensity (green to red)
  static int getPointsStatusCode(int available, int required) {
    if (available >= required) return 100; // Green
    if (available >= required * 0.75) return 75; // Yellow-green
    if (available >= required * 0.5) return 50; // Yellow
    if (available >= required * 0.25) return 25; // Orange
    return 0; // Red
  }
}
