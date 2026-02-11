import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/parent_provider.dart';
import '../../models/reward_request_model.dart';
import '../../widgets/student_selection/student_avatar_row.dart';
import 'parent_reward_request_detail_screen.dart';

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
        title: const Text(
          'Rewards',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? backgroundDark : Colors.white,
        foregroundColor: isDark ? Colors.white : textPrimary,
        elevation: 0.5,
        automaticallyImplyLeading: false,
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
    // Filter requests to show only those for current selected child
    final childRequests = parentProvider.rewardRequests
        .where((r) => r.studentId == selectedChild?.uid)
        .toList();
    final requests = _filtered(childRequests);
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

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ParentRewardRequestDetailScreen(request: r),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
                  child: Icon(
                    statusData.icon,
                    color: statusData.color,
                    size: 24,
                  ),
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
                          const Icon(
                            Icons.stars,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${r.pointsRequired} pts',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _confirmDeleteRequest(r, provider),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
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
              ],
            ),
            const SizedBox(height: 14),
            if (r.status == RewardRequestStatus.pending)
              _buildActionRow(isDark, r, provider),
            if (r.status == RewardRequestStatus.approved &&
                r.approvedOn != null)
              _buildStatusFooter(
                isDark,
                'Approved',
                r.approvedOn!,
                Colors.green,
              ),
          ],
        ),
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
    // Show method selection dialog
    final method = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Choose Purchase Method'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How would you like to fulfill this reward?'),
              const SizedBox(height: 16),
              // Amazon Option
              InkWell(
                onTap: () => Navigator.pop(c, 'amazon'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shopping_cart, color: Colors.orange[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Amazon Affiliate',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Order via Amazon link',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Manual Option
              InkWell(
                onTap: () => Navigator.pop(c, 'manual'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.store, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Manual Purchase',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Buy locally or from other store',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (method == null) return;

    if (method == 'amazon') {
      await _approveViaAmazon(id, provider);
    } else if (method == 'manual') {
      await _showManualPriceDialog(id, provider);
    }
  }

  Future<void> _approveViaAmazon(String id, ParentProvider provider) async {
    final success = await provider.approveRewardRequestWithMethod(
      requestId: id,
      approvalMethod: 'amazon',
    );

    if (!mounted) return;

    if (success) {
      // Show confirmation dialog with Amazon link
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('✓ Approved via Amazon'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Request approved! Click below to complete the purchase:',
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    // TODO: Launch Amazon URL
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Amazon link feature coming soon!'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  },
                  icon: const Icon(Icons.shopping_bag),
                  label: const Text('Open Amazon'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(double.infinity, 45),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approval failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showManualPriceDialog(
    String id,
    ParentProvider provider,
  ) async {
    final priceController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enter Purchase Price'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How much did you pay for this reward?'),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                  hintText: 'Enter amount',
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final price = double.tryParse(priceController.text);
              if (price == null || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid price'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(c, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: parentGreen),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final price = double.tryParse(priceController.text);
      priceController.dispose();

      if (price != null && price > 0) {
        final success = await provider.approveRewardRequestWithMethod(
          requestId: id,
          approvalMethod: 'manual',
          manualPrice: price,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✓ Approved! Manual purchase: ₹${price.toStringAsFixed(2)}'
                  : 'Approval failed',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } else {
      priceController.dispose();
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

  Future<void> _confirmDeleteRequest(
    RewardRequestModel request,
    ParentProvider provider,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete reward request?'),
          content: Text(
            'This will permanently remove "${request.productName}" from the requests list.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && mounted) {
      final success = await provider.deleteRewardRequest(request.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Reward request deleted' : 'Failed to delete request',
          ),
          backgroundColor: success ? parentGreen : Colors.red,
        ),
      );
    }
  }
}

class _StatusVisual {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusVisual(this.label, this.color, this.icon);
}
