import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';

/// Mixin to add scroll-to-message and highlight functionality
/// to any chat screen with a ListView
///
/// Usage:
/// ```dart
/// class _MyChatPageState extends State<MyChatPage>
///     with MessageScrollAndHighlightMixin {
///
///   @override
///   void initState() {
///     super.initState();
///     initializeScrollController(); // Initialize the scroll controller
///   }
///
///   // In your ListView.builder:
///   itemBuilder: (context, index) {
///     final messageId = messages[index].id;
///     final isHighlighted = highlightedMessageId == messageId;
///
///     return Container(
///       key: getMessageKey(messageId), // Assign key to each message
///       child: MessageBubble(
///         message: messages[index],
///         isHighlighted: isHighlighted,
///       ),
///     );
///   }
/// }
/// ```
mixin MessageScrollAndHighlightMixin<T extends StatefulWidget> on State<T> {
  /// Scroll controller for the message list
  ScrollController? _scrollController;

  /// Getter for scroll controller - initializes if needed
  ScrollController get scrollController {
    _scrollController ??= ScrollController(keepScrollOffset: true);
    return _scrollController!;
  }

  /// Map to store GlobalKeys for each message
  final Map<String, GlobalKey> _messageKeys = {};

  /// Currently highlighted message ID
  String? _highlightedMessageId;

  /// Timer for highlight animation
  Timer? _highlightTimer;

  /// Getter for highlighted message ID
  String? get highlightedMessageId => _highlightedMessageId;

  /// Initialize scroll controller (now optional since it auto-initializes)
  /// Keep for backward compatibility
  @Deprecated('ScrollController now initializes automatically')
  void initializeScrollController() {
    // No-op - kept for backward compatibility
  }

  /// Get or create a GlobalKey for a message
  /// Use this in ListView.builder to assign keys
  GlobalKey getMessageKey(String messageId) {
    if (!_messageKeys.containsKey(messageId)) {
      _messageKeys[messageId] = GlobalKey();
    }
    return _messageKeys[messageId]!;
  }

  /// Scroll to a specific message and highlight it
  ///
  /// [messageId] - The ID of the message to scroll to
  /// [messages] - List of all messages (to find the index)
  /// [highlightDuration] - How long to show the highlight (default 2 seconds)
  Future<void> scrollToMessage(
    String messageId,
    List<dynamic> messages, {
    Duration highlightDuration = const Duration(seconds: 2),
  }) async {
    print('🎯 Scrolling to message: $messageId');

    // Cancel any existing highlight timer
    _highlightTimer?.cancel();

    // Set highlighted message
    if (mounted) {
      setState(() {
        _highlightedMessageId = messageId;
      });
    }

    // Wait for keyboard animation to complete
    await Future.delayed(const Duration(milliseconds: 500));

    // Find message index
    final messageIndex = messages.indexWhere((msg) {
      if (msg is Map) {
        return msg['id'] == messageId;
      }
      return false;
    });

    if (messageIndex == -1) {
      print('❌ Message not found in list: $messageId');
      _clearHighlight();
      return;
    }

    print('✅ Found message at index: $messageIndex');

    // Use index-based scroll - simple and reliable
    await _scrollByIndex(messageIndex, messages.length, animate: true);

    _scheduleHighlightClear(highlightDuration);
  }

  /// Fallback: scroll by index if key-based scroll fails
  Future<void> _scrollByIndex(
    int index,
    int totalMessages, {
    bool animate = true,
  }) async {
    if (!scrollController.hasClients) return;

    // Estimate item height (more conservative estimate for better accuracy)
    const estimatedItemHeight = 80.0;
    const paddingBetweenMessages = 8.0;

    // Calculate scroll position for reverse list
    // In reverse lists, index 0 is at bottom (offset 0)
    // Higher indices are further up (higher offset)
    // So we need to calculate from the current position

    // For reverse list, we want to scroll UP to see older messages
    // Calculate position from bottom: (totalMessages - index - 1) * (height + padding)
    final positionFromBottom =
        (totalMessages - index - 1) *
        (estimatedItemHeight + paddingBetweenMessages);

    // Get current viewport height
    final viewportHeight = scrollController.position.viewportDimension;

    // Calculate offset to center the message in viewport
    final targetOffset =
        positionFromBottom -
        (viewportHeight / 3); // Position in upper third for better visibility

    // Clamp to valid range
    final clampedOffset = targetOffset.clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );

    print(
      '📍 Index-based scroll: index=$index, total=$totalMessages, target=$clampedOffset',
    );

    if (animate) {
      await scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      scrollController.jumpTo(clampedOffset);
    }
  }

  /// Schedule highlight clearing after duration
  void _scheduleHighlightClear(Duration duration) {
    _highlightTimer?.cancel();
    _highlightTimer = Timer(duration, _clearHighlight);
  }

  /// Clear the highlight effect
  void _clearHighlight() {
    if (mounted) {
      setState(() {
        _highlightedMessageId = null;
      });
    }
  }

  /// Clean up resources
  /// Call this in dispose()
  void disposeScrollController() {
    _highlightTimer?.cancel();
    _scrollController?.dispose();
    _scrollController = null;
    _messageKeys.clear();
  }

  /// Remove keys for messages that no longer exist
  /// Call this when messages are deleted or list changes
  void cleanupMessageKeys(List<String> currentMessageIds) {
    final currentIds = currentMessageIds.toSet();
    _messageKeys.removeWhere((key, _) => !currentIds.contains(key));
  }
}

/// Widget to wrap message bubbles with highlight animation
///
/// Usage:
/// ```dart
/// HighlightedMessageWrapper(
///   isHighlighted: isHighlighted,
///   highlightColor: Colors.yellow.withOpacity(0.3),
///   child: MessageBubble(message: message),
/// )
/// ```
class HighlightedMessageWrapper extends StatefulWidget {
  final Widget child;
  final bool isHighlighted;
  final Color highlightColor;
  final Duration animationDuration;

  const HighlightedMessageWrapper({
    super.key,
    required this.child,
    required this.isHighlighted,
    this.highlightColor = const Color(0xFFFFEB3B),
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<HighlightedMessageWrapper> createState() =>
      _HighlightedMessageWrapperState();
}

class _HighlightedMessageWrapperState extends State<HighlightedMessageWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _colorAnimation =
        ColorTween(
          begin: widget.highlightColor.withOpacity(0.0),
          end: widget.highlightColor.withOpacity(0.5),
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
  }

  @override
  void didUpdateWidget(HighlightedMessageWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isHighlighted && !oldWidget.isHighlighted) {
      // Start highlight animation
      _animationController.forward().then((_) {
        _animationController.reverse();
      });
    } else if (!widget.isHighlighted && oldWidget.isHighlighted) {
      // Stop highlight animation
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: _colorAnimation.value,
            borderRadius: BorderRadius.circular(12),
          ),
          child: widget.child,
        );
      },
    );
  }
}
