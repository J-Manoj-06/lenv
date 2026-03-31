import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/parent_provider.dart';
import '../../models/reward_request_model.dart';
import '../../widgets/student_selection/student_avatar_row.dart';
import 'parent_reward_request_detail_screen.dart';
import 'parent_profile_screen.dart';

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

  String _filter =
      'all'; // all | pending | pendingPrice | approved | orderPlaced | rejected

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
        actions: [
          IconButton(
            icon: const Icon(Icons.person, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ParentProfileScreen(),
                ),
              );
            },
          ),
        ],
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
    final selectedUid = selectedChild?.uid;
    final selectedStudentId = selectedChild?.studentId;
    // Filter requests to show only those for current selected child
    final childRequests = parentProvider.rewardRequests
        .where(
          (r) =>
              r.studentId == selectedUid ||
              (selectedStudentId != null &&
                  selectedStudentId.isNotEmpty &&
                  r.studentId == selectedStudentId),
        )
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
          _buildPointsHeader(isDark, selectedUid, selectedChild?.name ?? ''),
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
          return r.status == RewardRequestStatus.pending ||
              r.status == RewardRequestStatus.requested;
        case 'pendingPrice':
          return r.status == RewardRequestStatus.pendingPrice;
        case 'approved':
          return r.status == RewardRequestStatus.approved ||
              r.status == RewardRequestStatus.orderPlaced ||
              r.status == RewardRequestStatus.delivered;
        case 'orderPlaced':
          return r.status == RewardRequestStatus.orderPlaced ||
              r.status == RewardRequestStatus.delivered;
        case 'rejected':
          return r.status == RewardRequestStatus.rejected;
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildPointsHeader(bool isDark, String? childUid, String childName) {
    if (childUid == null || childUid.isEmpty) {
      return _buildPointsHeaderCard(isDark, 0, childName);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('student_rewards')
          .where('studentId', isEqualTo: childUid)
          .snapshots(),
      builder: (context, snapshot) {
        int totalEarned = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final points = doc.data()['pointsEarned'];
            if (points is num) totalEarned += points.toInt();
          }
        }
        return _buildPointsHeaderCard(
          isDark,
          totalEarned < 0 ? 0 : totalEarned,
          childName,
        );
      },
    );
  }

  Widget _buildPointsHeaderCard(bool isDark, int points, String childName) {
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
      {'label': 'Pending Price', 'value': 'pendingPrice'},
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
            if (r.status == RewardRequestStatus.pending ||
                r.status == RewardRequestStatus.requested)
              _buildActionRow(isDark, r, provider),
            if (r.status == RewardRequestStatus.pendingPrice)
              _buildEnterPriceRow(isDark, r, provider),
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
                : () => _confirmApprove(r, provider),
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

  Widget _buildEnterPriceRow(
    bool isDark,
    RewardRequestModel r,
    ParentProvider provider,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: provider.isLoadingRewards
            ? null
            : () => _showPriceEntryDialog(
                requestId: r.id,
                provider: provider,
                isEnterPriceLaterFlow: true,
                maxAvailablePoints: provider.selectedChild?.rewardPoints,
              ),
        icon: const Icon(Icons.currency_rupee, size: 18),
        label: const Text('Enter Price'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
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

  Future<void> _confirmApprove(
    RewardRequestModel request,
    ParentProvider provider,
  ) async {
    final method = await showDialog<String>(
      context: context,
      builder: (c) {
        final isDark = Theme.of(c).brightness == Brightness.dark;
        return _ApproveMethodDialog(
          isDark: isDark,
          headerIcon: Icons.verified_rounded,
          headerTitle: 'Approve Reward',
          headerSubtitle: 'How will this reward be purchased?',
          options: [
            _ApprovalOption(
              icon: Icons.open_in_new_rounded,
              title: 'Buy Through Product Link',
              subtitle: 'Approve & open purchase link',
              accentColor: parentGreen,
              value: 'link',
            ),
            _ApprovalOption(
              icon: Icons.storefront_rounded,
              title: 'Order Manually',
              subtitle: 'Complete purchase outside the app',
              accentColor: Colors.orange,
              value: 'manual',
            ),
          ],
          onSelect: (v) => Navigator.pop(c, v),
          onCancel: () => Navigator.pop(c),
        );
      },
    );

    if (!mounted || method == null) return;

    if (method == 'link') {
      final result = await provider.approveRewardByLink(request.id);
      if (!mounted) return;
      if (result['success'] == true) {
        // Navigate to detail screen so parent can view the product and tap Open Product Link
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ParentRewardRequestDetailScreen(request: request),
          ),
        );
      } else {
        _showResultSnackBar(result);
      }
      return;
    }

    final manualWhen = await showDialog<String>(
      context: context,
      builder: (c) {
        final isDark = Theme.of(c).brightness == Brightness.dark;
        return _ApproveMethodDialog(
          isDark: isDark,
          headerIcon: Icons.shopping_bag_rounded,
          headerTitle: 'Manual Order',
          headerSubtitle: 'When will you enter the purchase price?',
          options: [
            _ApprovalOption(
              icon: Icons.currency_rupee_rounded,
              title: 'Enter Price Now',
              subtitle: 'Deduct points immediately',
              accentColor: parentGreen,
              value: 'now',
            ),
            _ApprovalOption(
              icon: Icons.schedule_rounded,
              title: 'Enter Price Later',
              subtitle: 'Mark as pending price entry',
              accentColor: Colors.orange,
              value: 'later',
            ),
          ],
          onSelect: (v) => Navigator.pop(c, v),
          onCancel: () => Navigator.pop(c),
        );
      },
    );

    if (!mounted || manualWhen == null) return;
    if (manualWhen == 'later') {
      final result = await provider.markRewardPendingPrice(request.id);
      if (!mounted) return;
      _showResultSnackBar(result);
      return;
    }

    await _showPriceEntryDialog(
      requestId: request.id,
      provider: provider,
      isEnterPriceLaterFlow: false,
      maxAvailablePoints: provider.selectedChild?.rewardPoints,
    );
  }

  Future<void> _showPriceEntryDialog({
    required String requestId,
    required ParentProvider provider,
    required bool isEnterPriceLaterFlow,
    int? maxAvailablePoints,
  }) async {
    final enteredPrice = await showDialog<double>(
      context: context,
      builder: (c) =>
          _ManualPriceDialog(maxAvailablePoints: maxAvailablePoints),
    );

    if (enteredPrice == null || !mounted) {
      return;
    }

    Map<String, dynamic> result;
    if (isEnterPriceLaterFlow) {
      result = await provider.enterRewardPriceLater(
        requestId: requestId,
        price: enteredPrice,
      );
    } else {
      result = await provider.approveRewardManualNow(
        requestId: requestId,
        price: enteredPrice,
      );
    }

    if (!mounted) return;
    _showResultSnackBar(result);
  }

  void _showResultSnackBar(Map<String, dynamic> result) {
    final success = result['success'] as bool? ?? false;
    final message =
        result['message'] as String? ?? (success ? 'Success' : 'Failed');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? parentGreen : Colors.red,
      ),
    );
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
      case RewardRequestStatus.requested:
        return const _StatusVisual(
          'REQUESTED',
          Color(0xFFF5A623),
          Icons.hourglass_bottom,
        );
      case RewardRequestStatus.pending:
        return const _StatusVisual(
          'PENDING',
          Colors.orange,
          Icons.hourglass_top,
        );
      case RewardRequestStatus.pendingPrice:
        return const _StatusVisual(
          'PENDING PRICE',
          Colors.deepOrange,
          Icons.currency_rupee,
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
      case RewardRequestStatus.delivered:
        return const _StatusVisual('DELIVERED', Colors.teal, Icons.inventory_2);
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

class _ManualPriceDialog extends StatefulWidget {
  final int? maxAvailablePoints;

  const _ManualPriceDialog({this.maxAvailablePoints});

  @override
  State<_ManualPriceDialog> createState() => _ManualPriceDialogState();
}

class _ManualPriceDialogState extends State<_ManualPriceDialog> {
  final TextEditingController _priceController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  double _livePrice = 0;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _livePrice.round();
    final maxAvailablePoints = widget.maxAvailablePoints;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summaryBg = isDark
        ? const Color(0xFF1E6B4B)
        : _ParentRewardsScreenState.parentGreen.withOpacity(0.10);
    final summaryTextColor = isDark ? Colors.white : const Color(0xFF1F2937);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Enter Purchase Price'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid price greater than zero';
                  }
                  final enteredPoints = parsed.round();
                  if (maxAvailablePoints != null &&
                      enteredPoints > maxAvailablePoints) {
                    return 'Enter a price up to $maxAvailablePoints points';
                  }
                  return null;
                },
                onChanged: (value) {
                  final parsed = double.tryParse(value.trim()) ?? 0;
                  setState(() {
                    _livePrice = parsed;
                  });
                },
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: summaryBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _ParentRewardsScreenState.parentGreen.withOpacity(
                      isDark ? 0.65 : 0.22,
                    ),
                    width: 1,
                  ),
                ),
                child: Text(
                  'Price: ₹${_livePrice.toStringAsFixed(2)}\nPoints to Deduct: $points${maxAvailablePoints != null ? '\nAvailable Points: $maxAvailablePoints' : ''}',
                  style: TextStyle(
                    color: summaryTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              final parsed = double.tryParse(_priceController.text.trim()) ?? 0;
              Navigator.pop(context, parsed);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _ParentRewardsScreenState.parentGreen,
          ),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _StatusVisual {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusVisual(this.label, this.color, this.icon);
}

// ─────────────────────────────────────────────
// Approve-method dialog (shared helper)
// ─────────────────────────────────────────────

class _ApprovalOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final String value;
  const _ApprovalOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.value,
  });
}

class _ApproveMethodDialog extends StatelessWidget {
  final bool isDark;
  final IconData headerIcon;
  final String headerTitle;
  final String headerSubtitle;
  final List<_ApprovalOption> options;
  final void Function(String) onSelect;
  final VoidCallback onCancel;

  const _ApproveMethodDialog({
    required this.isDark,
    required this.headerIcon,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.options,
    required this.onSelect,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Gradient header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF14A670), const Color(0xFF0D7A52)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(headerIcon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headerSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Option cards ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: options.map((opt) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ApprovalOptionCard(
                    option: opt,
                    isDark: isDark,
                    onTap: () => onSelect(opt.value),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Cancel button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: subtitleColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalOptionCard extends StatelessWidget {
  final _ApprovalOption option;
  final bool isDark;
  final VoidCallback onTap;

  const _ApprovalOptionCard({
    required this.option,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252525) : const Color(0xFFF9F9F9);
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: option.accentColor.withOpacity(isDark ? 0.4 : 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: option.accentColor.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      option.accentColor.withOpacity(0.18),
                      option.accentColor.withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(option.icon, color: option.accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.subtitle,
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                  ],
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: option.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: option.accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
