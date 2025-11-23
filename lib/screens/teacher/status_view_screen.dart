import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/status_model.dart';

/// Full-screen WhatsApp-like status/story viewer
class StatusViewScreen extends StatefulWidget {
  final List<StatusModel> statuses;
  final int initialIndex;
  final String? currentUserId;
  final VoidCallback? onStatusDeleted;

  const StatusViewScreen({
    super.key,
    required this.statuses,
    this.initialIndex = 0,
    this.currentUserId,
    this.onStatusDeleted,
  });

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  int _currentIndex = 0;
  Timer? _progressTimer;
  Timer? _autoNextTimer;
  double _progress = 0.0;
  bool _isPaused = false;

  static const int _progressTicks = 120; // 100ms per tick = 12s total

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // Fade animation for text
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _startStatus();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _autoNextTimer?.cancel();
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _startStatus() {
    _progress = 0.0;
    _fadeController.forward(from: 0.0);

    // Mark current status as viewed
    _markAsViewed();

    // Progress bar updates every 100ms
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isPaused && mounted) {
        setState(() {
          _progress += 1.0 / _progressTicks;
          if (_progress >= 1.0) {
            timer.cancel();
            _nextStatus();
          }
        });
      }
    });
  }

  Future<void> _markAsViewed() async {
    if (widget.currentUserId == null) return;

    final currentStatus = widget.statuses[_currentIndex];

    // Don't mark own announcements as viewed
    if (currentStatus.teacherId == widget.currentUserId) return;

    // Check if already viewed
    if (currentStatus.hasBeenViewedBy(widget.currentUserId!)) return;

    try {
      // Add current user to viewedBy array
      await FirebaseFirestore.instance
          .collection('class_highlights')
          .doc(currentStatus.id)
          .update({
            'viewedBy': FieldValue.arrayUnion([widget.currentUserId!]),
          });
    } catch (e) {
      // Silently fail - viewing tracking is not critical
      print('Failed to mark as viewed: $e');
    }
  }

  void _nextStatus() {
    if (_currentIndex < widget.statuses.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _startStatus();
    } else {
      // All statuses viewed, exit
      Navigator.of(context).pop();
    }
  }

  void _previousStatus() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _startStatus();
    }
  }

  void _pauseStatus() {
    setState(() {
      _isPaused = true;
    });
  }

  void _resumeStatus() {
    setState(() {
      _isPaused = false;
    });
  }

  void _handleTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tapPosition = details.globalPosition.dx;

    if (tapPosition < screenWidth / 3) {
      // Left third - go to previous
      _previousStatus();
    } else if (tapPosition > screenWidth * 2 / 3) {
      // Right third - go to next
      _nextStatus();
    }
  }

  Future<void> _deleteCurrentStatus() async {
    final currentStatus = widget.statuses[_currentIndex];

    // Pause the status while showing dialog
    _pauseStatus();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: const Color(0xFF7E57C2).withOpacity(0.3),
              width: 1,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_forever,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Highlight?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'This highlight will be permanently deleted and cannot be recovered.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      _resumeStatus();
      return;
    }

    try {
      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('class_highlights')
          .doc(currentStatus.id)
          .delete();

      // Notify parent
      widget.onStatusDeleted?.call();

      if (!mounted) return;

      // Remove from local list
      widget.statuses.removeAt(_currentIndex);

      // If no more statuses, close viewer
      if (widget.statuses.isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      // Adjust index if needed
      if (_currentIndex >= widget.statuses.length) {
        _currentIndex = widget.statuses.length - 1;
      }

      // Restart with current/next status
      setState(() {});
      _startStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Highlight deleted successfully'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _resumeStatus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Failed to delete: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  bool _canDeleteCurrentStatus() {
    if (widget.currentUserId == null) return false;
    return widget.statuses[_currentIndex].teacherId == widget.currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _handleTapDown,
        onLongPress: _pauseStatus,
        onLongPressEnd: (_) => _resumeStatus(),
        child: Stack(
          children: [
            // Content - PageView of statuses
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.statuses.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return _buildStatusContent(widget.statuses[index]);
              },
            ),

            // Progress bars at the top
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: List.generate(
                    widget.statuses.length,
                    (index) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: LinearProgressIndicator(
                          value: index < _currentIndex
                              ? 1.0
                              : index == _currentIndex
                              ? _progress
                              : 0.0,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Header with teacher info and close button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Teacher avatar
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF7B61FF),
                      child: Text(
                        widget.statuses[_currentIndex].teacherName[0]
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.statuses[_currentIndex].teacherName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            widget
                                .statuses[_currentIndex]
                                .timeRemainingFormatted,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Delete button (only for owner)
                    if (_canDeleteCurrentStatus())
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.withOpacity(0.9),
                              Colors.red.shade700.withOpacity(0.9),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _deleteCurrentStatus,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Delete',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Close button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusContent(StatusModel status) {
    if (status.hasImage) {
      return _buildImageStatus(status);
    } else {
      return _buildTextStatus(status);
    }
  }

  Widget _buildTextStatus(StatusModel status) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFA78BFA), // Light violet
            Color(0xFF7B61FF), // Deep violet
            Color(0xFF6366F1), // Indigo
          ],
        ),
      ),
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              status.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1.4,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  Shadow(
                    color: const Color(0xFF7B61FF).withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageStatus(StatusModel status) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image with blur
        Image.network(
          status.imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Container(
            color: const Color(0xFF1F2937),
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
            ),
          ),
        ),

        // Blur overlay
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(color: Colors.black.withOpacity(0.3)),
        ),

        // Centered clear image
        Center(
          child: Image.network(
            status.imageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),

        // Text overlay if present
        if (status.hasText)
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  status.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
