import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/product_model.dart';
import '../../providers/rewards_providers.dart';
import '../../services/affiliate_service.dart';
import '../../utils/points_calculator.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  final ProductModel? initialProduct;
  final String? studentId;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.initialProduct,
    this.studentId,
  });

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  bool _isRequestingProduct = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use initialProduct if available, otherwise fetch from provider
    final productAsync = widget.initialProduct != null
        ? AsyncValue.data(widget.initialProduct)
        : ref.watch(productDetailProvider(widget.productId));

    // Watch student points if studentId is available, otherwise use 0
    final studentPointsAsync =
        widget.studentId != null && widget.studentId!.isNotEmpty
        ? ref.watch(studentPointsProvider(widget.studentId!))
        : const AsyncValue.data(0.0);

    return productAsync.when(
      data: (product) {
        if (product == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Product Not Found')),
            body: const Center(child: Text('Product not found')),
          );
        }

        final pointsRequired = PointsCalculator.calculatePointsRequired(
          price: product.price.estimatedPrice,
          pointsPerRupee: product.pointsRule.pointsPerRupee,
          maxPoints: product.pointsRule.maxPoints,
        );

        // Check eligibility based on student points
        return studentPointsAsync.when(
          data: (studentPoints) {
            final requiredInt = pointsRequired;
            final availableInt = studentPoints.toInt();
            final isEligible = availableInt >= requiredInt;
            final neededPoints = (requiredInt - availableInt) > 0
                ? (requiredInt - availableInt)
                : 0;

            final affiliateUrl = AffiliateService.buildUrl(
              source: product.source,
              productId: product.productId,
              asin: product.asin,
            );

            return Scaffold(
              // App bar removed; custom header below keeps nav bar hidden and uses the project arrow style
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  'Reward',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ===== PRODUCT IMAGE SECTION =====
                      Container(
                        width: double.infinity,
                        height: 280,
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          size: 80,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),

                      // ===== PRODUCT HEADER (NAME & PRICE) =====
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Product Name - Primary element
                            Text(
                              product.title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 16),

                            // Price & Rating Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Price
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Store Price',
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₹${product.price.estimatedPrice.toStringAsFixed(0)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFFF2800D),
                                          ),
                                    ),
                                  ],
                                ),

                                // Rating
                                if (product.rating != null && product.rating! > 0)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Rating',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.star_rounded,
                                            size: 16,
                                            color: Colors.amber[400],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${product.rating!.toStringAsFixed(1)} / 5',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 28),

                    // ===== REWARD ELIGIBILITY SECTION =====
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[800]!
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section Title
                            Text(
                              'Your Eligibility',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                            const SizedBox(height: 14),

                            // Points Required (Primary)
                            _ModernInfoRow(
                              label: 'Points Needed',
                              value: '$requiredInt points',
                              icon: Icons.card_giftcard,
                              isPrimary: true,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 10),

                            // Your Points (Secondary - with color indicator)
                            _ModernInfoRow(
                              label: 'Your Points',
                              value: '$availableInt points',
                              icon: Icons.account_balance_wallet,
                              valueColor: isEligible
                                  ? Colors.green
                                  : Colors.orange,
                              isDark: isDark,
                            ),

                            // Eligibility message if needed
                            if (!isEligible) ...[
                              const SizedBox(height: 12),
                              _EligibilityMessage(
                                neededPoints: neededPoints,
                                isDark: isDark,
                              ),
                            ],

                            // Eligible badge
                            if (isEligible) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  '✓ You can request this reward',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ===== PRODUCT DETAILS SECTION =====
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Product Info',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.grey[200]
                                      : Colors.grey[800],
                                ),
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(
                            label: 'Product ID',
                            value: product.asin ?? 'N/A',
                            isDark: isDark,
                          ),
                          _DetailDivider(isDark: isDark),
                          _DetailRow(
                            label: 'Status',
                            value: product.status,
                            isDark: isDark,
                          ),
                          _DetailDivider(isDark: isDark),
                          _DetailRow(
                            label: 'Currency',
                            value: product.price.currency,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ===== SECONDARY ACTION (View on Store) =====
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Opening: $affiliateUrl')),
                          );
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('View on Store'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          side: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                        ),
                      ),
                    ),

                      const SizedBox(height: 24),

                      // ===== PRIMARY ACTION BUTTON (moved into scroll, no bottom nav) =====
                      _ActionButton(
                        isEligible: isEligible,
                        isLoading: _isRequestingProduct,
                        onPressed: !isEligible || _isRequestingProduct
                            ? null
                            : () => _showRequestConfirmation(
                                context,
                                product,
                                pointsRequired,
                              ),
                        neededPoints: neededPoints,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => Scaffold(
            appBar: AppBar(title: const Text('Loading points...')),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, st) => Scaffold(
            appBar: AppBar(title: const Text('Product Details')),
            body: Center(child: Text('Unable to load points: $error')),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, st) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

  void _showRequestConfirmation(
    BuildContext context,
    ProductModel product,
    int pointsRequired,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Reward'),
        content: Text(
          'Request ${product.title} for $pointsRequired points?\n\nThis will lock your points until the parent approves or the request expires (21 days).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isRequestingProduct
                ? null
                : () async {
                    Navigator.pop(context);
                    await _submitRequest(product, pointsRequired);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2800D),
            ),
            child: const Text('Request'),
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

    setState(() => _isRequestingProduct = true);

    try {
      // Get parent ID from current user or use a default
      // NOTE: In production, get actual parent ID from user/student relationship
      final parentId = widget.studentId!.replaceFirst('student_', 'parent_');

      final notifier = ref.read(createRequestProvider.notifier);
      await notifier.createRequest(
        product: product,
        studentId: widget.studentId!,
        parentId: parentId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Request submitted! Parent notification sent.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );

      // Optional: Navigate back or refresh requests
      if (mounted) {
        Navigator.pop(context);
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
        setState(() => _isRequestingProduct = false);
      }
    }
  }
}

