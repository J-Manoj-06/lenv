import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'reward_request_screen.dart';

const Color _primaryOrange = Color(0xFFF97316);
const Color _darkBg = Color(0xFF0F0F14);
const Color _cardDark = Color(0xFF1E1E1E);
const Color _borderDark = Color(0xFF2D2D32);

class RewardDetailsScreen extends ConsumerWidget {
  final String productId;
  final String? studentId;

  const RewardDetailsScreen({
    super.key,
    required this.productId,
    this.studentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? _darkBg : const Color(0xFFF5F6F7),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('rewards_catalog')
            .doc(productId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState(isDark);
          }

          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return _buildErrorState(context, isDark);
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          return SafeArea(
            child: CustomScrollView(
              slivers: [
                _buildAppBar(context, data, isDark),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _buildProductHeader(context, data, isDark),
                      const SizedBox(height: 24),
                      _buildPriceRedeemCard(context, data, isDark),
                      const SizedBox(height: 20),
                      if (data['availability'] != null)
                        _buildAvailabilityPill(context, data, isDark),
                      if (data['availability'] != null)
                        const SizedBox(height: 16),
                      _buildDescriptionSection(context, data, isDark),
                      const SizedBox(height: 20),
                      _buildMetaInfoCards(context, data, isDark),
                      const SizedBox(height: 20),
                      if (data['learning_type'] != null)
                        _buildLearningTypeSection(context, data, isDark),
                      if (data['learning_type'] != null)
                        const SizedBox(height: 20),
                      if (data['features'] != null)
                        _buildFeaturesSection(context, data, isDark),
                      if (data['features'] != null) const SizedBox(height: 20),
                      _buildDeliverySellerSection(context, data, isDark),
                      const SizedBox(height: 20),
                      _buildViewOnAmazonButton(context, data, isDark),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomRequestCTA(context),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_primaryOrange),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading reward details...',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _primaryOrange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: _primaryOrange,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Product not found',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'This reward is no longer available',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Go Back'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final images = data['images'] as List?;
    final imageUrl = images != null && images.isNotEmpty
        ? images[0]['url'] as String?
        : data['image_url'] as String?;

    return SliverAppBar(
      expandedHeight: 340,
      pinned: true,
      backgroundColor: isDark ? _cardDark : Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            Container(
              color: isDark ? const Color(0xFF111114) : const Color(0xFFF3F4F6),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildImagePlaceholder(isDark),
                    )
                  : _buildImagePlaceholder(isDark),
            ),
            // Gradient overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 120,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      (isDark ? _darkBg : const Color(0xFFF5F6F7)).withOpacity(
                        0.8,
                      ),
                      isDark ? _darkBg : const Color(0xFFF5F6F7),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(bool isDark) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: _primaryOrange.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.card_giftcard_rounded,
          size: 80,
          color: _primaryOrange.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _buildProductHeader(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final title = data['title'] ?? 'Product';
    final brand = data['brand'];
    final category = data['category'];
    final subCategory = data['sub_category'];
    final ratings = data['ratings'] as Map<String, dynamic>?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand Badge
          if (brand != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _primaryOrange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                brand.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _primaryOrange,
                ),
              ),
            ),
          if (brand != null) const SizedBox(height: 12),

          // Title
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.3,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 14),

          // Category Chips + Rating
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (category != null || subCategory != null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (category != null)
                      _buildModernChip(
                        category,
                        isDark,
                        icon: Icons.category_rounded,
                      ),
                    if (subCategory != null)
                      _buildModernChip(
                        subCategory,
                        isDark,
                        icon: Icons.label_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (ratings != null) _buildRatingRow(context, ratings, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernChip(String label, bool isDark, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _primaryOrange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryOrange.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: _primaryOrange),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _primaryOrange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingRow(
    BuildContext context,
    Map<String, dynamic> ratings,
    bool isDark,
  ) {
    final avgRating = ratings['average_rating'] as num?;
    final source = ratings['rating_source'] as String?;

    if (avgRating == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 18, color: Colors.amber[600]),
          const SizedBox(width: 6),
          Text(
            avgRating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.amber[900],
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '/ 5',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.amber[700],
            ),
          ),
          if (source != null) ...[
            const SizedBox(width: 8),
            Text(
              '• $source',
              style: TextStyle(fontSize: 11, color: Colors.amber[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceRedeemCard(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final price = data['price'] as Map<String, dynamic>?;
    final pointsRule = data['points_rule'] as Map<String, dynamic>?;
    final maxPoints = pointsRule?['max_points'] as int?;

    if (price == null) return const SizedBox.shrink();

    final currency = price['currency'] ?? 'INR';
    final discountedPrice = price['discounted_price'];
    final originalPrice = price['original_price'];
    final discountPercentage = price['discount_percentage'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isDark ? const Color(0xFF252530) : const Color(0xFFFAFAFA),
              isDark ? const Color(0xFF1E1E1E) : Colors.white,
            ],
          ),
          border: Border.all(
            color: isDark ? _borderDark : Colors.grey.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _primaryOrange.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Store Price',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (discountedPrice != null)
                    Text(
                      '$currency ${discountedPrice.toString()}',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _primaryOrange,
                            fontSize: 28,
                          ),
                    ),
                  if (originalPrice != null &&
                      discountedPrice != originalPrice) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '$currency ${originalPrice.toString()}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.lineThrough,
                            color: isDark ? Colors.grey[600] : Colors.grey[500],
                          ),
                        ),
                        if (discountPercentage != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '$discountPercentage% OFF',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.green[700],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (maxPoints != null) ...[
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _primaryOrange.withOpacity(0.15),
                      _primaryOrange.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _primaryOrange.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryOrange.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.stars_rounded, color: _primaryOrange, size: 24),
                    const SizedBox(height: 6),
                    Text(
                      maxPoints.toString(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _primaryOrange,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Points',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _primaryOrange,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityPill(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final availability = data['availability'] as String?;
    if (availability == null) return const SizedBox.shrink();

    final isAvailable = availability.toLowerCase() != 'out of stock';
    final bgColor = isAvailable
        ? Colors.green.withOpacity(0.1)
        : Colors.red.withOpacity(0.1);
    final textColor = isAvailable ? Colors.green[700] : Colors.red[700];
    final icon = isAvailable ? Icons.check_circle_rounded : Icons.block_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: textColor!.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 8),
            Text(
              availability,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaInfoCards(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final ageGroup = data['age_group'];
    final bookFormat = data['book_format'];
    final binding = data['binding'];
    final availability = data['availability'];

    final items = <Map<String, dynamic>>[];
    if (ageGroup != null) {
      items.add({
        'label': 'Age Group',
        'value': ageGroup,
        'icon': Icons.child_care,
      });
    }
    if (bookFormat != null) {
      items.add({'label': 'Format', 'value': bookFormat, 'icon': Icons.book});
    }
    if (binding != null) {
      items.add({'label': 'Binding', 'value': binding, 'icon': Icons.layers});
    }
    if (availability != null) {
      items.add({
        'label': 'Availability',
        'value': availability,
        'icon': Icons.inventory,
      });
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items
            .map((item) => _buildMetaCard(context, item, isDark))
            .toList(),
      ),
    );
  }

  Widget _buildMetaCard(
    BuildContext context,
    Map<String, dynamic> item,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D32) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item['icon'] as IconData, size: 16, color: _primaryOrange),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['label'],
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item['value'],
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final description = data['description'] as String?;
    if (description == null || description.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.5,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLearningTypeSection(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final learningTypes = data['learning_type'] as List?;
    if (learningTypes == null || learningTypes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Learning Focus',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: learningTypes
                .map(
                  (type) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _primaryOrange.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      type.toString(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _primaryOrange,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final features = data['features'] as List?;
    if (features == null || features.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Key Features',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _primaryOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature.toString(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliverySellerSection(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final delivery = data['delivery'] as Map<String, dynamic>?;
    final seller = data['seller'] as Map<String, dynamic>?;

    if (delivery == null && seller == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF2D2D32) : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delivery & Seller Info',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            if (delivery != null) ...[
              _buildInfoRow(
                context,
                'Delivery Type',
                delivery['type'] ?? 'N/A',
                Icons.local_shipping_outlined,
                isDark,
              ),
              if (delivery['fulfilled_by'] != null) ...[
                const SizedBox(height: 10),
                _buildInfoRow(
                  context,
                  'Fulfilled By',
                  delivery['fulfilled_by'],
                  Icons.verified_outlined,
                  isDark,
                ),
              ],
            ],
            if (seller != null) ...[
              const SizedBox(height: 10),
              _buildInfoRow(
                context,
                'Platform',
                seller['platform'] ?? 'N/A',
                Icons.store_outlined,
                isDark,
              ),
              if (seller['brand_owner'] != null) ...[
                const SizedBox(height: 10),
                _buildInfoRow(
                  context,
                  'Brand Owner',
                  seller['brand_owner'],
                  Icons.business_outlined,
                  isDark,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExternalLinkButton(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final cta = data['cta'] as Map<String, dynamic>?;
    final affiliate = data['affiliate'] as Map<String, dynamic>?;

    String? url = cta?['redirect_url'];
    url ??= affiliate?['affiliate_link'];

    if (url == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: () async {
          final uri = Uri.parse(url!);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open link')),
              );
            }
          }
        },
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(cta?['button_text'] ?? 'View on Store'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          side: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Secondary CTA: opens the product on Amazon/store
  Widget _buildViewOnAmazonButton(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final cta = data['cta'] as Map<String, dynamic>?;
    final affiliate = data['affiliate'] as Map<String, dynamic>?;

    String? url = cta?['redirect_url'];
    url ??= affiliate?['affiliate_link'];

    // Always surface a visit-store label (even if backend still says "Buy Now")
    String buttonText = cta?['button_text'] ?? 'Visit Amazon Store';
    if (buttonText.toLowerCase() == 'buy now') {
      buttonText = 'Visit Amazon Store';
    }

    if (url == null) return const SizedBox.shrink();
    final link = url;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: () async {
          final uri = Uri.parse(link);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open link')),
              );
            }
          }
        },
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(buttonText),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          side: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  /// Primary CTA: Request Reward (navigates to request screen)
  Widget _buildBottomRequestCTA(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2D2D32) : Colors.grey.shade200,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RewardRequestScreen(
                  productId: productId,
                  studentId: studentId,
                ),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryOrange,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.card_giftcard, size: 20),
              SizedBox(width: 10),
              Text(
                'Request Reward',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
