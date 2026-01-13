import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/parent_provider.dart';
import '../../models/reward_request_model.dart';
import '../../widgets/student_selection/student_avatar_row.dart';

class ParentRewardsScreen extends StatefulWidget {
  const ParentRewardsScreen({super.key});

  @override
  State<ParentRewardsScreen> createState() => _ParentRewardsScreenState();
}

class _ParentRewardsScreenState extends State<ParentRewardsScreen> {
  static const Color parentGreen = Color(0xFF14A670);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  String _filter = 'all'; // all | pending | approved | orderPlaced | rejected

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      appBar: AppBar(
        title: const Text('Rewards', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? backgroundDark : Colors.white,
        foregroundColor: isDark ? Colors.white : textPrimary,
        elevation: 0.5,
      ),
      body: Consumer<ParentProvider>(
        builder: (context, parentProvider, _) {
          if (!parentProvider.hasChildren) {
            return _buildEmpty(isDark, 'No children found');
          }

          return Column(
            children: [
              // ✅ NEW: Student selection row
              const StudentAvatarRow(),

              // Main content
              Expanded(
                child: parentProvider.isLoadingRewards
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(parentGreen),
                        ),
                      )
                    : _buildRewardsContent(context, isDark, parentProvider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRewardsContent(
    BuildContext context,
    bool isDark,
    ParentProvider parentProvider,
  ) {
    final selectedChild = parentProvider.selectedChild;
    final points = selectedChild?.rewardPoints ?? 0;
    final requests = _filtered(parentProvider.rewardRequests);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () => parentProvider.refresh(),
      color: parentGreen,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildPointsHeader(isDark, points, selectedChild?.name ?? ''),
          _buildFilterRow(isDark),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
              child: _buildEmpty(isDark, 'No reward requests'),
            )
          else
            ...requests.map(
              (r) => _buildRequestCard(isDark, r, parentProvider),
            ),
        ],
      ),
    );
  }

  List<RewardRequestModel> _filtered(List<RewardRequestModel> all) {
    if (_filter == 'all') return all;
    return all.where((r) {
      switch (_filter) {
        case 'pending':
          return r.status == RewardRequestStatus.pending;
        case 'approved':
          return r.status == RewardRequestStatus.approved;
        case 'orderPlaced':
          return r.status == RewardRequestStatus.orderPlaced;
        case 'rejected':
          return r.status == RewardRequestStatus.rejected;
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildPointsHeader(bool isDark, int points, String childName) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14A670), Color(0xFF0F8A5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: parentGreen.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.stars, color: Colors.white, size: 34),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reward Points',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  points.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (childName.isNotEmpty)
                  Text(
                    childName.split(' ').first,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(bool isDark) {
    final filters = <Map<String, String>>[
      {'label': 'All', 'value': 'all'},
      {'label': 'Pending', 'value': 'pending'},
      {'label': 'Approved', 'value': 'approved'},
      {'label': 'Ordered', 'value': 'orderPlaced'},
      {'label': 'Rejected', 'value': 'rejected'},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: filters.map((f) {
          final selected = _filter == f['value'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f['label']!),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f['value']!),
              backgroundColor: isDark
                  ? const Color(0xFF1F1A2D)
                  : Colors.grey[200],
              selectedColor: parentGreen.withOpacity(0.2),
              labelStyle: TextStyle(
                color: selected
                    ? parentGreen
                    : (isDark ? Colors.white : textPrimary),
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: selected ? parentGreen : Colors.transparent,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRequestCard(
    bool isDark,
    RewardRequestModel r,
    ParentProvider provider,
  ) {
    final statusData = _statusVisual(r.status);
    final dateStr = DateFormat('MMM dd, yyyy').format(r.requestedOn);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1A2D) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.withOpacity(0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusData.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusData.icon, color: statusData.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.productName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.stars, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${r.pointsRequired} pts',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusData.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusData.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusData.color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (r.status == RewardRequestStatus.pending)
            _buildActionRow(isDark, r, provider),
          if (r.status == RewardRequestStatus.approved && r.approvedOn != null)
            _buildStatusFooter(isDark, 'Approved', r.approvedOn!, Colors.green),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    bool isDark,
    RewardRequestModel r,
    ParentProvider provider,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: provider.isLoadingRewards
                ? null
                : () => _confirmReject(r.id, provider),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: provider.isLoadingRewards
                ? null
                : () => _confirmApprove(r.id, provider),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: parentGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusFooter(
    bool isDark,
    String label,
    DateTime date,
    Color color,
  ) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$label on ${DateFormat('MMM dd, yyyy').format(date)}',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmApprove(String id, ParentProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Approve Reward'),
        content: const Text('Approve this reward request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: parentGreen),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final success = await provider.approveRewardRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Approved' : 'Approval failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmReject(String id, ParentProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject Reward'),
        content: const Text('Reject this reward request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final success = await provider.rejectRewardRequest(id, null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Rejected' : 'Rejection failed'),
          backgroundColor: success ? Colors.orange : Colors.red,
        ),
      );
    }
  }

  Widget _buildEmpty(bool isDark, String msg) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.card_giftcard,
          size: 64,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
        const SizedBox(height: 16),
        Text(
          msg,
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  _StatusVisual _statusVisual(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.pending:
        return const _StatusVisual(
          'PENDING',
          Colors.orange,
          Icons.hourglass_top,
        );
      case RewardRequestStatus.approved:
        return const _StatusVisual(
          'APPROVED',
          Colors.green,
          Icons.check_circle,
        );
      case RewardRequestStatus.orderPlaced:
        return const _StatusVisual(
          'ORDERED',
          Colors.blue,
          Icons.local_shipping,
        );
      case RewardRequestStatus.rejected:
        return const _StatusVisual('REJECTED', Colors.red, Icons.cancel);
    }
  }
}

class _StatusVisual {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusVisual(this.label, this.color, this.icon);
}
