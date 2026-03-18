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
      case RewardRequestStatus.requested:
        return 'Requested';
      case RewardRequestStatus.pending:
        return 'Pending Approval';
      case RewardRequestStatus.pendingPrice:
        return 'Pending Price';
      case RewardRequestStatus.approved:
        return 'Approved';
      case RewardRequestStatus.orderPlaced:
        return 'Order Placed';
      case RewardRequestStatus.delivered:
        return 'Delivered';
      case RewardRequestStatus.rejected:
        return 'Rejected';
    }
  }

  Color _statusColor(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.requested:
        return const Color(0xFFF59E0B);
      case RewardRequestStatus.pending:
        return const Color(0xFFF2800D);
      case RewardRequestStatus.pendingPrice:
        return const Color(0xFFEA580C);
      case RewardRequestStatus.approved:
        return const Color(0xFF16A34A);
      case RewardRequestStatus.orderPlaced:
        return const Color(0xFF0EA5E9);
      case RewardRequestStatus.delivered:
        return const Color(0xFF0D9488);
      case RewardRequestStatus.rejected:
        return const Color(0xFFEF4444);
    }
  }

  Future<void> _handleApprove() async {
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);
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

    setState(() => _isLoading = true);
    Map<String, dynamic> result;

    if (method == 'link') {
      result = await parentProvider.approveRewardByLink(widget.request.id);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showResultSnackBar(result);
      // Navigate to product link after approval
      if (result['success'] == true &&
          widget.request.amazonLink.trim().isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _openLink(widget.request.amazonLink);
      }
      return;
    } else {
      final timing = await showDialog<String>(
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
                subtitle: 'Mark request as pending price',
                accentColor: Colors.orange,
                value: 'later',
              ),
            ],
            onSelect: (v) => Navigator.pop(c, v),
            onCancel: () => Navigator.pop(c),
          );
        },
      );

      if (!mounted || timing == null) {
        setState(() => _isLoading = false);
        return;
      }

      if (timing == 'later') {
        result = await parentProvider.markRewardPendingPrice(widget.request.id);
      } else {
        setState(() => _isLoading = false);
        await _showEnterPriceDialog(isEnterLaterFlow: false);
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    _showResultSnackBar(result);
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

  Future<void> _showEnterPriceDialog({required bool isEnterLaterFlow}) async {
    final provider = Provider.of<ParentProvider>(context, listen: false);
    final priceController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Enter Purchase Price'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final price = double.tryParse((value ?? '').trim());
                  if (price == null || price <= 0) {
                    return 'Enter valid price greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: priceController,
                builder: (context, value, _) {
                  final price = double.tryParse(value.text.trim()) ?? 0;
                  final points = price.round();
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: parentGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Price: ₹${price.toStringAsFixed(2)}\nPoints to Deduct: $points',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                },
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
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(c, true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: parentGreen),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      priceController.dispose();
      return;
    }

    final price = double.tryParse(priceController.text.trim()) ?? 0;
    priceController.dispose();

    setState(() => _isLoading = true);
    final result = isEnterLaterFlow
        ? await provider.enterRewardPriceLater(
            requestId: widget.request.id,
            price: price,
          )
        : await provider.approveRewardManualNow(
            requestId: widget.request.id,
            price: price,
          );

    if (!mounted) return;
    setState(() => _isLoading = false);
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

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    // Ensure the URL has a scheme
    final raw = url.trim();
    final withScheme = (raw.startsWith('http://') || raw.startsWith('https://'))
        ? raw
        : 'https://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasAuthority) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid product link')));
      }
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open product link')),
        );
      }
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

                    // Status Timeline (after request submission)
                    if (request.status != RewardRequestStatus.requested &&
                        request.status != RewardRequestStatus.pending)
                      _buildStatusTimeline(isDark, request),

                    if (request.status != RewardRequestStatus.requested &&
                        request.status != RewardRequestStatus.pending)
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
    final isOrderPlaced =
        request.status == RewardRequestStatus.orderPlaced ||
        request.status == RewardRequestStatus.delivered;
    final isApproved =
        request.status == RewardRequestStatus.approved ||
        request.status == RewardRequestStatus.orderPlaced ||
        request.status == RewardRequestStatus.delivered;

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
                : (request.status == RewardRequestStatus.pendingPrice
                      ? 'Pending price entry'
                      : 'Pending'),
            isCompleted: isApproved,
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

        // Approve/Reject Buttons (if requested/pending)
        if (request.status == RewardRequestStatus.pending ||
            request.status == RewardRequestStatus.requested) ...[
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

        if (request.status == RewardRequestStatus.pendingPrice) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _showEnterPriceDialog(isEnterLaterFlow: true),
              icon: const Icon(Icons.currency_rupee),
              label: const Text('Enter Price'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
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

// ─────────────────────────────────────────────
// Approve-method dialog
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
          // Gradient header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF14A670), Color(0xFF0D7A52)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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

          // Option cards
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

          // Cancel button
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
