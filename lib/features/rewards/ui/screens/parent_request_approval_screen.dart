import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/reward_request_model.dart';
import '../../providers/rewards_providers.dart';

class ParentRequestApprovalScreen extends ConsumerStatefulWidget {
  final String parentId;

  const ParentRequestApprovalScreen({super.key, required this.parentId});

  @override
  ConsumerState<ParentRequestApprovalScreen> createState() =>
      _ParentRequestApprovalScreenState();
}

class _ParentRequestApprovalScreenState
    extends ConsumerState<ParentRequestApprovalScreen> {
  RewardRequestStatus? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final requestsAsync = ref.watch(parentRequestsProvider(widget.parentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reward Requests'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark
            ? Theme.of(context).scaffoldBackgroundColor
            : Colors.transparent,
      ),
      body: requestsAsync.when(
        data: (requests) {
          final filteredRequests = _filterRequests(requests);

          if (filteredRequests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.card_giftcard, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No reward requests',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When your child requests rewards, they\'ll appear here.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: filteredRequests.length,
            itemBuilder: (context, index) {
              final request = filteredRequests[index];
              return _RequestCard(
                request: request,
                parentId: widget.parentId,
                onUpdated: () {
                  // Trigger rebuild
                  setState(() {});
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, st) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                'Error loading requests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Please try again',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<RewardRequestModel> _filterRequests(List<RewardRequestModel> requests) {
    if (_selectedStatus == null) return requests;
    return requests.where((r) => r.status == _selectedStatus).toList();
  }
}

class _RequestCard extends ConsumerWidget {
  final RewardRequestModel request;
  final String parentId;
  final VoidCallback onUpdated;

  const _RequestCard({
    required this.request,
    required this.parentId,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat(
      'MMM dd, yyyy',
    ).format(request.timestamps.requestedAt);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        request.productSnapshot.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: request.status),
                  ],
                ),
                const SizedBox(height: 8),

                // Date
                Text(
                  'Requested on $dateStr',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 0,
            color: isDark ? Colors.grey[800] : Colors.grey[200],
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  label: 'Points Required',
                  value: '${request.pointsData.required} points',
                  icon: Icons.card_giftcard,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: 'Price',
                  value:
                      '₹${request.productSnapshot.price.estimatedPrice.toStringAsFixed(0)}',
                  icon: Icons.shopping_bag,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Actions
          if (request.status == RewardRequestStatus.pendingParentApproval)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRejectDialog(context, ref),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showApproveDialog(context, ref),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14A670),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showApproveDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Approve Request?'),
        content: Text(
          'Approve "${request.productSnapshot.title}" for ${request.pointsData.required} points?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(c);
              await _approveRequest(context, ref);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14A670),
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject Request?'),
        content: Text('Reject "${request.productSnapshot.title}" request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(c);
              await _rejectRequest(context, ref);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _approveRequest(BuildContext context, WidgetRef ref) async {
    try {
      final repository = ref.read(rewardsRepositoryProvider);
      await repository.updateRequestStatus(
        requestId: request.requestId,
        newStatus: RewardRequestStatus.approvedPurchaseInProgress,
        userId: parentId,
        metadata: {'approvedAt': DateTime.now().toString()},
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Request approved!'),
          backgroundColor: Colors.green,
        ),
      );
      onUpdated();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectRequest(BuildContext context, WidgetRef ref) async {
    try {
      final repository = ref.read(rewardsRepositoryProvider);
      await repository.updateRequestStatus(
        requestId: request.requestId,
        newStatus: RewardRequestStatus.cancelled,
        userId: parentId,
        metadata: {'rejectedAt': DateTime.now().toString()},
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request rejected'),
          backgroundColor: Colors.orange,
        ),
      );
      onUpdated();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final RewardRequestStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        bgColor = Colors.orange.withOpacity(0.15);
        textColor = Colors.orange[700]!;
        label = 'Pending';
        break;
      case RewardRequestStatus.approvedPurchaseInProgress:
        bgColor = Colors.green.withOpacity(0.15);
        textColor = Colors.green[700]!;
        label = 'Approved';
        break;
      case RewardRequestStatus.cancelled:
        bgColor = Colors.red.withOpacity(0.15);
        textColor = Colors.red[700]!;
        label = 'Rejected';
        break;
      default:
        bgColor = Colors.blue.withOpacity(0.15);
        textColor = Colors.blue[700]!;
        label = status.displayName;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isDark;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ],
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.grey[100] : Colors.grey[900],
          ),
        ),
      ],
    );
  }
}
