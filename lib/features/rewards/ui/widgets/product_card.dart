import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../utils/points_calculator.dart';

const Color _primaryOrange = Color(0xFFF97316);

class ProductCard extends StatefulWidget {
  final ProductModel product;
  final VoidCallback onRequestPressed;
  final bool isRequesting;

  const ProductCard({
    super.key,
    required this.product,
    required this.onRequestPressed,
    this.isRequesting = false,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onHoverStart() {
    setState(() => _isHovering = true);
    _scaleController.forward();
  }

  void _onHoverEnd() {
    setState(() => _isHovering = false);
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final pointsRequired = PointsCalculator.calculatePointsRequired(
      price: widget.product.price.estimatedPrice,
      pointsPerRupee: widget.product.pointsRule.pointsPerRupee,
      maxPoints: widget.product.pointsRule.maxPoints,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final imageBg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);

    return MouseRegion(
      onEnter: (_) => _onHoverStart(),
      onExit: (_) => _onHoverEnd(),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.01).animate(
          CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
        ),
        child: Card(
          elevation: _isHovering ? 8 : 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: cardBg,
          shadowColor: _primaryOrange.withOpacity(0.1),
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Image Section with Modern Design
                  _buildImageSection(context, imageBg),
                  const SizedBox(height: 14),
                  // Product Title and Basic Info
                  _buildTitleSection(context, isDark),
                  const SizedBox(height: 12),
                  // Rating Section
                  if (widget.product.rating != null &&
                      widget.product.rating! > 0)
                    _buildRatingSection(context, isDark),
                  if (widget.product.rating != null &&
                      widget.product.rating! > 0)
                    const SizedBox(height: 10),
                  // Points Required Badge
                  _buildPointsBadge(context, pointsRequired, isDark),
                  const SizedBox(height: 12),
                  // Action Button
                  _buildActionButton(context, pointsRequired),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(BuildContext context, Color imageBg) {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        color: imageBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryOrange.withOpacity(0.15), width: 1),
      ),
      child: Center(
        child: Icon(
          Icons.card_giftcard,
          size: 56,
          color: _primaryOrange.withOpacity(0.6),
        ),
      ),
    );
  }

  Widget _buildTitleSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (widget.product.status == 'available')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Available',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (widget.product.status == 'limited')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Limited',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.amber[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '₹${widget.product.price.estimatedPrice.toStringAsFixed(0)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _primaryOrange,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildRatingSection(BuildContext context, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.star, size: 16, color: Colors.amber[600]),
              const SizedBox(width: 4),
              Text(
                '${widget.product.rating!.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.amber[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ' / 5',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPointsBadge(
    BuildContext context,
    int pointsRequired,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _primaryOrange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryOrange.withOpacity(0.2), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _primaryOrange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.card_giftcard,
              size: 16,
              color: _primaryOrange,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$pointsRequired points required',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _primaryOrange,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, int pointsRequired) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton.icon(
        onPressed: widget.isRequesting ? null : widget.onRequestPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _primaryOrange,
          disabledBackgroundColor: Colors.grey[300],
          disabledForegroundColor: Colors.grey[600],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: widget.isRequesting ? 0 : 2,
        ),
        icon: widget.isRequesting
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                ),
              )
            : const Icon(Icons.shopping_cart, size: 18),
        label: Text(
          widget.isRequesting ? 'Requesting…' : 'Request Item',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
