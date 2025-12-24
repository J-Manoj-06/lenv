import 'package:flutter/material.dart';

/// Reusable unread badge widget for all chat types
/// Non-invasive: doesn't affect card layout or tap behavior
class UnreadBadge extends StatelessWidget {
  final int count;
  final Color? backgroundColor;
  final Color textColor;
  final double? badgeSize;
  final double? fontSize;
  
  const UnreadBadge({
    Key? key,
    required this.count,
    this.backgroundColor,
    this.textColor = Colors.white,
    this.badgeSize = 24,
    this.fontSize = 12,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Don't render if count is 0
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    
    // Cap display at 99+
    final displayCount = count > 99 ? '99+' : count.toString();
    
    // Get primary color from theme
    final bgColor = backgroundColor ?? Theme.of(context).primaryColor;
    
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          displayCount,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
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
  final Color textColor;
  final double? badgeSize;
  final double? fontSize;
  final double rightOffset;
  final double topOffset;
  
  const PositionedUnreadBadge({
    Key? key,
    required this.count,
    this.backgroundColor,
    this.textColor = Colors.white,
    this.badgeSize = 24,
    this.fontSize = 12,
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
  final Color textColor;
  
  const InlineUnreadBadge({
    Key? key,
    required this.count,
    this.backgroundColor,
    this.textColor = Colors.white,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    
    final displayCount = count > 99 ? '99+' : count.toString();
    final bgColor = backgroundColor ?? Theme.of(context).primaryColor;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        displayCount,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
