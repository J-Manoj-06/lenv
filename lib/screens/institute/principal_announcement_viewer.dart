import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/institute_announcement_model.dart';
import '../../services/institute_announcement_service.dart';

/// Principal's own announcement viewer with delete functionality
class PrincipalAnnouncementViewer extends StatefulWidget {
  final List<InstituteAnnouncementModel> announcements;
  final int initialIndex;
  final String currentUserId;
  final bool allowDelete;

  const PrincipalAnnouncementViewer({
    super.key,
    required this.announcements,
    this.initialIndex = 0,
    required this.currentUserId,
    this.allowDelete = true,
  });

  @override
  State<PrincipalAnnouncementViewer> createState() =>
      _PrincipalAnnouncementViewerState();
}

class _PrincipalAnnouncementViewerState
    extends State<PrincipalAnnouncementViewer>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  late AnimationController _progressController;
  late Animation<double> _progress;
  final _announcementService = InstituteAnnouncementService();
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progress = CurvedAnimation(
      parent: _progressController,
      curve: Curves.linear,
    );
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_currentIndex < widget.announcements.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          if (mounted) Navigator.of(context).maybePop();
        }
      }
    });
    _progressController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _progressController.reset();
    _progressController.forward();
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(dt);
  }

  String _expiryText(DateTime? expiresAt) {
    if (expiresAt == null) return '';
    final now = DateTime.now();
    final diff = expiresAt.difference(now);
    if (diff.isNegative) return 'Expired';
    if (diff.inHours >= 24) {
      final days = (diff.inHours / 24).floor();
      return 'Expires in ${days}d';
    }
    return 'Expires in ${diff.inHours} hrs';
  }

  Future<void> _deleteAnnouncement() async {
    if (!widget.allowDelete) return;
    final announcement = widget.announcements[_currentIndex];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Delete Announcement?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently delete the announcement for all users.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      // Delete from Firestore (includes views subcollection and image)
      await _announcementService.deleteAnnouncement(
        announcement.id,
        announcement.imageUrl,
      );

      if (!mounted) return;

      // Remove from local list
      widget.announcements.removeAt(_currentIndex);

      // Close viewer if no announcements left
      if (widget.announcements.isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      // Move to previous or next announcement
      if (_currentIndex >= widget.announcements.length) {
        _currentIndex = widget.announcements.length - 1;
      }

      // Refresh page
      setState(() {
        _isDeleting = false;
      });
      _pageController.jumpToPage(_currentIndex);
      _progressController.reset();
      _progressController.forward();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Announcement deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: widget.announcements.length,
            itemBuilder: (context, index) {
              final announcement = widget.announcements[index];
              const theme = Color(0xFF146D7A); // Teal for principal
              const bgColor = Colors.black; // Changed to black background

              return Scaffold(
                backgroundColor: bgColor,
                body: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final width = MediaQuery.of(context).size.width;
                    final dx = details.globalPosition.dx;
                    if (dx < width * 0.33) {
                      if (_currentIndex > 0) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      }
                    } else if (dx > width * 0.67) {
                      if (_currentIndex < widget.announcements.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      } else {
                        Navigator.of(context).maybePop();
                      }
                    }
                  },
                  child: Stack(
                    children: [
                      // Black background (removed gradient)
                      Positioned.fill(child: Container(color: Colors.black)),

                      // Content
                      SafeArea(
                        child: Column(
                          children: [
                            // Header with progress and delete button
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                12,
                              ),
                              child: Column(
                                children: [
                                  // Progress bars
                                  if (widget.announcements.length > 1)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Row(
                                        children: List.generate(
                                          widget.announcements.length,
                                          (i) => Expanded(
                                            child: Container(
                                              height: 3,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  i == _currentIndex
                                                      ? 0.8
                                                      : 0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(9999),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: i == _currentIndex
                                                  ? AnimatedBuilder(
                                                      animation: _progress,
                                                      builder: (context, _) {
                                                        return Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child:
                                                              FractionallySizedBox(
                                                                widthFactor:
                                                                    _progress
                                                                        .value,
                                                                child:
                                                                    Container(
                                                                      color:
                                                                          theme,
                                                                    ),
                                                              ),
                                                        );
                                                      },
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Top row with metadata and delete button
                                  Row(
                                    children: [
                                      Container(
                                        height: 40,
                                        width: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: theme.withOpacity(0.5),
                                            width: 2,
                                          ),
                                          color: theme,
                                        ),
                                        child: Center(
                                          child: Text(
                                            announcement
                                                    .principalName
                                                    .isNotEmpty
                                                ? announcement.principalName[0]
                                                      .toUpperCase()
                                                : 'P',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Posted by ${announcement.principalName}',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.8,
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _relativeTime(
                                                announcement.createdAt,
                                              ),
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.6,
                                                ),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (widget.allowDelete)
                                        IconButton(
                                          onPressed: _isDeleting
                                              ? null
                                              : _deleteAnnouncement,
                                          icon: _isDeleting
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red,
                                                  size: 24,
                                                ),
                                        ),
                                      // Close button
                                      IconButton(
                                        onPressed: () =>
                                            Navigator.of(context).maybePop(),
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Center content
                            Expanded(
                              child: Center(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Show images with captions if available
                                    if (announcement.imageCaptions != null &&
                                        announcement.imageCaptions!.isNotEmpty)
                                      // Horizontal PageView for multiple images
                                      PageView.builder(
                                        itemCount:
                                            announcement.imageCaptions!.length,
                                        itemBuilder: (context, imageIndex) {
                                          final imageCaption = announcement
                                              .imageCaptions![imageIndex];
                                          return Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              // Image
                                              Image.network(
                                                imageCaption['url']!,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return Container(
                                                        color: Colors.black,
                                                        child: const Center(
                                                          child: Icon(
                                                            Icons.broken_image,
                                                            size: 64,
                                                            color:
                                                                Colors.white54,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                              ),
                                              // Caption overlay at bottom
                                              if (imageCaption['caption']
                                                      ?.isNotEmpty ==
                                                  true)
                                                Positioned(
                                                  bottom: 0,
                                                  left: 0,
                                                  right: 0,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin:
                                                            Alignment.topCenter,
                                                        end: Alignment
                                                            .bottomCenter,
                                                        colors: [
                                                          Colors.transparent,
                                                          Colors.black
                                                              .withOpacity(0.3),
                                                          Colors.black
                                                              .withOpacity(0.7),
                                                        ],
                                                      ),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          24,
                                                          80,
                                                          24,
                                                          24,
                                                        ),
                                                    child: Text(
                                                      imageCaption['caption']!,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      )
                                    else
                                      // Text-only announcement (centered)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(32),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.campaign,
                                                size: 64,
                                                color: theme,
                                              ),
                                              const SizedBox(height: 20),
                                              Text(
                                                announcement.hasText
                                                    ? announcement.text
                                                    : 'Principal Announcement',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            // Footer
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                24,
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(9999),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.08),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.schedule,
                                          size: 16,
                                          color: Colors.white70,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _expiryText(announcement.expiresAt),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.announcements.length > 1) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      '${_currentIndex + 1} / ${widget.announcements.length}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
