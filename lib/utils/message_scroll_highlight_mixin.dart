import 'package:flutter/material.dart';
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
    // Cancel any existing highlight timer
    _highlightTimer?.cancel();

    // Set highlighted message
    if (mounted) {
      setState(() {
        _highlightedMessageId = messageId;
      });
    }

    // Wait for keyboard to dismiss and UI to settle
    await Future.delayed(const Duration(milliseconds: 600));

    // Find message index
    final messageIndex = messages.indexWhere((msg) {
      if (msg is Map) {
        return msg['id'] == messageId;
      }
      return false;
    });

    if (messageIndex == -1) {
      _clearHighlight();
      return;
    }

    // Try key-based scroll first (most accurate when widget is rendered)
    await Future.delayed(
      const Duration(milliseconds: 100),
    ); // Let widgets render
    final success = await _scrollToMessageByKey(messageId);

    if (!success) {
      // Fallback to index-based scroll with improved calculations
      await _scrollByIndexImproved(messageIndex, messages.length);
    }

    _scheduleHighlightClear(highlightDuration);
  }

  /// Scroll to message using its GlobalKey (most accurate method)
  Future<bool> _scrollToMessageByKey(String messageId) async {
    try {
      final key = _messageKeys[messageId];
      if (key == null || key.currentContext == null) {
        return false;
      }

      final context = key.currentContext!;
      final renderObject = context.findRenderObject();

      if (renderObject == null || !renderObject.attached) {
        return false;
      }

      // Use Scrollable.ensureVisible to scroll the message into view
      // alignment: 0.5 = center of viewport
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        alignment: 0.5, // Center in viewport
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Improved index-based scroll with better accuracy
  Future<void> _scrollByIndexImproved(int index, int totalMessages) async {
    if (!scrollController.hasClients) {
      return;
    }

    final maxScroll = scrollController.position.maxScrollExtent;
    final viewportHeight = scrollController.position.viewportDimension;

    // Calculate the percentage position in the list
    // For reverse list: index 0 = bottom (newest), high index = top (oldest)
    final percentage = (totalMessages - index - 1) / totalMessages;

    // Calculate target scroll position
    // We want to center the message in viewport
    final targetOffset = (maxScroll * percentage) - (viewportHeight * 0.25);

    // Clamp to valid range
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);

    await scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );

    // Wait for animation to complete
    await Future.delayed(const Duration(milliseconds: 100));
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
