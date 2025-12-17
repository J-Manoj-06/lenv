import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../rewards_module.dart';
import '../../models/reward_request_model.dart';
import '../../providers/rewards_providers.dart';
import '../widgets/request_card.dart';
import '../widgets/rewards_top_switcher.dart';

class StudentRequestsScreen extends ConsumerStatefulWidget {
  final String studentId;

  const StudentRequestsScreen({super.key, required this.studentId});

  @override
  ConsumerState<StudentRequestsScreen> createState() =>
      _StudentRequestsScreenState();
}

class _StudentRequestsScreenState extends ConsumerState<StudentRequestsScreen> {
  RewardRequestStatus? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(studentRequestsProvider(widget.studentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Requests'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          RewardsTopSwitcher(
            isCatalogActive: false,
            studentId: widget.studentId,
          ),
          // Status Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatusFilterChip(
                    label: 'All',
                    isSelected: _selectedStatus == null,
                    onPressed: () {
                      setState(() => _selectedStatus = null);
                    },
                  ),
                  const SizedBox(width: 10),
                  _StatusFilterChip(
                    label: 'Pending',
                    isSelected:
                        _selectedStatus ==
                        RewardRequestStatus.pendingParentApproval,
                    onPressed: () {
                      setState(
                        () => _selectedStatus =
                            RewardRequestStatus.pendingParentApproval,
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  _StatusFilterChip(
                    label: 'In Progress',
                    isSelected:
                        _selectedStatus ==
                        RewardRequestStatus.approvedPurchaseInProgress,
                    onPressed: () {
                      setState(
                        () => _selectedStatus =
                            RewardRequestStatus.approvedPurchaseInProgress,
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  _StatusFilterChip(
                    label: 'Delivery',
                    isSelected:
                        _selectedStatus ==
                        RewardRequestStatus.awaitingDeliveryConfirmation,
                    onPressed: () {
                      setState(
                        () => _selectedStatus =
                            RewardRequestStatus.awaitingDeliveryConfirmation,
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  _StatusFilterChip(
                    label: 'Completed',
                    isSelected:
                        _selectedStatus == RewardRequestStatus.completed,
                    onPressed: () {
                      setState(
                        () => _selectedStatus = RewardRequestStatus.completed,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Requests List
          Expanded(
            child: requestsAsync.when(
              data: (requests) {
                // Filter by selected status
                var filteredRequests = requests;
                if (_selectedStatus != null) {
                  filteredRequests = requests
                      .where((r) => r.status == _selectedStatus)
                      .toList();
                }

                if (filteredRequests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedStatus == null
                              ? 'No requests yet'
                              : 'No ${_getStatusLabel(_selectedStatus!)} requests',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start exploring rewards!',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: filteredRequests.length,
                  itemBuilder: (context, index) {
                    final request = filteredRequests[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: RequestCard(
                        request: request,
                        onTapped: () {
                          RewardsModule.navigateToRequestDetail(
                            context,
                            requestId: request.requestId,
                            request: request,
                          );
                        },
                        actionLabel: _getActionLabel(request.status),
                        onActionPressed: () => _handleAction(context, request),
                      ),
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          RewardsModule.navigateToCatalog(context);
        },
        backgroundColor: const Color(0xFFF2800D),
        elevation: 3,
        icon: const Icon(Icons.card_giftcard, size: 20),
        label: const Text(
          'Browse Rewards',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  String _getStatusLabel(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.pendingParentApproval:
        return 'Pending Approval';
      case RewardRequestStatus.approvedPurchaseInProgress:
        return 'In Progress';
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

  String _getActionLabel(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.awaitingDeliveryConfirmation:
        return 'Confirm Receipt';
      case RewardRequestStatus.completed:
        return 'View Details';
      default:
        return 'View Status';
    }
  }

  void _handleAction(BuildContext context, RewardRequestModel request) {
    RewardsModule.navigateToRequestDetail(
      context,
      requestId: request.requestId,
      request: request,
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _StatusFilterChip({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF2800D).withOpacity(0.12)
                : (isDark ? Colors.grey[800] : Colors.grey[100]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isSelected
                  ? const Color(0xFFF2800D)
                  : (isDark ? Colors.grey[300] : Colors.grey[700]),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
