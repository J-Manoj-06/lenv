import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/reward_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

class MyRewardRequestsScreen extends StatelessWidget {
  const MyRewardRequestsScreen({super.key});

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
                child: ListTile(
                  title: Text(
                    r.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        '${r.pointsRequired} pts • ₹${r.price.toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 4),
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
                    ],
                  ),
                  trailing: _buildTrailing(context, r),
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
}
