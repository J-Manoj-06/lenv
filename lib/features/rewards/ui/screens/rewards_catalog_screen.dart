import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/product_model.dart';
import '../../providers/rewards_providers.dart';
import '../widgets/product_card.dart';
import '../widgets/rewards_top_switcher.dart';
import 'reward_details_screen.dart';
import 'reward_request_screen.dart';

const Color _primaryOrange = Color(0xFFF97316);

class RewardsCatalogScreen extends ConsumerStatefulWidget {
  final String? studentId;

  const RewardsCatalogScreen({super.key, this.studentId});

  @override
  ConsumerState<RewardsCatalogScreen> createState() =>
      _RewardsCatalogScreenState();
}

class _RewardsCatalogScreenState extends ConsumerState<RewardsCatalogScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _sortBy = 'default';
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text;
    final productsAsync = searchQuery.isEmpty
        ? ref.watch(rewardsCatalogProvider)
        : ref.watch(productsSearchProvider(searchQuery));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF0F0F14)
        : const Color(0xFFF5F6F7);
    final searchBg = isDark ? const Color(0xFF1C1C1F) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Column(
        children: [
          // Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Rewards Store',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.card_giftcard_rounded, color: _primaryOrange),
                ],
              ),
            ),
          ),
          RewardsTopSwitcher(
            isCatalogActive: true,
            studentId: widget.studentId,
          ),
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                _buildModernSearchBar(context, isDark, searchBg),
                const SizedBox(height: 12),
                _buildFilterChips(context),
              ],
            ),
          ),
          // Products List
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return _buildEmptyState(context, isDark);
                }

                // Sort products
                var sortedProducts = List<ProductModel>.from(products);
                switch (_sortBy) {
                  case 'price_asc':
                    sortedProducts.sort(
                      (a, b) => a.price.estimatedPrice.compareTo(
                        b.price.estimatedPrice,
                      ),
                    );
                  case 'price_desc':
                    sortedProducts.sort(
                      (a, b) => b.price.estimatedPrice.compareTo(
                        a.price.estimatedPrice,
                      ),
                    );
                  case 'rating':
                    sortedProducts.sort(
                      (a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0),
                    );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: 20,
                    left: 16,
                    right: 16,
                  ),
                  itemCount: sortedProducts.length,
                  itemBuilder: (context, index) {
                    final product = sortedProducts[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ProductCard(
                        product: product,
                        onRequestPressed: () {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (ctx) => UncontrolledProviderScope(
                                container: ProviderScope.containerOf(context),
                                child: RewardRequestScreen(
                                  productId: product.productId,
                                  studentId: widget.studentId,
                                ),
                              ),
                            ),
                          );
                        },
                        onDetailsPressed: () {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (ctx) => UncontrolledProviderScope(
                                container: ProviderScope.containerOf(context),
                                child: RewardDetailsScreen(
                                  productId: product.productId,
                                  studentId: widget.studentId,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
              loading: () {
                return _buildLoadingList(isDark);
              },
              error: (error, st) {
                return _buildErrorState(context, error, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSearchBar(
    BuildContext context,
    bool isDark,
    Color cardBg,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A2E) : Colors.grey.shade200,
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) {
          setState(() {});
        },
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search rewards…',
          hintStyle: TextStyle(
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.search_rounded, color: _primaryOrange, size: 22),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                      size: 20,
                    ),
                  ),
                )
              : null,
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _primaryOrange, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chips = [
      ('All', 'default', Icons.apps_rounded),
      ('Low to High', 'price_asc', Icons.arrow_downward_rounded),
      ('High to Low', 'price_desc', Icons.arrow_upward_rounded),
      ('Top Rated', 'rating', Icons.star_rounded),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final (label, value, icon) = chips[index];
          final isSelected = _sortBy == value;

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() => _sortBy = value);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _primaryOrange : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? _primaryOrange
                      : (isDark
                            ? const Color(0xFF2D2D32)
                            : Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.grey[300] : Colors.grey[700]),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.grey[200] : Colors.grey[800]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _SkeletonCard(isDark: isDark),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _primaryOrange.withOpacity(0.1),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: _primaryOrange,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No rewards found',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search criteria',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.1),
            ),
            child: Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
          ),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              // Use refresh result to satisfy lints
              final _ = ref.refresh(rewardsCatalogProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

class _ModernFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onSelected;

  const _ModernFilterChip({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryOrange
              : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  width: 1,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryOrange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey[300] : Colors.grey[700]),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final bool isDark;

  const _SkeletonCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[200]!;

    Widget shimmer({required double width, required double height}) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  base,
                  Color.lerp(base, highlight, 0.3 + 0.3 * value)!,
                  base,
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D32) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          shimmer(width: 100, height: 110),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                shimmer(width: double.infinity, height: 14),
                const SizedBox(height: 8),
                shimmer(width: 160, height: 12),
                const SizedBox(height: 10),
                shimmer(width: 80, height: 12),
                const SizedBox(height: 10),
                shimmer(width: 140, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final bool isSelected;
  final VoidCallback onSelected;

  const _SortChip({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      backgroundColor: Colors.transparent,
      side: BorderSide(
        color: isSelected ? const Color(0xFFF2800D) : Colors.grey[300]!,
      ),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFFF2800D) : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}
