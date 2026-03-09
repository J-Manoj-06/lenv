import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Generic Message Search Page
/// Works with any chat collection structure
///
/// Usage:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => MessageSearchPage(
///       collectionPath: 'chats/$chatId/messages',
///       onMessageSelected: (messageId, messageData) {
///         // Handle navigation back and scroll
///       },
///     ),
///   ),
/// );
/// ```
class MessageSearchPage extends StatefulWidget {
  final String collectionPath; // e.g., 'chats/{chatId}/messages'
  final Function(String messageId, Map<String, dynamic> messageData)
  onMessageSelected;
  final Color primaryColor;
  final String searchHint;

  const MessageSearchPage({
    super.key,
    required this.collectionPath,
    required this.onMessageSelected,
    this.primaryColor = const Color(0xFF00A884),
    this.searchHint = 'Search messages...',
  });

  @override
  State<MessageSearchPage> createState() => _MessageSearchPageState();
}

class _MessageSearchPageState extends State<MessageSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _allMessages = [];
  List<Map<String, dynamic>> _filteredMessages = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _searchController.addListener(_performSearch);

    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_performSearch);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Load all messages from Firestore once
  /// We fetch locally to enable fast, flexible searching
  Future<void> _loadMessages() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Fetch messages ordered by timestamp (latest first)
      // Try timestamp first (community/group chats), fallback to createdAt (other chats)
      QuerySnapshot snapshot;
      try {
        snapshot = await FirebaseFirestore.instance
            .collection(widget.collectionPath)
            .orderBy('timestamp', descending: true)
            .limit(500) // Limit to recent 500 messages for performance
            .get();
      } catch (e) {
        // If timestamp field doesn't exist, try createdAt
        snapshot = await FirebaseFirestore.instance
            .collection(widget.collectionPath)
            .orderBy('createdAt', descending: true)
            .limit(500)
            .get();
      }

      _allMessages = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        data['id'] = doc.id; // Add document ID
        return data;
      }).toList();

      setState(() {
        _isLoading = false;
        _filteredMessages = []; // Start with empty results
      });
    } catch (e) {
      print('❌ Error loading messages: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  /// Perform local search with case-insensitive partial matching
  void _performSearch() {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _filteredMessages = [];
      });
      return;
    }

    // Filter messages that contain the search query
    final results = _allMessages.where((message) {
      // Check both 'message' (community/group) and 'text' (other chats) fields
      final messageText = (message['message'] ?? message['text'] ?? '')
          .toString()
          .toLowerCase();
      final attachmentName = (message['attachmentName'] ?? '')
          .toString()
          .toLowerCase();

      // Get media metadata for audio/document names
      String mediaName = '';
      if (message['mediaMetadata'] != null) {
        final metadata = message['mediaMetadata'];
        if (metadata is Map) {
          mediaName = (metadata['fileName'] ?? metadata['name'] ?? '')
              .toString()
              .toLowerCase();
        }
      }

      // Check poll question if message is a poll
      String pollQuestion = '';
      if (message['type'] == 'poll' && message['poll'] != null) {
        final poll = message['poll'];
        if (poll is Map) {
          pollQuestion = (poll['question'] ?? '').toString().toLowerCase();
        }
      }

      // Search only in message content — NOT in sender name
      // Results where only the sender name matched are excluded intentionally
      return messageText.contains(query) ||
          attachmentName.contains(query) ||
          mediaName.contains(query) ||
          pollQuestion.contains(query);
    }).toList();

    setState(() {
      _filteredMessages = results;
    });
  }

  /// Format timestamp for display
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      return '';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${DateFormat('HH:mm').format(dateTime)}';
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat('EEE HH:mm').format(dateTime);
    } else {
      return DateFormat('MMM dd, HH:mm').format(dateTime);
    }
  }

  /// Get icon based on message type
  IconData _getMessageIcon(Map<String, dynamic> message) {
    final attachmentType = message['attachmentType'] as String?;

    if (attachmentType != null) {
      if (attachmentType.startsWith('image/')) return Icons.image_outlined;
      if (attachmentType.startsWith('audio/')) return Icons.audiotrack;
      if (attachmentType == 'application/pdf') {
        return Icons.picture_as_pdf_outlined;
      }
      return Icons.attach_file;
    }

    return Icons.chat_bubble_outline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF222222) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: widget.searchHint,
            hintStyle: TextStyle(color: subtitleColor),
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          textInputAction: TextInputAction.search,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear, color: subtitleColor),
              onPressed: () {
                _searchController.clear();
                _searchFocusNode.requestFocus();
              },
            ),
        ],
      ),
      body: _buildBody(theme, isDark, textColor, subtitleColor, cardColor),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    bool isDark,
    Color textColor,
    Color subtitleColor,
    Color cardColor,
  ) {
    // Loading state
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: widget.primaryColor),
            const SizedBox(height: 16),
            Text('Loading messages...', style: TextStyle(color: subtitleColor)),
          ],
        ),
      );
    }

    // Error state
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load messages',
              style: TextStyle(color: textColor, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadMessages,
              child: Text(
                'Retry',
                style: TextStyle(color: widget.primaryColor),
              ),
            ),
          ],
        ),
      );
    }

    // Empty search state
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: widget.primaryColor.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search messages',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type to search in this conversation',
              style: TextStyle(color: subtitleColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // No results
    if (_filteredMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.red.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(color: textColor, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords',
              style: TextStyle(color: subtitleColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Results list
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '${_filteredMessages.length} result${_filteredMessages.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: subtitleColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: _filteredMessages.length,
            itemBuilder: (context, index) {
              final message = _filteredMessages[index];
              final messageId = message['id'] as String;

              // Support both 'message' and 'text' fields
              String text = (message['message'] ?? message['text'] ?? '')
                  .toString();

              // Check if it's a poll message
              if (message['type'] == 'poll' && message['poll'] != null) {
                final poll = message['poll'];
                if (poll is Map && poll['question'] != null) {
                  text = '📊 Poll: ${poll['question']}';
                }
              }

              final senderName = (message['senderName'] ?? 'Unknown')
                  .toString();
              // Support both 'timestamp' and 'createdAt' fields
              final timestamp = message['timestamp'] ?? message['createdAt'];
              final icon = _getMessageIcon(message);

              // Highlight search query in text
              final query = _searchController.text.trim().toLowerCase();
              final displayText = text.isNotEmpty
                  ? text
                  : (message['attachmentName'] ?? 'Media message');

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      final attachmentType =
                          (message['attachmentType'] as String? ?? '')
                              .toLowerCase();
                      final msgType = (message['type'] as String? ?? '')
                          .toLowerCase();

                      // Plain text message → no-op, stays static in list
                      if (attachmentType.isEmpty &&
                          msgType != 'image' &&
                          msgType != 'photo') {
                        return;
                      }

                      // Image → open in-app full-screen viewer
                      if (attachmentType.startsWith('image/') ||
                          msgType == 'image' ||
                          msgType == 'photo') {
                        final url =
                            (message['attachmentUrl'] ??
                                    message['url'] ??
                                    message['mediaUrl'] ??
                                    '')
                                as String;
                        if (url.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _InAppImageViewer(imageUrl: url),
                            ),
                          );
                        }
                        return;
                      }

                      // Documents / audio / other → existing callback
                      widget.onMessageSelected(messageId, message);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: widget.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              icon,
                              color: widget.primaryColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        senderName,
                                        style: TextStyle(
                                          color: widget.primaryColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      _formatTimestamp(timestamp),
                                      style: TextStyle(
                                        color: subtitleColor,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                _buildHighlightedText(
                                  displayText,
                                  query,
                                  textColor,
                                  subtitleColor,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build text with highlighted search query
  Widget _buildHighlightedText(
    String text,
    String query,
    Color textColor,
    Color subtitleColor,
  ) {
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: subtitleColor, fontSize: 14),
      );
    }

    final textLower = text.toLowerCase();
    final queryLower = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (start < text.length) {
      final index = textLower.indexOf(queryLower, start);

      if (index == -1) {
        // No more matches, add remaining text
        spans.add(
          TextSpan(
            text: text.substring(start),
            style: TextStyle(color: subtitleColor),
          ),
        );
        break;
      }

      // Add text before match
      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: TextStyle(color: subtitleColor),
          ),
        );
      }

      // Add highlighted match
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            color: textColor,
            backgroundColor: widget.primaryColor.withOpacity(0.3),
            fontWeight: FontWeight.w600,
          ),
        ),
      );

      start = index + query.length;
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans, style: const TextStyle(fontSize: 14)),
    );
  }
}

/// Full-screen in-app image viewer — used only by search results.
class _InAppImageViewer extends StatelessWidget {
  final String imageUrl;
  const _InAppImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
