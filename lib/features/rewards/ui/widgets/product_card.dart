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
    final cardBg = isDark ? const Color(0xFF1A1A1F) : Colors.white;
    final imageBg = isDark ? const Color(0xFF0F0F14) : const Color(0xFFF3F4F6);

    return MouseRegion(
      onEnter: (_) => _onHoverStart(),
      onExit: (_) => _onHoverEnd(),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.02).animate(
          CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
        ),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: cardBg,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                  blurRadius: _isHovering ? 16 : 12,
                  offset: Offset(0, _isHovering ? 6 : 4),
                ),
              ],
            ),
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
      ),
    );
  }

  Widget _buildImageSection(BuildContext context, Color imageBg) {
    final imageUrl = widget.product.imageUrl;

    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: imageBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(
                      Icons.card_giftcard_rounded,
                      size: 64,
                      color: _primaryOrange.withOpacity(0.4),
                    ),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                            : null,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                },
              ),
            )
          : Center(
              child: Icon(
                Icons.card_giftcard_rounded,
                size: 64,
                color: _primaryOrange.withOpacity(0.4),
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
                widget.product.rating!.toStringAsFixed(1),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF97316).withOpacity(0.12),
            const Color(0xFFFBBF24).withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF97316).withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.stars_rounded, size: 18, color: Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          Text(
            '$pointsRequired points',
            style: TextStyle(
              fontSize: 14,
              color: _primaryOrange,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, int pointsRequired) {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        gradient: widget.isRequesting
            ? null
            : const LinearGradient(
                colors: [Color(0xFFF97316), Color(0xFFFBBF24)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: widget.isRequesting ? Colors.grey[300] : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: widget.isRequesting
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFFF97316).withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isRequesting ? null : widget.onRequestPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: widget.isRequesting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.grey[600]!,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Requesting…',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[600],
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Request Item',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
