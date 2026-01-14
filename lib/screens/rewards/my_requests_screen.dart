import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/reward_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/reward_request_service.dart';

class MyRewardRequestsScreen extends StatefulWidget {
  const MyRewardRequestsScreen({super.key});

  @override
  State<MyRewardRequestsScreen> createState() => _MyRewardRequestsScreenState();
}

class _MyRewardRequestsScreenState extends State<MyRewardRequestsScreen> {
  final RewardRequestService _rewardService = RewardRequestService();

  Color _statusColor(RewardRequestStatus s) {
    switch (s) {
      case RewardRequestStatus.pending:
        return const Color(0xFF1777FF);
      case RewardRequestStatus.approved:
        return const Color(0xFF16A34A);
      case RewardRequestStatus.orderPlaced:
        return const Color(0xFF0EA5E9);
      case RewardRequestStatus.rejected:
        return const Color(0xFFEF4444);
    }
  }

  String _statusText(RewardRequestStatus s) {
    switch (s) {
      case RewardRequestStatus.pending:
        return 'Pending Approval';
      case RewardRequestStatus.approved:
        return 'Approved – Waiting for Order';
      case RewardRequestStatus.orderPlaced:
        return 'Order Placed';
      case RewardRequestStatus.rejected:
        return 'Rejected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final studentId = auth.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('My Requests'), centerTitle: true),
      body: StreamBuilder<List<RewardRequestModel>>(
        stream: FirestoreService().getRewardRequestsForStudent(studentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('No requests yet'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final r = items[i];
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title with delete button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              r.productName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Colors.red.shade400,
                              size: 24,
                            ),
                            onPressed: () => _confirmDeleteReward(r),
                            tooltip: 'Delete',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Points and price
                      Text(
                        '${r.pointsRequired} pts • ₹${r.price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(r.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          _statusText(r.status),
                          style: TextStyle(
                            color: _statusColor(r.status),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // Action button if needed
                      if (r.status == RewardRequestStatus.approved ||
                          r.status == RewardRequestStatus.orderPlaced)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildTrailing(context, r),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTrailing(BuildContext context, RewardRequestModel r) {
    if (r.status == RewardRequestStatus.approved) {
      return TextButton(
        onPressed: () async {
          final url = Uri.tryParse(r.amazonLink);
          if (url != null) launchUrl(url, mode: LaunchMode.externalApplication);
        },
        child: const Text('Open Link'),
      );
    }
    if (r.status == RewardRequestStatus.orderPlaced) {
      return const Icon(Icons.check_circle, color: Color(0xFF16A34A));
    }
    return const SizedBox.shrink();
  }

  Future<void> _confirmDeleteReward(RewardRequestModel request) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Reward Request?'),
          content: Text(
            'Are you sure you want to delete "${request.productName}"?\n\nThis action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && mounted) {
      await _deleteRewardRequest(request);
    }
  }

  Future<void> _deleteRewardRequest(RewardRequestModel request) async {
    try {
      await _rewardService.deleteRewardRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reward request deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
