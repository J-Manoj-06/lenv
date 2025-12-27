import 'package:flutter/material.dart';

/// Reusable unread badge widget for all chat types
/// Non-invasive: doesn't affect card layout or tap behavior
class UnreadBadge extends StatelessWidget {
  final int count;
  final Color? backgroundColor;
  final Color? textColor;
  final double? badgeSize;
  final double? fontSize;
  
  const UnreadBadge({
    Key? key,
    required this.count,
    this.backgroundColor,
    this.textColor,
    this.badgeSize = 32,
    this.fontSize = 14,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Don't render if count is 0
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    
    // Cap display at 99+
    final displayCount = count > 99 ? '99+' : count.toString();
    
    // Get theme-aware colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ?? const Color(0xFFF97316); // Orange (primary)
    final textCol = textColor ?? Colors.white;
    
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          displayCount,
          style: TextStyle(
            color: textCol,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }
}

/// Positioned badge for chat card (top-right corner)
class PositionedUnreadBadge extends StatelessWidget {
  final int count;
  final Color? backgroundColor;
  final Color? textColor;
  final double? badgeSize;
  final double? fontSize;
  final double rightOffset;
  final double topOffset;
  
  const PositionedUnreadBadge({
    Key? key,
    required this.count,
    this.backgroundColor,
    this.textColor,
    this.badgeSize = 32,
    this.fontSize = 14,
    this.rightOffset = 8,
    this.topOffset = 8,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Don't render if count is 0
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      right: rightOffset,
      top: topOffset,
      child: UnreadBadge(
        count: count,
        backgroundColor: backgroundColor,
        textColor: textColor,
        badgeSize: badgeSize,
        fontSize: fontSize,
      ),
    );
  }
}

/// Compact inline badge (for use in list tiles)
class InlineUnreadBadge extends StatelessWidget {
  final int count;
  final Color? backgroundColor;
  final Color? textColor;
  
  const InlineUnreadBadge({
    Key? key,
    required this.count,
    this.backgroundColor,
    this.textColor,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    
    final displayCount = count > 99 ? '99+' : count.toString();
    final bgColor = backgroundColor ?? const Color(0xFFF97316);
    final textCol = textColor ?? Colors.white;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        displayCount,
        style: TextStyle(
          color: textCol,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}
