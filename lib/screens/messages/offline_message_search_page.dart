import 'package:flutter/material.dart';
import '../../models/local_message.dart';
import '../../repositories/local_message_repository.dart';

/// Offline-first Message Search Page
/// WHY: Search works completely offline using local database
/// - NO Firebase queries during search
/// - Instant results from local DB
/// - Works in airplane mode
class OfflineMessageSearchPage extends StatefulWidget {
  final String chatId;
  final String chatType;

  const OfflineMessageSearchPage({
    super.key,
    required this.chatId,
    required this.chatType,
  });

  @override
  State<OfflineMessageSearchPage> createState() =>
      _OfflineMessageSearchPageState();
}

class _OfflineMessageSearchPageState extends State<OfflineMessageSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final LocalMessageRepository _localRepo = LocalMessageRepository();

  List<LocalMessage> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _localRepo.initialize();
    _searchController.addListener(_performSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Perform search in local database
  /// WHY: All search happens in local DB - NO Firebase queries
  Future<void> _performSearch() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Search only in this chat's messages (offline)
      final results = await _localRepo.searchMessages(
        query,
        chatId: widget.chatId,
        limit: 500,
      );

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });

      // Debug: Show detailed info about search results
      if (results.isNotEmpty) {
        print('📋 Search results details:');
        for (var i = 0; i < results.take(5).length; i++) {
          final msg = results[i];
          print('   [$i] ChatId: ${msg.chatId}');
          print(
            '       Message: ${msg.messageText?.substring(0, msg.messageText!.length > 50 ? 50 : msg.messageText!.length)}...',
          );
          print('       Sender: ${msg.senderId}');
        }
      }
    } catch (e) {
      print('❌ Search error: $e');
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF111B21)
          : const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF1F2C34)
            : const Color(0xFF008069),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Search',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search input container
          Container(
            color: isDark ? const Color(0xFF1F2C34) : const Color(0xFF008069),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111B21) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF8696A0)
                      : const Color(0xFF008069),
                  width: 2,
                ),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Messages, files, audio...',
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close,
                            color: isDark
                                ? const Color(0xFF8696A0)
                                : Colors.grey[600],
                          ),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          // Search results
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Search Messages',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Find messages, PDFs, images, or audio files',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2C34) : Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flight_takeoff,
                    size: 16,
                    color: isDark
                        ? const Color(0xFF00A884)
                        : const Color(0xFF008069),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Works offline',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF00A884)
                          : const Color(0xFF008069),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(
          color: isDark ? const Color(0xFF00A884) : const Color(0xFF008069),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? const Color(0xFF8696A0) : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No messages found',
              style: TextStyle(
                color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final message = _searchResults[index];
        return _buildSearchResultItem(message, theme);
      },
    );
  }

  Widget _buildSearchResultItem(LocalMessage message, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final displayText =
        message.messageText ??
        (message.pollData != null
            ? '📊 Poll: ${message.pollData!['question'] ?? ''}'
            : '[Media message]');

    // Highlight search term in message text
    final searchQuery = _searchController.text.toLowerCase();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1F2C34) : Colors.grey[200]!,
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isDark
              ? const Color(0xFF00A884)
              : const Color(0xFF008069),
          child: Text(
            message.senderName.isNotEmpty
                ? message.senderName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          message.senderName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            displayText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
            ),
          ),
        ),
        trailing: Text(
          _formatTimestamp(message.timestamp),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF8696A0) : Colors.grey[500],
          ),
        ),
        onTap: () {
          // Dismiss keyboard before navigating back
          FocusScope.of(context).unfocus();

          // Return messageId to navigate to it in chat
          Navigator.pop(context, message.messageId);
        },
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
