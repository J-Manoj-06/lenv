import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
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
  List<LocalMessage> _fileResults = [];
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
        _fileResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      // Debug: Show search parameters
      print('🔍 Starting search with:');
      print('   Query: "$query"');
      print('   ChatId: "${widget.chatId}"');
      print('   ChatType: "${widget.chatType}"');

      // First check total messages in DB for this chat
      final totalMessages = await _localRepo.getMessagesForChat(widget.chatId);
      print('   Total messages in this chat: ${totalMessages.length}');

      final messagesWithFiles = totalMessages
          .where((m) => m.attachmentUrl != null && m.attachmentUrl!.isNotEmpty)
          .toList();
      print('   Messages with attachments: ${messagesWithFiles.length}');

      if (messagesWithFiles.isNotEmpty) {
        print('   Sample attachments:');
        for (var i = 0; i < messagesWithFiles.take(3).length; i++) {
          final msg = messagesWithFiles[i];
          print(
            '      [$i] Type: ${msg.attachmentType}, URL: ${msg.attachmentUrl?.substring(0, 50)}...',
          );
        }
      }

      // Search for messages and files in parallel
      final messagesFuture = _localRepo.searchMessages(
        query,
        chatId: widget.chatId,
        limit: 500,
      );

      final filesFuture = _localRepo.searchFilesAndMedia(
        query,
        chatId: widget.chatId,
        limit: 100,
      );

      final results = await Future.wait([messagesFuture, filesFuture]);
      final messages = results[0];
      final files = results[1];

      setState(() {
        _searchResults = messages;
        _fileResults = files;
        _isSearching = false;
      });

      // Debug: Show detailed info about search results
      print('📋 Message results: ${messages.length}');
      print('📁 File results: ${files.length}');

      if (files.isNotEmpty) {
        for (var i = 0; i < files.take(3).length; i++) {
          final file = files[i];
          print('   [$i] ${file.getFileName()} (${file.attachmentType})');
        }
      } else {
        print('   ❌ No files found matching query: "$query"');
      }
    } catch (e, stackTrace) {
      print('❌ Search error: $e');
      print('Stack trace: $stackTrace');
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

    if (_searchResults.isEmpty && _fileResults.isEmpty) {
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
              'No messages or files found',
              style: TextStyle(
                color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        // Message results section
        if (_searchResults.isNotEmpty) ...[
          _buildSectionHeader('Messages', _searchResults.length, theme),
          ..._searchResults.map((msg) => _buildSearchResultItem(msg, theme)),
        ],

        // Files & Media section
        if (_fileResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildSectionHeader('Files & Media', _fileResults.length, theme),
          ..._fileResults.map((msg) => _buildFileResultItem(msg, theme)),
        ],
      ],
    );
  }

  Widget _buildSearchResultItem(LocalMessage message, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final displayText =
        message.messageText ??
        (message.pollData != null
            ? '📊 Poll: ${message.pollData!['question'] ?? ''}'
            : '[Media message]');

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

  Widget _buildSectionHeader(String title, int count, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isDark ? const Color(0xFF1F2C34) : Colors.grey[100],
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF00A884) : const Color(0xFF008069),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF00A884) : const Color(0xFF008069),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileResultItem(LocalMessage message, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final fileName = message.getFileName();
    final fileExtension = message.getFileExtension() ?? '';

    // Get appropriate icon based on file type
    IconData fileIcon;
    Color iconColor;

    if (message.attachmentType?.contains('pdf') == true ||
        fileExtension == 'pdf') {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (message.attachmentType?.contains('image') == true ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)) {
      fileIcon = Icons.image;
      iconColor = Colors.blue;
    } else if (message.attachmentType?.contains('audio') == true ||
        ['mp3', 'wav', 'ogg', 'm4a'].contains(fileExtension)) {
      fileIcon = Icons.audiotrack;
      iconColor = Colors.purple;
    } else if (message.attachmentType?.contains('video') == true ||
        ['mp4', 'mov', 'avi', 'mkv'].contains(fileExtension)) {
      fileIcon = Icons.video_library;
      iconColor = Colors.orange;
    } else {
      fileIcon = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

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
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(fileIcon, color: iconColor, size: 28),
        ),
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
                ),
              ),
              Text(
                ' • ',
                style: TextStyle(
                  color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
                ),
              ),
              Text(
                _formatTimestamp(message.timestamp),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF8696A0) : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: isDark ? const Color(0xFF8696A0) : Colors.grey[400],
        ),
        onTap: () => _openFile(message),
      ),
    );
  }

  Future<void> _openFile(LocalMessage message) async {
    if (message.attachmentUrl == null) return;

    final url = message.attachmentUrl!;
    final fileName = message.getFileName();
    final fileExtension = message.getFileExtension();

    try {
      // For images, try to open directly in browser/viewer
      if (message.attachmentType?.contains('image') == true ||
          ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      // For PDFs and other documents, download and open with external app
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Opening $fileName...')),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final filePath = '${tempDir.path}/${timestamp}_$cleanFileName';

      final dio = Dio();
      await dio.download(url, filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      // Open with appropriate app
      String? mimeType;
      if (message.attachmentType?.contains('pdf') == true ||
          fileExtension == 'pdf') {
        mimeType = 'application/pdf';
      }

      final result = await OpenFilex.open(filePath, type: mimeType);

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status: ${result.message}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error opening file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
