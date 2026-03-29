import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/product_model.dart';
import '../../models/reward_request_model.dart';
import '../../providers/rewards_providers.dart';
import '../../utils/points_calculator.dart';
import 'dart:ui';

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
  bool _hasPendingRequest = false;
  bool _isThisProductPending = false;

  // Catalog future stored in state so it is created once and never recreated on
  // each build. Also ensures the auth token is refreshed before the Firestore
  // read to avoid the startup "permission denied" race condition.
  late final Future<DocumentSnapshot> _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _fetchCatalogDoc();
    _checkPendingRequest();
  }

  Future<DocumentSnapshot> _fetchCatalogDoc() async {
    // Ensure Firestore SDK has the current auth token before reading.
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(false);
    } catch (_) {}
    return FirebaseFirestore.instance
        .collection('rewards_catalog')
        .doc(widget.productId)
        .get();
  }

  Future<void> _checkPendingRequest() async {
    if (widget.studentId == null || widget.studentId!.isEmpty) return;

    try {
      final repository = ref.read(rewardsRepositoryProvider);

      // Get the latest pending request
      final latestRequest = await repository.getLatestRewardRequest(
        widget.studentId!,
      );

      if (latestRequest != null &&
          latestRequest.status == RewardRequestStatus.pendingParentApproval) {
        final hasPending = true;
        final isThisProduct =
            latestRequest.productSnapshot.productId == widget.productId;

        if (mounted) {
          setState(() {
            _hasPendingRequest = hasPending;
            _isThisProductPending = isThisProduct;
          });
        }
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {}

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

          final product = ProductModel.fromMap(data);

          // Calculate points required
          final pointsRequired = PointsCalculator.calculatePointsRequired(
            price: product.price.estimatedPrice,
            pointsPerRupee: product.pointsRule.pointsPerRupee,
            maxPoints: product.pointsRule.maxPoints,
          );

          // Watch total earned points for display
          final totalPointsAsync =
              widget.studentId != null && widget.studentId!.isNotEmpty
              ? ref.watch(studentPointsProvider(widget.studentId!))
              : const AsyncValue.data(0.0);

          // Watch available points for backend validation
          final availablePointsAsync =
              widget.studentId != null && widget.studentId!.isNotEmpty
              ? ref.watch(studentAvailablePointsProvider(widget.studentId!))
              : const AsyncValue.data(0.0);

          return totalPointsAsync.when(
            data: (totalPoints) {
              return availablePointsAsync.when(
                data: (availablePoints) {
                  final userTotalPoints = totalPoints.toInt();
                  final userAvailablePoints = availablePoints.toInt();
                  final remainingPoints = pointsRequired - userAvailablePoints;
                  final isEligible = userAvailablePoints >= pointsRequired;

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
                            userTotalPoints,
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
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Unable to load your points',
                        style: Theme.of(context).textTheme.titleMedium,
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
                      errorBuilder: (_, _, _) => _buildImagePlaceholder(),
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
    String buttonText;
    IconData buttonIcon;
    VoidCallback? onPressed;
    Color? buttonColor;
    Color? disabledColor;

    if (_isThisProductPending) {
      // This specific product has been requested
      buttonText = 'Already Requested';
      buttonIcon = Icons.schedule_outlined;
      onPressed = null;
      buttonColor = Colors.amber.shade700;
      disabledColor = Colors.amber.shade700.withOpacity(0.6);
    } else if (_hasPendingRequest) {
      // Another product has been requested - show popup on tap
      buttonText = 'Confirm Request';
      buttonIcon = Icons.check_circle;
      onPressed = () => _showPendingRequestWarning(context);
      buttonColor = _primaryOrange;
      disabledColor = isDark ? Colors.grey[800] : Colors.grey[300];
    } else if (!isEligible) {
      // Not enough points
      buttonText = 'Need $remainingPoints More Points';
      buttonIcon = Icons.lock_outline;
      onPressed = null;
      buttonColor = _primaryOrange;
      disabledColor = isDark ? Colors.grey[800] : Colors.grey[300];
    } else {
      // Can request
      buttonText = 'Confirm Request';
      buttonIcon = Icons.check_circle;
      onPressed = _isRequesting
          ? null
          : () => _showConfirmationDialog(context, product, pointsRequired);
      buttonColor = _primaryOrange;
      disabledColor = isDark ? Colors.grey[800] : Colors.grey[300];
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          disabledBackgroundColor: disabledColor,
          foregroundColor: Colors.white,
          elevation: onPressed != null ? 4 : 0,
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
                  Icon(buttonIcon, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    buttonText,
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
    // Double check for pending request before showing dialog
    if (_hasPendingRequest) {
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

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: _ModernConfirmationDialog(
            product: product,
            pointsRequired: pointsRequired,
            onConfirm: () {
              Navigator.pop(context);
              _submitRequest(product, pointsRequired);
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(opacity: curvedAnimation, child: child),
        );
      },
    );
  }

  void _showPendingRequestWarning(BuildContext context) {
    HapticFeedback.mediumImpact();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(child: _PendingRequestWarningDialog());
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(opacity: curvedAnimation, child: child),
        );
      },
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

// Modern Confirmation Dialog Widget
class _ModernConfirmationDialog extends StatefulWidget {
  final ProductModel product;
  final int pointsRequired;
  final VoidCallback onConfirm;

  const _ModernConfirmationDialog({
    required this.product,
    required this.pointsRequired,
    required this.onConfirm,
  });

  @override
  State<_ModernConfirmationDialog> createState() =>
      _ModernConfirmationDialogState();
}

class _ModernConfirmationDialogState extends State<_ModernConfirmationDialog> {
  bool _isConfirming = false;

  void _handleConfirm() async {
    if (_isConfirming) return;

    setState(() => _isConfirming = true);

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Small delay to show visual feedback
    await Future.delayed(const Duration(milliseconds: 150));

    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon and Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _primaryOrange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.card_giftcard_rounded,
                            color: _primaryOrange,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'Confirm Request',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF5F5F5),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Product Info
                    Row(
                      children: [
                        // Product Image
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: (widget.product.imageUrl?.isNotEmpty ?? false)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: Image.network(
                                    widget.product.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Icon(
                                          Icons.image_outlined,
                                          color: Colors.white.withOpacity(0.3),
                                          size: 28,
                                        ),
                                  ),
                                )
                              : Icon(
                                  Icons.image_outlined,
                                  color: Colors.white.withOpacity(0.3),
                                  size: 28,
                                ),
                        ),
                        const SizedBox(width: 16),

                        // Product Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.product.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE5E5E5),
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _primaryOrange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.stars_rounded,
                                      size: 14,
                                      color: _primaryOrange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${widget.pointsRequired} points',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _primaryOrange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Divider
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.1),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Info Text
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.05),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 20,
                            color: Colors.white.withOpacity(0.6),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your points will be locked until the parent approves or the request expires (21 days).',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.white.withOpacity(0.7),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Action Buttons
                    Row(
                      children: [
                        // Cancel Button
                        Expanded(
                          child: TextButton(
                            onPressed: _isConfirming
                                ? null
                                : () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pop(context);
                                  },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _isConfirming
                                    ? Colors.white.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.8),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Confirm Button
                        Expanded(
                          flex: 1,
                          child: ElevatedButton(
                            onPressed: _isConfirming ? null : _handleConfirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              disabledBackgroundColor: _primaryOrange
                                  .withOpacity(0.5),
                            ),
                            child: _isConfirming
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Confirm',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Pending Request Warning Dialog Widget
class _PendingRequestWarningDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Warning Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange.shade400,
                        size: 48,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    const Text(
                      'Request Pending',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF5F5F5),
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Message
                    Text(
                      'You have already requested another reward. Please wait for parent approval or cancellation before requesting a new reward.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Colors.white.withOpacity(0.75),
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 28),

                    // OK Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Got it',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
