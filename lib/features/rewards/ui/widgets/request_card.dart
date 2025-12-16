import 'package:flutter/material.dart';
import '../../models/reward_request_model.dart';
import '..\\..\\utils\\date_utils.dart' as reward_date_utils;

class RequestCard extends StatelessWidget {
  final RewardRequestModel request;
  final VoidCallback onTapped;
  final VoidCallback? onActionPressed;
  final String? actionLabel;
  final bool isLoading;

  const RequestCard({
    super.key,
    required this.request,
    required this.onTapped,
    this.onActionPressed,
    this.actionLabel,
    this.isLoading = false,
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
    // Try to extract from audit entries or request data
    if (request.audit.isNotEmpty) {
      final firstEntry = request.audit.first;
      return firstEntry.actor ?? 'Unknown Product';
    }
    return 'Reward Request';
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
                    '${request.pointsData.required} points',
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
                    value: _getProgressFraction(),
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

  double _getProgressFraction() {
    const totalSteps = 5;
    late int currentStep;

    switch (request.status) {
      case RewardRequestStatus.pendingParentApproval:
        currentStep = 1;
      case RewardRequestStatus.approvedPurchaseInProgress:
        currentStep = 2;
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        currentStep = 3;
      case RewardRequestStatus.completed:
        currentStep = 4;
      case RewardRequestStatus.expiredOrAutoResolved:
      case RewardRequestStatus.cancelled:
        currentStep = 0;
    }

    return currentStep / totalSteps;
  }
}
