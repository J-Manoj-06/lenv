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
  static const Color parentGreen = Color(0xFF14A670);

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
    final parentProvider = Provider.of<ParentProvider>(context);
    final statusColor = _statusColor(request.status);
    final studentName = _resolveStudentName(request, parentProvider);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          // Gradient AppBar
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF14A670), Color(0xFF0D7C52)],
                ),
              ),
              child: FlexibleSpaceBar(
                centerTitle: true,
                title: Text(
                  'Reward Request',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.3),
                        offset: const Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
                titlePadding: const EdgeInsets.only(bottom: 16),
              ),
            ),
          ),

          // Content
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Card with Image and Info
                    _buildProductCard(isDark, request, statusColor),

                    const SizedBox(height: 20),

                    // Reward Details Section
                    _buildDetailsSection(isDark, request, studentName),

                    const SizedBox(height: 20),

                    // Status Timeline (if approved or order placed)
                    if (request.status != RewardRequestStatus.pending)
                      _buildStatusTimeline(isDark, request),

                    if (request.status != RewardRequestStatus.pending)
                      const SizedBox(height: 20),

                    // Action Section
                    _buildActionSection(isDark, request),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // Product Card with Image and Name
  Widget _buildProductCard(
    bool isDark,
    RewardRequestModel request,
    Color statusColor,
  ) {
    final hasImage = request.productImageUrl.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image Section
          Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  parentGreen.withOpacity(0.1),
                  parentGreen.withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    child: Image.network(
                      request.productImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          Icons.card_giftcard,
                          size: 80,
                          color: parentGreen.withOpacity(0.6),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.card_giftcard,
                      size: 80,
                      color: parentGreen.withOpacity(0.6),
                    ),
                  ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status badge (top-right)
                Row(
                  children: [
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _statusLabel(request.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  request.productName,
                  textAlign: TextAlign.left,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Details Section with Icons
  Widget _buildDetailsSection(
    bool isDark,
    RewardRequestModel request,
    String studentName,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reward Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.person_outline,
            label: 'Student',
            value: studentName,
            isDark: isDark,
          ),
          _buildDivider(isDark),
          _DetailRow(
            icon: Icons.stars_outlined,
            label: 'Points Required',
            value: '${request.pointsRequired}',
            isDark: isDark,
          ),
          _buildDivider(isDark),
          _DetailRow(
            icon: Icons.payments_outlined,
            label: 'Price',
            value: '₹${request.price.toStringAsFixed(0)}',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  String _resolveStudentName(
    RewardRequestModel request,
    ParentProvider parentProvider,
  ) {
    final rawName = request.studentName.trim();
    if (rawName.isNotEmpty && rawName.toLowerCase() != 'unknown student') {
      return rawName;
    }

    for (final child in parentProvider.children) {
      if (child.uid == request.studentId ||
          child.studentId == request.studentId) {
        final resolvedName = child.name.trim();
        if (resolvedName.isNotEmpty) {
          return resolvedName;
        }
      }
    }

    if (rawName.isNotEmpty) {
      return rawName;
    }

    return 'Student';
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        color: isDark ? Colors.grey[800] : Colors.grey[200],
      ),
    );
  }

  // Status Timeline
  Widget _buildStatusTimeline(bool isDark, RewardRequestModel request) {
    final isOrderPlaced = request.status == RewardRequestStatus.orderPlaced;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status Timeline',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 20),
          _TimelineStep(
            icon: Icons.send,
            title: 'Requested',
            subtitle: _formatDate(request.requestedOn),
            isCompleted: true,
            isLast: false,
            isDark: isDark,
          ),
          _TimelineStep(
            icon: Icons.check_circle,
            title: 'Approved',
            subtitle: request.approvedOn != null
                ? _formatDate(request.approvedOn!)
                : 'Pending',
            isCompleted: request.status != RewardRequestStatus.pending,
            isLast: !isOrderPlaced,
            isDark: isDark,
          ),
          if (isOrderPlaced)
            _TimelineStep(
              icon: Icons.local_shipping,
              title: 'Ready for Delivery',
              subtitle: 'Order placed',
              isCompleted: true,
              isLast: true,
              isDark: isDark,
            ),
        ],
      ),
    );
  }

  // Action Section
  Widget _buildActionSection(bool isDark, RewardRequestModel request) {
    return Column(
      children: [
        // Open Product Link Button
        if (request.amazonLink.trim().isNotEmpty)
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF14A670), Color(0xFF0D7C52)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: parentGreen.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openLink(request.amazonLink),
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.open_in_new, color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Open Product Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Approve/Reject Buttons (if pending)
        if (request.status == RewardRequestStatus.pending) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red[400]!, width: 2),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading ? null : _handleReject,
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        child: _isLoading
                            ? SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.red[400],
                                  ),
                                ),
                              )
                            : Text(
                                'Reject',
                                style: TextStyle(
                                  color: Colors.red[400],
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF14A670), Color(0xFF0D7C52)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: parentGreen.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading ? null : _handleApprove,
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Approve',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

// Detail Row Widget with Icon
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF14A670).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF14A670)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Timeline Step Widget
class _TimelineStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isLast;
  final bool isDark;

  const _TimelineStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isCompleted,
    required this.isLast,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCompleted
                    ? const Color(0xFF14A670)
                    : (isDark ? Colors.grey[800] : Colors.grey[300]),
                shape: BoxShape.circle,
                boxShadow: isCompleted
                    ? [
                        BoxShadow(
                          color: const Color(0xFF14A670).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isCompleted ? Colors.white : Colors.grey[600],
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: isCompleted
                    ? const Color(0xFF14A670).withOpacity(0.5)
                    : (isDark ? Colors.grey[800] : Colors.grey[300]),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isCompleted
                        ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                        : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
