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

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search messages...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: theme.hintColor),
          ),
          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
              },
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for messages',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '✈️ Works offline',
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages found',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
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
    final displayText =
        message.messageText ??
        (message.pollData != null
            ? '📊 Poll: ${message.pollData!['question'] ?? ''}'
            : '[Media message]');

    return ListTile(
      leading: CircleAvatar(
        child: Text(
          message.senderName.isNotEmpty
              ? message.senderName[0].toUpperCase()
              : '?',
        ),
      ),
      title: Text(
        message.senderName,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(displayText, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        _formatTimestamp(message.timestamp),
        style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
      ),
      onTap: () {
        // Return messageId to navigate to it in chat
        Navigator.pop(context, message.messageId);
      },
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
