import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/reward_request_model.dart';
import '../../providers/rewards_providers.dart';
import '../../utils/points_calculator.dart';
import '../../utils/date_utils.dart' as reward_date_utils;
import '../widgets/modals.dart';

class RequestDetailScreen extends ConsumerStatefulWidget {
  final String requestId;
  final RewardRequestModel? initialRequest;

  const RequestDetailScreen({super.key, required this.requestId, this.initialRequest});

  @override
  ConsumerState<RequestDetailScreen> createState() => _RequestDetailScreenState();
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
    final theme = Theme.of(context);
    final productName = _getProductName();
    final shortLen = request.requestId.length >= 6 ? 6 : request.requestId.length;
    final requestIdShort = '#${request.requestId.substring(0, shortLen)}';
    final remainingDays = reward_date_utils.DateUtils.getRemainingDays(
      request.timestamps.lockExpiresAt,
    );

    final pointsNeeded = _computePointsNeeded();

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF18181b)
          : Colors.grey[50],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(requestIdShort: requestIdShort),
              const SizedBox(height: 16),

              _SummaryCard(
                request: request,
                productName: productName,
                pointsNeeded: pointsNeeded,
                remainingDays: remainingDays,
              ),

              const SizedBox(height: 20),
              _ProgressTimeline(request: request),

              const SizedBox(height: 20),
              _RequestDetailsCard(
                request: request,
                productName: productName,
                pointsNeeded: pointsNeeded,
              ),

              const SizedBox(height: 20),
              _ActionButtons(
                request: request,
                isLoading: isLoading,
                onStatusChanged: onStatusChanged,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _getProductName() {
    final snapshotTitle = request.productSnapshot.title.trim();
    if (snapshotTitle.isNotEmpty) return snapshotTitle;
    if (request.audit.isNotEmpty) {
      final firstEntry = request.audit.first;
      final actor = firstEntry.actor;
      if (actor.trim().isNotEmpty) return actor.trim();
    }
    return 'Reward Item';
  }

  int _computePointsNeeded() {
    final product = request.productSnapshot;
    final calculated = PointsCalculator.calculatePointsRequired(
      price: product.price.estimatedPrice,
      pointsPerRupee: product.pointsRule.pointsPerRupee,
      maxPoints: product.pointsRule.maxPoints,
    );
    if (calculated > 0) return calculated;
    if (request.pointsData.required > 0) return request.pointsData.required;
    return product.pointsRule.maxPoints;
  }
}

class _TopBar extends StatelessWidget {
  final String requestIdShort;

  const _TopBar({required this.requestIdShort});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Request Status',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                requestIdShort,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.textTheme.labelSmall?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final RewardRequestModel request;
  final String productName;
  final int pointsNeeded;
  final int remainingDays;

