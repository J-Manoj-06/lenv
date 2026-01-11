import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/product_model.dart';
import '../../providers/rewards_providers.dart';
import '../widgets/product_card.dart';
import '../widgets/rewards_top_switcher.dart';
import 'product_detail_screen.dart';

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
        ? const Color(0xFF121212)
        : const Color(0xFFFAF9F7);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: _buildModernAppBar(context, isDark, cardBg),
      body: Column(
        children: [
          RewardsTopSwitcher(
            isCatalogActive: true,
            studentId: widget.studentId,
          ),
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                _buildModernSearchBar(context, isDark, cardBg),
                const SizedBox(height: 14),
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
                                child: ProductDetailScreen(
                                  productId: product.productId,
                                  initialProduct: product,
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
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: const AlwaysStoppedAnimation(
                          _primaryOrange,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading rewards...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
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

  PreferredSizeWidget _buildModernAppBar(
    BuildContext context,
    bool isDark,
    Color cardBg,
  ) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: AppBar(
        elevation: 0,
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Rewards Store',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
    );
  }

  Widget _buildModernSearchBar(
    BuildContext context,
    bool isDark,
    Color cardBg,
  ) {
    return TextField(
      controller: _searchController,
      onChanged: (_) {
        setState(() {});
      },
      decoration: InputDecoration(
        hintText: 'Search rewards…',
        hintStyle: TextStyle(
          color: isDark ? Colors.grey[500] : Colors.grey[600],
          fontSize: 15,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
        suffixIcon: _searchController.text.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {});
                },
                child: Icon(
                  Icons.clear,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                  size: 20,
                ),
              )
            : null,
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primaryOrange, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chips = [
      ('All', 'default'),
      ('💰 Low to High', 'price_asc'),
      ('💰 High to Low', 'price_desc'),
      ('⭐ Top Rated', 'rating'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(chips.length, (index) {
          final (label, value) = chips[index];
          final isSelected = _sortBy == value;

          return Padding(
            padding: EdgeInsets.only(right: index < chips.length - 1 ? 8 : 0),
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return _ModernFilterChip(
                  label: label,
                  isSelected: isSelected,
                  isDark: isDark,
                  onSelected: () {
                    setState(() => _sortBy = value);
                    _animationController.forward(from: 0);
                  },
                );
              },
            ),
          );
        }),
      ),
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
