import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'reward_request_screen.dart';

const Color _primaryOrange = Color(0xFFF97316);

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

    print('🔵 RewardDetailsScreen - productId: $productId');

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F0F14)
          : const Color(0xFFF5F6F7),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('rewards_catalog')
            .doc(productId)
            .get(),
        builder: (context, snapshot) {
          print(
            '🔵 RewardDetailsScreen - connectionState: ${snapshot.connectionState}',
          );

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          print('🔵 RewardDetailsScreen - hasError: ${snapshot.hasError}');
          print('🔵 RewardDetailsScreen - hasData: ${snapshot.hasData}');
          print('🔵 RewardDetailsScreen - exists: ${snapshot.data?.exists}');

          if (snapshot.hasError) {
            print('🔴 RewardDetailsScreen - error: ${snapshot.error}');
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
            '🟢 RewardDetailsScreen - Found product data: ${data['title']}',
          );
          print('🟢 RewardDetailsScreen - Data keys: ${data.keys.toList()}');

          return SafeArea(
            child: CustomScrollView(
              slivers: [
                _buildAppBar(context, data, isDark),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProductHeader(context, data, isDark),
                      const SizedBox(height: 16),
                      _buildPriceSection(context, data, isDark),
                      const SizedBox(height: 20),
                      _buildMetaInfoCards(context, data, isDark),
                      const SizedBox(height: 20),
                      _buildDescriptionSection(context, data, isDark),
                      if (data['learning_type'] != null)
                        _buildLearningTypeSection(context, data, isDark),
                      if (data['features'] != null)
                        _buildFeaturesSection(context, data, isDark),
                      const SizedBox(height: 20),
                      _buildDeliverySellerSection(context, data, isDark),
                      const SizedBox(height: 16),
                      _buildExternalLinkButton(context, data, isDark),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomCTA(context, isDark),
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
      expandedHeight: 320,
      pinned: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: isDark ? const Color(0xFF111114) : const Color(0xFFF3F4F6),
          child: imageUrl != null && imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _buildImagePlaceholder(isDark),
                )
              : _buildImagePlaceholder(isDark),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(bool isDark) {
    return Center(
      child: Icon(
        Icons.card_giftcard_rounded,
        size: 100,
        color: _primaryOrange.withOpacity(0.3),
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
          if (brand != null)
            Text(
              brand,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: _primaryOrange,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (category != null) ...[
                _buildChip(category, isDark, icon: Icons.category_outlined),
                const SizedBox(width: 8),
              ],
              if (subCategory != null)
                _buildChip(subCategory, isDark, icon: Icons.sell_outlined),
            ],
          ),
          if (ratings != null) ...[
            const SizedBox(height: 12),
            _buildRatingRow(context, ratings, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool isDark, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
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

    return Row(
      children: [
        Icon(Icons.star_rounded, size: 20, color: Colors.amber[500]),
        const SizedBox(width: 6),
        Text(
          avgRating.toStringAsFixed(1),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.amber[400],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '/ 5',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        if (source != null) ...[
          const SizedBox(width: 12),
          Text(
            source,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceSection(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final price = data['price'] as Map<String, dynamic>?;
    if (price == null) return const SizedBox.shrink();

    final currency = price['currency'] ?? 'INR';
    final discountedPrice = price['discounted_price'];
    final originalPrice = price['original_price'];
    final discountPercentage = price['discount_percentage'];

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
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (discountedPrice != null)
                    Text(
                      '$currency ${discountedPrice.toString()}',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _primaryOrange,
                          ),
                    ),
                  if (originalPrice != null &&
                      discountedPrice != originalPrice) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '$currency ${originalPrice.toString()}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[600],
                              ),
                        ),
                        if (discountPercentage != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$discountPercentage% OFF',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
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
    if (ageGroup != null)
      items.add({
        'label': 'Age Group',
        'value': ageGroup,
        'icon': Icons.child_care,
      });
    if (bookFormat != null)
      items.add({'label': 'Format', 'value': bookFormat, 'icon': Icons.book});
    if (binding != null)
      items.add({'label': 'Binding', 'value': binding, 'icon': Icons.layers});
    if (availability != null)
      items.add({
        'label': 'Availability',
        'value': availability,
        'icon': Icons.inventory,
      });

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
    if (description == null || description.isEmpty)
      return const SizedBox.shrink();

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
    if (learningTypes == null || learningTypes.isEmpty)
      return const SizedBox.shrink();

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

  Widget _buildBottomCTA(BuildContext context, bool isDark) {
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
                builder: (ctx) => RewardRequestScreen(
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
