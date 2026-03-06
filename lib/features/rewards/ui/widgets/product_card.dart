import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../utils/points_calculator.dart';

const Color _primaryOrange = Color(0xFFF97316);

class ProductCard extends StatefulWidget {
  final ProductModel product;
  final VoidCallback onRequestPressed;
  final VoidCallback? onDetailsPressed;
  final bool isRequesting;

  const ProductCard({
    super.key,
    required this.product,
    required this.onRequestPressed,
    this.onDetailsPressed,
    this.isRequesting = false,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final pointsRequired = PointsCalculator.calculatePointsRequired(
      price: widget.product.price.estimatedPrice,
      pointsPerRupee: widget.product.pointsRule.pointsPerRupee,
      maxPoints: widget.product.pointsRule.maxPoints,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2D2D32) : Colors.grey.shade200;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        scale: _isHovering ? 1.02 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.06),
                blurRadius: _isHovering ? 14 : 10,
                offset: Offset(0, _isHovering ? 8 : 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.isRequesting ? null : widget.onRequestPressed,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImageSection(isDark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitleSection(isDark),
                          const SizedBox(height: 6),
                          _buildRatingSection(isDark),
                          const SizedBox(height: 8),
                          _buildPriceRow(isDark),
                          const SizedBox(height: 6),
                          _buildPointsRow(pointsRequired),
                          const SizedBox(height: 10),
                          _buildActionButtons(isDark),
                        ],
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

  Widget _buildImageSection(bool isDark) {
    final imageUrl = widget.product.imageUrl;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 110,
            height: 110,
            color: isDark ? const Color(0xFF111114) : const Color(0xFFF3F4F6),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _imageFallback(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  )
                : _imageFallback(),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_border,
              size: 16,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleSection(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            widget.product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              letterSpacing: -0.1,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildStatusBadge(widget.product.status),
      ],
    );
  }

  Widget _buildRatingSection(bool isDark) {
    final rating = widget.product.rating;
    if (rating == null || rating <= 0) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(Icons.star_rounded, size: 16, color: Colors.amber[500]),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.amber[400],
          ),
        ),
        if (widget.product.reviewCount != null) ...[
          const SizedBox(width: 6),
          Text(
            '(${widget.product.reviewCount})',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceRow(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '₹${widget.product.price.estimatedPrice.toStringAsFixed(0)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'MRP',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }

  Widget _buildPointsRow(int pointsRequired) {
    return Row(
      children: [
        const Icon(Icons.stars_rounded, size: 18, color: Color(0xFFF9A825)),
        const SizedBox(width: 6),
        Text(
          '$pointsRequired points',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: _primaryOrange,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 42,
            child: ElevatedButton(
              onPressed: widget.isRequesting ? null : widget.onRequestPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: widget.isRequesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      'Request',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: SizedBox(
            height: 42,
            child: OutlinedButton(
              onPressed: widget.onDetailsPressed ?? widget.onRequestPressed,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
                ),
                foregroundColor: isDark ? Colors.grey[200] : Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Icon(Icons.info_outline, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final normalized = status.toLowerCase();
    final color = _statusColor(normalized);
    final label = normalized == 'limited'
        ? 'Limited'
        : normalized == 'available'
        ? 'Available'
        : status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade600,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  MaterialColor _statusColor(String status) {
    switch (status) {
      case 'limited':
        return Colors.amber;
      case 'available':
        return Colors.green;
      case 'outofstock':
      case 'out_of_stock':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _imageFallback() {
    return Center(
      child: Icon(
        Icons.card_giftcard_rounded,
        size: 42,
        color: _primaryOrange.withOpacity(0.5),
      ),
    );
  }
}