  const _SummaryCard({
    required this.request,
    required this.productName,
    required this.pointsNeeded,
    required this.remainingDays,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final imageUrl = request.productSnapshot.imageUrl;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272a) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey[200]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(imageUrl, fit: BoxFit.cover),
                  )
                : const Icon(Icons.card_giftcard, size: 36, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusPill(status: request.status),
                const SizedBox(height: 8),
                Text(
                  productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  request.productSnapshot.description ?? 'Reward item',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${PointsCalculator.formatPoints(pointsNeeded)} pts',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF97316),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      remainingDays > 0
                          ? '$remainingDays days left'
                          : 'Lock active',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.textTheme.labelSmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressTimeline extends StatelessWidget {
  final RewardRequestModel request;

  const _ProgressTimeline({required this.request});

  int _currentStepIndex() {
    switch (request.status) {
      case RewardRequestStatus.pendingParentApproval:
        return 1;
      case RewardRequestStatus.approvedPurchaseInProgress:
        return 2;
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return 3;
      case RewardRequestStatus.completed:
        return 4;
      case RewardRequestStatus.expiredOrAutoResolved:
      case RewardRequestStatus.cancelled:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      _TimelineStep(
        label: 'Requested',
        description: 'Student sent reward request',
        icon: Icons.check,
      ),
      _TimelineStep(
        label: 'Parent Approval',
        description: 'Waiting for parent response',
        icon: Icons.group,
      ),
      _TimelineStep(
        label: 'In Progress',
        description: 'Purchase in progress',
        icon: Icons.local_mall_outlined,
      ),
      _TimelineStep(
        label: 'Delivery',
        description: 'Awaiting delivery confirmation',
        icon: Icons.local_shipping,
      ),
      _TimelineStep(
        label: 'Completed',
        description: 'Reward delivered',
        icon: Icons.home_rounded,
      ),
    ];

    final currentIndex = _currentStepIndex();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Progress',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF27272a)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? Colors.white10
                  : Colors.grey[200]!,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                _TimelineRow(
                  step: steps[i],
                  state: i < currentIndex
                      ? _StepState.done
                      : i == currentIndex
                          ? _StepState.active
                          : _StepState.upcoming,
                  showConnector: i < steps.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _StepState { done, active, upcoming }

class _TimelineStep {
  final String label;
  final String description;
  final IconData icon;

  const _TimelineStep({
    required this.label,
    required this.description,
    required this.icon,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineStep step;
  final _StepState state;
  final bool showConnector;

  const _TimelineRow({
    required this.step,
    required this.state,
    required this.showConnector,
  });

  Color _color(BuildContext context) {
    switch (state) {
      case _StepState.done:
        return const Color(0xFFF97316);
      case _StepState.active:
        return const Color(0xFFF97316);
      case _StepState.upcoming:
        return Theme.of(context).textTheme.bodySmall!.color!
            .withOpacity(0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color(context);
    final isUpcoming = state == _StepState.upcoming;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: state == _StepState.done
                      ? color.withOpacity(0.15)
                      : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  step.icon,
                  size: 18,
                  color: color,
                ),
              ),
              if (showConnector)
                Container(
                  width: 2,
                  height: 28,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: isUpcoming ? Colors.grey[700] : color.withOpacity(0.4),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isUpcoming
                          ? theme.textTheme.bodyLarge?.color?.withOpacity(0.6)
                          : theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestDetailsCard extends StatelessWidget {
  final RewardRequestModel request;
  final String productName;
  final int pointsNeeded;

  const _RequestDetailsCard({
    required this.request,
    required this.productName,
    required this.pointsNeeded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final details = [
      _DetailTile(
        label: 'Order Date',
        value: reward_date_utils.DateUtils.formatDateTime(
          request.timestamps.requestedAt,
        ),
        icon: Icons.calendar_today,
      ),
      _DetailTile(
        label: 'Points Required',
        value: '${PointsCalculator.formatPoints(pointsNeeded)} pts',
        icon: Icons.workspace_premium_outlined,
      ),
      _DetailTile(
        label: 'Parent',
        value: request.parentId.isNotEmpty ? request.parentId : '—',
        icon: Icons.group,
      ),
      _DetailTile(
        label: 'Product ID',
        value: request.productSnapshot.productId,
        icon: Icons.qr_code_2_rounded,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272a) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey[200]!,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Request Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.8,
            ),
            itemCount: details.length,
            itemBuilder: (context, index) => details[index],
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1f1f23) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.textTheme.labelSmall?.color?.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final RewardRequestStatus status;

  const _StatusPill({required this.status});

  Color _color() {
    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        return const Color(0xFF2563EB);
      case RewardRequestStatus.approvedPurchaseInProgress:
        return const Color(0xFFF59E0B);
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return const Color(0xFF8B5CF6);
      case RewardRequestStatus.completed:
        return const Color(0xFF10B981);
      case RewardRequestStatus.expiredOrAutoResolved:
      case RewardRequestStatus.cancelled:
        return Colors.grey;
    }
  }

  String _label() {
    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        return 'Awaiting Parent Approval';
      case RewardRequestStatus.approvedPurchaseInProgress:
        return 'Order in Progress';
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

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _label(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
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