// ===== MODERN INFO ROW WIDGET =====
class _ModernInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isPrimary;
  final Color? valueColor;
  final bool isDark;

  const _ModernInfoRow({
    required this.label,
    required this.value,
    required this.icon,
    this.isPrimary = false,
    this.valueColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isPrimary
                  ? const Color(0xFFF2800D)
                  : isDark
                  ? Colors.grey[500]
                  : Colors.grey[500],
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ===== ELIGIBILITY MESSAGE WIDGET =====
class _EligibilityMessage extends StatelessWidget {
  final int neededPoints;
  final bool isDark;

  const _EligibilityMessage({required this.neededPoints, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.orange.withOpacity(isDark ? 0.3 : 0.2),
        ),
      ),
      child: Text(
        'Earn $neededPoints more points to request',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.orange[700],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ===== DETAIL ROW (PRODUCT INFO) =====
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[200] : Colors.grey[900],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== DETAIL DIVIDER =====
class _DetailDivider extends StatelessWidget {
  final bool isDark;

  const _DetailDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
    );
  }
}

// ===== ACTION BUTTON WIDGET =====
class _ActionButton extends StatelessWidget {
  final bool isEligible;
  final bool isLoading;
  final VoidCallback? onPressed;
  final int neededPoints;
  final bool isDark;

  const _ActionButton({
    required this.isEligible,
    required this.isLoading,
    required this.onPressed,
    required this.neededPoints,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.card_giftcard, size: 18),
          label: Text(
            isLoading
                ? 'Requesting...'
                : isEligible
                ? 'Request Reward'
                : 'Need $neededPoints Points',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF2800D),
            disabledBackgroundColor: isDark
                ? Colors.grey[800]
                : Colors.grey[300],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}
