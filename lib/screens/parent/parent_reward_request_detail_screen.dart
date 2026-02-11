import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/reward_request_model.dart';
import '../../providers/parent_provider.dart';

class ParentRewardRequestDetailScreen extends StatefulWidget {
  final RewardRequestModel request;

  const ParentRewardRequestDetailScreen({super.key, required this.request});

  @override
  State<ParentRewardRequestDetailScreen> createState() =>
      _ParentRewardRequestDetailScreenState();
}

class _ParentRewardRequestDetailScreenState
    extends State<ParentRewardRequestDetailScreen> {
  bool _isLoading = false;

  String _statusLabel(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.pending:
        return 'Pending Approval';
      case RewardRequestStatus.approved:
        return 'Approved';
      case RewardRequestStatus.orderPlaced:
        return 'Order Placed';
      case RewardRequestStatus.rejected:
        return 'Rejected';
    }
  }

  Color _statusColor(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.pending:
        return const Color(0xFFF2800D);
      case RewardRequestStatus.approved:
        return const Color(0xFF16A34A);
      case RewardRequestStatus.orderPlaced:
        return const Color(0xFF0EA5E9);
      case RewardRequestStatus.rejected:
        return const Color(0xFFEF4444);
    }
  }

  Future<void> _handleApprove() async {
    setState(() => _isLoading = true);
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);
    final success = await parentProvider.approveRewardRequest(
      widget.request.id,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Reward request approved!' : 'Failed to approve request',
        ),
        backgroundColor: success ? const Color(0xFF14A670) : Colors.red[400],
      ),
    );
  }

  Future<void> _handleReject() async {
    setState(() => _isLoading = true);
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);
    final success = await parentProvider.rejectRewardRequest(
      widget.request.id,
      null,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Reward request rejected' : 'Failed to reject request',
        ),
        backgroundColor: success ? Colors.red[400] : Colors.red[400],
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final request = widget.request;
    final statusColor = _statusColor(request.status);

    return Scaffold(
      appBar: AppBar(title: const Text('Reward Request'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0 : 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          request.productName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusLabel(request.status),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Student', value: request.studentName),
                  _InfoRow(
                    label: 'Points Required',
                    value: '${request.pointsRequired}',
                  ),
                  _InfoRow(
                    label: 'Price',
                    value: '₹${request.price.toStringAsFixed(0)}',
                  ),
                  _InfoRow(
                    label: 'Requested On',
                    value: _formatDate(request.requestedOn),
                  ),
                  if (request.approvedOn != null)
                    _InfoRow(
                      label: 'Approved On',
                      value: _formatDate(request.approvedOn!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (request.amazonLink.trim().isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openLink(request.amazonLink),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Product Link'),
                ),
              ),
            const SizedBox(height: 16),
            if (request.status == RewardRequestStatus.pending)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _handleReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[400],
                        side: BorderSide(color: Colors.red[400]!),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14A670),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Approve'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
