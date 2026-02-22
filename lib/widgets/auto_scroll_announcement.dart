import 'package:flutter/material.dart';

/// Auto-scrolling announcement widget with "Read More" functionality
///
/// Features:
/// - Auto-scrolls vertically when text is long
/// - Shows "Read More" button if content exceeds maxCollapsedHeight
/// - Pauses auto-scroll and expands on "Read More" tap
/// - Enables manual scrolling when expanded
/// - Clean UI suitable for educational apps
class AutoScrollAnnouncement extends StatefulWidget {
  final String title;
  final String content;
  final String? postedBy;
  final DateTime? timestamp;
  final double maxCollapsedHeight;
  final Duration scrollDuration;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? accentColor;

  const AutoScrollAnnouncement({
    super.key,
    required this.title,
    required this.content,
    this.postedBy,
    this.timestamp,
    this.maxCollapsedHeight = 150.0,
    this.scrollDuration = const Duration(seconds: 15),
    this.backgroundColor,
    this.textColor,
    this.accentColor,
  });

  @override
  State<AutoScrollAnnouncement> createState() => _AutoScrollAnnouncementState();
}

class _AutoScrollAnnouncementState extends State<AutoScrollAnnouncement>
    with SingleTickerProviderStateMixin {
  late AnimationController _scrollController;
  late Animation<double> _scrollAnimation;
  final ScrollController _manualScrollController = ScrollController();

  bool _isExpanded = false;
  bool _needsReadMore = false;
  double _contentHeight = 0;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller for auto-scroll
    _scrollController = AnimationController(
      duration: widget.scrollDuration,
      vsync: this,
    );

    _scrollAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scrollController, curve: Curves.linear));

    // Measure content height after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureContent();
    });
  }

  void _measureContent() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.content,
        style: TextStyle(
          fontSize: 14,
          color: widget.textColor ?? Colors.black87,
        ),
      ),
      maxLines: null,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: MediaQuery.of(context).size.width - 48);
    _contentHeight = textPainter.size.height;

    setState(() {
      _needsReadMore = _contentHeight > widget.maxCollapsedHeight;

      // Start auto-scroll if content is long
      if (_needsReadMore) {
        _startAutoScroll();
      }
    });
  }

  void _startAutoScroll() {
    if (!_isExpanded && mounted) {
      _scrollController.repeat();
    }
  }

  void _stopAutoScroll() {
    if (mounted) {
      _scrollController.stop();
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;

      if (_isExpanded) {
        _stopAutoScroll();
      } else {
        _startAutoScroll();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _manualScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        widget.backgroundColor ??
        (isDark ? const Color(0xFF1E1E1E) : Colors.white);
    final txtColor =
        widget.textColor ?? (isDark ? Colors.white : Colors.black87);
    final accent = widget.accentColor ?? const Color(0xFF7A5CFF);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with icon and title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.campaign, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: txtColor,
                        ),
                      ),
                      if (widget.postedBy != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Posted by ${widget.postedBy}',
                          style: TextStyle(
                            fontSize: 12,
                            color: txtColor.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.timestamp != null)
                  Text(
                    _formatTimestamp(widget.timestamp!),
                    style: TextStyle(
                      fontSize: 11,
                      color: txtColor.withOpacity(0.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Content area with auto-scroll or manual scroll
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _isExpanded ? null : widget.maxCollapsedHeight,
              constraints: _isExpanded
                  ? const BoxConstraints(maxHeight: 400)
                  : null,
              child: _isExpanded
                  ? _buildExpandedContent(txtColor)
                  : _buildCollapsedContent(txtColor),
            ),

            // Read More / Read Less button
            if (_needsReadMore) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _toggleExpanded,
                  icon: Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: accent,
                  ),
                  label: Text(
                    _isExpanded ? 'Read Less' : 'Read More',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedContent(Color textColor) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _scrollAnimation,
        builder: (context, child) {
          final maxScroll = _contentHeight - widget.maxCollapsedHeight;
          final scrollOffset = maxScroll > 0
              ? maxScroll * _scrollAnimation.value
              : 0.0;

          return Transform.translate(
            offset: Offset(0, -scrollOffset),
            child: child,
          );
        },
        child: Text(
          widget.content,
          style: TextStyle(fontSize: 14, color: textColor, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(Color textColor) {
    return SingleChildScrollView(
      controller: _manualScrollController,
      child: Text(
        widget.content,
        style: TextStyle(fontSize: 14, color: textColor, height: 1.5),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}
