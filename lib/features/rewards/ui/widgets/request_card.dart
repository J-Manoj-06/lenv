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
    final statusColor = _getStatusColor(request.status);
    final statusLabel = _getStatusLabel(request.status);
    final productName = _getProductName();
    final remainingDays = reward_date_utils.DateUtils.getRemainingDays(
      request.timestamps.lockExpiresAt,
    );

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTapped,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Name and Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Badge(
                    label: Text(
                      statusLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    backgroundColor: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Points and Date Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.card_giftcard,
                        size: 16,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${request.pointsData.required} points',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (remainingDays > 0)
                    Text(
                      '$remainingDays days left',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Timeline Indicator
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  widthFactor: _getProgressFraction(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              if (onActionPressed != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : onActionPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: statusColor,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: isLoading
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(actionLabel ?? 'Take Action'),
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
