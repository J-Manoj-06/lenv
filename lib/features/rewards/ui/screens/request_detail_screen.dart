import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/reward_request_model.dart';
import '../../providers/rewards_providers.dart';
import '../../utils/date_utils.dart' as reward_date_utils;
import '../widgets/modals.dart';

class RequestDetailScreen extends ConsumerStatefulWidget {
  final String requestId;
  final RewardRequestModel? initialRequest;

  const RequestDetailScreen({
    super.key,
    required this.requestId,
    this.initialRequest,
  });

  @override
  ConsumerState<RequestDetailScreen> createState() =>
      _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final requestAsync = ref.watch(currentRequestProvider(widget.requestId));

    return requestAsync.when(
      data: (request) {
        if (request == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Request Not Found')),
            body: const Center(child: Text('Request not found')),
          );
        }

        return _RequestDetailContent(
          request: request,
          isLoading: _isLoading,
          onStatusChanged: _onStatusChanged,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, st) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

  Future<void> _onStatusChanged(
    RewardRequestModel request,
    RewardRequestStatus newStatus,
  ) async {
    setState(() => _isLoading = true);

    try {
      final updateNotifier = ref.read(updateRequestStatusProvider.notifier);
      await updateNotifier.updateStatus(
        requestId: request.requestId,
        newStatus: newStatus,
        userId: 'current_user',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _RequestDetailContent extends StatelessWidget {
  final RewardRequestModel request;
  final bool isLoading;
  final Function(RewardRequestModel, RewardRequestStatus) onStatusChanged;

  const _RequestDetailContent({
    required this.request,
    required this.isLoading,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final productName = _getProductName();
    final remainingDays = reward_date_utils.DateUtils.getRemainingDays(
      request.timestamps.lockExpiresAt,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Request Details'), elevation: 0),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge
            Padding(
              padding: const EdgeInsets.all(16),
              child: _StatusBadge(status: request.status),
            ),
            // Request Info Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Product',
                      value: productName,
                      icon: Icons.shopping_bag,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Request ID',
                      value: request.requestId.substring(0, 8),
                      icon: Icons.receipt_long,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Created Date',
                      value: reward_date_utils.DateUtils.formatDate(
                        request.timestamps.requestedAt,
                      ),
                      icon: Icons.calendar_today,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Lock Expires In',
                      value: '$remainingDays days',
                      icon: Icons.schedule,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Points Information
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Points Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PointsBar(
                      label: 'Points Required',
                      points: request.pointsData.required.toInt(),
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    _PointsBar(
                      label: 'Points Locked',
                      points: request.pointsData.locked.toInt(),
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    _PointsBar(
                      label: 'Points Deducted',
                      points: request.pointsData.deducted.toInt(),
                      color: Colors.green,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Status Timeline
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatusTimeline(request: request),
            ),
            const SizedBox(height: 20),
            // Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ActionButtons(
                request: request,
                isLoading: isLoading,
                onStatusChanged: onStatusChanged,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _getProductName() {
    if (request.audit.isNotEmpty) {
      final firstEntry = request.audit.first;
      return firstEntry.actor ?? 'Unknown Product';
    }
    return 'Reward Item';
  }
}

class _StatusBadge extends StatelessWidget {
  final RewardRequestStatus status;

  const _StatusBadge({required this.status});

  Color _getColor() {
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

  String _getLabel() {
    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        return 'Awaiting Parent Approval';
      case RewardRequestStatus.approvedPurchaseInProgress:
        return 'Purchase In Progress';
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return 'Awaiting Delivery Confirmation';
      case RewardRequestStatus.completed:
        return 'Completed';
      case RewardRequestStatus.expiredOrAutoResolved:
        return 'Expired';
      case RewardRequestStatus.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _getColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getColor()),
      ),
      child: Text(
        _getLabel(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: _getColor(),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _PointsBar extends StatelessWidget {
  final String label;
  final int points;
  final Color color;

  const _PointsBar({
    required this.label,
    required this.points,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(
              '$points pts',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: 0.7,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final RewardRequestModel request;

  const _StatusTimeline({required this.request});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status History',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ...request.audit.asMap().entries.map((entry) {
                final isLast = entry.key == request.audit.length - 1;
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.orange[700],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.value.action,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                reward_date_utils.DateUtils.formatDateTime(
                                  entry.value.timestamp,
                                ),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!isLast) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Container(
                          width: 2,
                          height: 16,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final RewardRequestModel request;
  final bool isLoading;
  final Function(RewardRequestModel, RewardRequestStatus) onStatusChanged;

  const _ActionButtons({
    required this.request,
    required this.isLoading,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    // Show action buttons based on status
    if (request.status == RewardRequestStatus.pendingParentApproval) {
      buttons.addAll([
        ElevatedButton(
          onPressed: isLoading
              ? null
              : () async {
                  await onStatusChanged(
                    request,
                    RewardRequestStatus.approvedPurchaseInProgress,
                  );
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approve Request'),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: isLoading
              ? null
              : () async {
                  await onStatusChanged(request, RewardRequestStatus.cancelled);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Reject Request'),
        ),
      ]);
    } else if (request.status ==
        RewardRequestStatus.awaitingDeliveryConfirmation) {
      buttons.add(
        ElevatedButton(
          onPressed: isLoading
              ? null
              : () {
                  showDialog(
                    context: context,
                    builder: (context) => DeliveryConfirmModal(
                      productName: 'Reward Item',
                      pointsToRelease: request.pointsData.required.toDouble(),
                      onConfirm: () {
                        Navigator.pop(context);
                        onStatusChanged(request, RewardRequestStatus.completed);
                      },
                      onCancel: () => Navigator.pop(context),
                      isLoading: isLoading,
                    ),
                  );
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Confirm Delivery'),
        ),
      );
    }

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(children: buttons);
  }
}
