import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/reward_request_model.dart';
import '../../providers/rewards_providers.dart';
import '../widgets/request_card.dart';

class ParentDashboardScreen extends ConsumerStatefulWidget {
  final String parentId;

  const ParentDashboardScreen({super.key, required this.parentId});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends ConsumerState<ParentDashboardScreen> {
  bool _showPendingOnly = true;

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(parentRequestsProvider(widget.parentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Rewards'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Toggle for Pending/All
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _showPendingOnly = true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _showPendingOnly
                              ? const Color(0xFFF2800D)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'Pending Action',
                            style: TextStyle(
                              color: _showPendingOnly
                                  ? Colors.white
                                  : Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _showPendingOnly = false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_showPendingOnly
                              ? const Color(0xFFF2800D)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'All Requests',
                            style: TextStyle(
                              color: !_showPendingOnly
                                  ? Colors.white
                                  : Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Requests List
          Expanded(
            child: requestsAsync.when(
              data: (requests) {
                // Filter pending if needed
                var filteredRequests = requests;
                if (_showPendingOnly) {
                  filteredRequests = requests
                      .where(
                        (r) =>
                            r.status ==
                            RewardRequestStatus.pendingParentApproval,
                      )
                      .toList();
                }

                if (filteredRequests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _showPendingOnly
                              ? 'No pending requests'
                              : 'No requests',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showPendingOnly
                              ? 'Your students\' requests will appear here'
                              : 'All requests will appear here',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                // Group by student or status
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: filteredRequests.length,
                  itemBuilder: (context, index) {
                    final request = filteredRequests[index];
                    final isPending =
                        request.status ==
                        RewardRequestStatus.pendingParentApproval;

                    return RequestCard(
                      request: request,
                      onTapped: () {
                        context.push(
                          '/rewards/request/${request.requestId}',
                          extra: request,
                        );
                      },
                      actionLabel: isPending
                          ? 'Review Request'
                          : 'View Details',
                      onActionPressed: () {
                        context.push(
                          '/rewards/request/${request.requestId}',
                          extra: request,
                        );
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
