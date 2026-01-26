import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/product_model.dart';
import '../../providers/rewards_providers.dart';
import '../../utils/points_calculator.dart';

const Color _primaryOrange = Color(0xFFF97316);

class RewardRequestScreen extends ConsumerStatefulWidget {
  final String productId;
  final String? studentId;

  const RewardRequestScreen({
    super.key,
    required this.productId,
    this.studentId,
  });

  @override
  ConsumerState<RewardRequestScreen> createState() =>
      _RewardRequestScreenState();
}

class _RewardRequestScreenState extends ConsumerState<RewardRequestScreen> {
  bool _isRequesting = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    print('🔵 RewardRequestScreen - productId: ${widget.productId}');
    print('🔵 RewardRequestScreen - studentId: ${widget.studentId}');

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F0F14)
          : const Color(0xFFF5F6F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Request Reward',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('rewards_catalog')
            .doc(widget.productId)
            .get(),
        builder: (context, snapshot) {
          print(
            '🔵 RewardRequestScreen - connectionState: ${snapshot.connectionState}',
          );

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          print('🔵 RewardRequestScreen - hasError: ${snapshot.hasError}');
          print('🔵 RewardRequestScreen - hasData: ${snapshot.hasData}');
          print('🔵 RewardRequestScreen - exists: ${snapshot.data?.exists}');

          if (snapshot.hasError) {
            print('🔴 RewardRequestScreen - error: ${snapshot.error}');
          }

          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Product not found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          print(
            '🟢 RewardRequestScreen - Found product data: ${data['title']}',
          );
          print('🟢 RewardRequestScreen - Data keys: ${data.keys.toList()}');

          final product = ProductModel.fromMap(data);
          print('🟢 RewardRequestScreen - Product parsed: ${product.title}');

          // Calculate points required
          final pointsRequired = PointsCalculator.calculatePointsRequired(
            price: product.price.estimatedPrice,
            pointsPerRupee: product.pointsRule.pointsPerRupee,
            maxPoints: product.pointsRule.maxPoints,
          );

          // Watch student points if studentId is available
          final studentPointsAsync =
              widget.studentId != null && widget.studentId!.isNotEmpty
              ? ref.watch(studentPointsProvider(widget.studentId!))
              : const AsyncValue.data(0.0);

          return studentPointsAsync.when(
            data: (studentPoints) {
              final userPoints = studentPoints.toInt();
              final remainingPoints = pointsRequired - userPoints;
              final isEligible = userPoints >= pointsRequired;

              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProductPreview(context, data, isDark),
                      const SizedBox(height: 24),
                      _buildEligibilityCard(
                        context,
                        pointsRequired,
                        userPoints,
                        remainingPoints,
                        isEligible,
                        isDark,
                      ),
                      const SizedBox(height: 24),
                      _buildConfirmButton(
                        context,
                        product,
                        pointsRequired,
                        isEligible,
                        remainingPoints,
                        isDark,
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, st) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Unable to load points',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductPreview(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final title = data['title'] ?? 'Product';
    final images = data['images'] as List?;
    final imageUrl = images != null && images.isNotEmpty
        ? images[0]['url'] as String?
        : data['image_url'] as String?;

    final price = data['price'] as Map<String, dynamic>?;
    final discountedPrice = price?['discounted_price'];
    final currency = price?['currency'] ?? 'INR';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D32) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 90,
              height: 90,
              color: isDark ? const Color(0xFF111114) : const Color(0xFFF3F4F6),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                    )
                  : _buildImagePlaceholder(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (discountedPrice != null)
                  Row(
                    children: [
                      Text(
                        'Store Price:',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$currency $discountedPrice',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _primaryOrange,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Icon(
        Icons.card_giftcard_rounded,
        size: 40,
        color: _primaryOrange.withOpacity(0.3),
      ),
    );
  }

  Widget _buildEligibilityCard(
    BuildContext context,
    int pointsRequired,
    int userPoints,
    int remainingPoints,
    bool isEligible,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEligible
              ? [
                  Colors.green.withOpacity(isDark ? 0.2 : 0.1),
                  Colors.green.withOpacity(isDark ? 0.15 : 0.05),
                ]
              : [
                  Colors.orange.withOpacity(isDark ? 0.2 : 0.1),
                  Colors.orange.withOpacity(isDark ? 0.15 : 0.05),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEligible
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEligible ? Icons.check_circle : Icons.info_outline,
                color: isEligible ? Colors.green[400] : Colors.orange[400],
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'Eligibility Status',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildPointRow(
            context,
            'Points Needed',
            pointsRequired.toString(),
            Icons.stars_rounded,
            _primaryOrange,
            isDark,
          ),
          const SizedBox(height: 14),
          _buildPointRow(
            context,
            'Your Points',
            userPoints.toString(),
            Icons.account_balance_wallet,
            isEligible ? Colors.green[400]! : Colors.grey[400]!,
            isDark,
          ),
          if (!isEligible) ...[
            const SizedBox(height: 14),
            _buildPointRow(
              context,
              'Remaining Points',
              remainingPoints.toString(),
              Icons.trending_up,
              Colors.orange[400]!,
              isDark,
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (isEligible ? Colors.green : Colors.orange).withOpacity(
                0.15,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isEligible ? Icons.check_circle_outline : Icons.error_outline,
                  size: 20,
                  color: isEligible ? Colors.green[700] : Colors.orange[700],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEligible
                        ? 'You can request this reward ✅'
                        : 'Earn $remainingPoints more points to request',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isEligible
                          ? Colors.green[700]
                          : Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ],
        ),
        Text(
          '$value points',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton(
    BuildContext context,
    ProductModel product,
    int pointsRequired,
    bool isEligible,
    int remainingPoints,
    bool isDark,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: !isEligible || _isRequesting
            ? null
            : () => _showConfirmationDialog(context, product, pointsRequired),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryOrange,
          disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
          foregroundColor: Colors.white,
          elevation: isEligible ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isRequesting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isEligible ? Icons.check_circle : Icons.lock_outline,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEligible
                        ? 'Confirm Request'
                        : 'Need $remainingPoints More Points',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showConfirmationDialog(
    BuildContext context,
    ProductModel product,
    int pointsRequired,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.card_giftcard, color: _primaryOrange),
            const SizedBox(width: 10),
            const Text('Confirm Request'),
          ],
        ),
        content: Text(
          'Request "${product.title}" for $pointsRequired points?\n\n'
          'Your points will be locked until the parent approves or the request expires (21 days).',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _submitRequest(product, pointsRequired);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRequest(ProductModel product, int pointsRequired) async {
    if (widget.studentId == null || widget.studentId!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student ID not found. Please sign in again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isRequesting = true);

    try {
      // Check if student has pending request
      final repository = ref.read(rewardsRepositoryProvider);
      final hasPending = await repository.hasActivePendingRequest(
        widget.studentId!,
      );

      if (hasPending) {
        if (!mounted) return;
        setState(() => _isRequesting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⏳ You have a pending reward request. Please wait for parent approval.',
            ),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Get parent ID from student document
      String parentId;
      try {
        final studentDoc = await repository.getStudentDocument(
          widget.studentId!,
        );
        parentId =
            studentDoc['parentId'] as String? ??
            studentDoc['parent_id'] as String? ??
            studentDoc['userId'] as String? ??
            widget.studentId!;
      } catch (e) {
        parentId = widget.studentId!;
      }

      final notifier = ref.read(createRequestProvider.notifier);
      await notifier.createRequest(
        product: product,
        studentId: widget.studentId!,
        parentId: parentId,
      );

      // Check if request actually succeeded
      final requestState = ref.read(createRequestProvider);
      if (requestState.hasError) {
        throw requestState.error ?? Exception('Unknown error');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Request submitted! Parent notification sent.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back to catalog
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }
}
