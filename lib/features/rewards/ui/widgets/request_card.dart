import 'package:flutter/material.dart';
import '../../models/reward_request_model.dart';
import '../../utils/points_calculator.dart';
import '../../utils/date_utils.dart' as reward_date_utils;

class RequestCard extends StatelessWidget {
  final RewardRequestModel request;
  final VoidCallback onTapped;
  final VoidCallback? onActionPressed;
  final String? actionLabel;
  final bool isLoading;
  final VoidCallback? onDeletePressed;

  const RequestCard({
    super.key,
    required this.request,
    required this.onTapped,
    this.onActionPressed,
    this.actionLabel,
    this.isLoading = false,
    this.onDeletePressed,
  });

  Color _getStatusColor(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        return Colors.blue;
      case RewardRequestStatus.approvedPurchaseInProgress:
        return Colors.orange;
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return Colors.purple;
      case RewardRequestStatus.completed:
        return Colors.green;
      case RewardRequestStatus.expiredOrAutoResolved:
        return Colors.grey;
      case RewardRequestStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusLabel(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        return 'Awaiting Parent Approval';
      case RewardRequestStatus.approvedPurchaseInProgress:
        return 'Purchase In Progress';
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return 'Awaiting Delivery';
      case RewardRequestStatus.completed:
        return 'Completed';
      case RewardRequestStatus.expiredOrAutoResolved:
        return 'Expired';
      case RewardRequestStatus.cancelled:
        return 'Cancelled';
    }
  }

  String _getProductName() {
    // Prefer the product snapshot title; fallback to audit actor or a generic label
    final snapshotTitle = request.productSnapshot.title.trim();
    if (snapshotTitle.isNotEmpty) return snapshotTitle;

    if (request.audit.isNotEmpty) {
      final firstEntry = request.audit.first;
      final actor = firstEntry.actor.trim();
      if (actor.isNotEmpty) return actor;
    }

    return 'Reward Request';
  }

  int _getDisplayPoints() {
    final product = request.productSnapshot;

    // Prefer calculated points based on product snapshot to align with detail view
    final calculated = PointsCalculator.calculatePointsRequired(
      price: product.price.estimatedPrice,
      pointsPerRupee: product.pointsRule.pointsPerRupee,
      maxPoints: product.pointsRule.maxPoints,
    );
    if (calculated > 0) return calculated;

    if (request.pointsData.required > 0) return request.pointsData.required;
    final maxPoints = product.pointsRule.maxPoints;
    return maxPoints > 0 ? maxPoints : 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor(request.status);
    final statusLabel = _getStatusLabel(request.status);
    final productName = _getProductName();
    final remainingDays = reward_date_utils.DateUtils.getRemainingDays(
      request.timestamps.lockExpiresAt,
    );

    return Material(
      elevation: isDark ? 2 : 1,
      borderRadius: BorderRadius.circular(16),
      color: isDark ? Colors.grey[850] : Colors.white,
      shadowColor: Colors.black.withOpacity(0.05),
      child: InkWell(
        onTap: onTapped,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Name and Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                letterSpacing: 0.1,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Delete Button
                  if (onDeletePressed != null)
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade400,
                        size: 24,
                      ),
                      onPressed: onDeletePressed,
                      tooltip: 'Delete request',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Points and Date Info
              Row(
                children: [
                  Icon(
                    Icons.card_giftcard,
                    size: 18,
                    color: const Color(0xFFF2800D),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_getDisplayPoints()} points',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                    ),
                  ),
                  const Spacer(),
                  const Spacer(),
                  if (remainingDays > 0)
                    Text(
                      '$remainingDays days left',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Timeline Indicator
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: _getTimeProgressFraction(),
                    backgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ),
              if (onActionPressed != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: FilledButton(
                    onPressed: isLoading ? null : onActionPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF2800D),
                      disabledBackgroundColor: isDark
                          ? Colors.grey[700]
                          : Colors.grey[300],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isLoading
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isDark ? Colors.grey[400]! : Colors.grey[600]!,
                              ),
                            ),
                          )
                        : Text(
                            actionLabel ?? 'View Status',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double _getTimeProgressFraction() {
    // If completed, consider as 100%
    if (request.status == RewardRequestStatus.completed) return 1.0;
    // If cancelled/expired, show full track but no progress (0)
    if (request.status == RewardRequestStatus.expiredOrAutoResolved ||
        request.status == RewardRequestStatus.cancelled) {
      return 0.0;
    }

    final start = request.timestamps.requestedAt;
    final end = request.timestamps.lockExpiresAt;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0.0;

    final elapsed = DateTime.now().difference(start).inSeconds;
    final fraction = elapsed / total;
    if (fraction.isNaN || fraction.isInfinite) return 0.0;
    return fraction.clamp(0.0, 1.0);
  }
}
