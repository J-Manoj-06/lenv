import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../share/incoming_share_data.dart';
import '../share/share_controller.dart';
import '../services/cloudflare_r2_service.dart';
import '../config/cloudflare_config.dart';
import '../services/media_upload_service.dart';
import '../services/local_cache_service.dart';
import '../screens/messages/staff_room_group_chat_page.dart';

/// Page for selecting a chat to forward shared content to
class SelectForwardChatPage extends StatefulWidget {
  final IncomingShareData shareData;

  const SelectForwardChatPage({super.key, required this.shareData});

  @override
  State<SelectForwardChatPage> createState() => _SelectForwardChatPageState();
}

class _SelectForwardChatPageState extends State<SelectForwardChatPage> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatDestination> _allChats = [];
  List<ChatDestination> _filteredChats = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late final MediaUploadService _mediaUploadService;

  @override
  void initState() {
    super.initState();
    _initMediaService();
    _loadChats();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filterChats();
      });
    });
  }

  void _initMediaService() {
    final r2 = CloudflareR2Service(
      accountId: CloudflareConfig.accountId,
      bucketName: CloudflareConfig.bucketName,
      accessKeyId: CloudflareConfig.accessKeyId,
      secretAccessKey: CloudflareConfig.secretAccessKey,
      r2Domain: CloudflareConfig.r2Domain,
    );

    _mediaUploadService = MediaUploadService(
      r2Service: r2,
      firestore: FirebaseFirestore.instance,
      cacheService: LocalCacheService(),
    );
  }

  Future<void> _loadChats() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      final List<ChatDestination> chats = [];

      // Add Staff Room (always available for principal)
      chats.add(
        ChatDestination(
          id: 'staff_room_${currentUser.instituteId}',
          name: 'Staff Room',
          type: ChatType.staffRoom,
          instituteId: currentUser.instituteId ?? '',
          memberCount: null,
        ),
      );

      setState(() {
        _allChats = chats;
        _filteredChats = chats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading chats: $e')));
      }
    }
  }

  void _filterChats() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _filteredChats = _allChats;
      });
    } else {
      setState(() {
        _filteredChats = _allChats
            .where((chat) => chat.name.toLowerCase().contains(_searchQuery))
            .toList();
      });
    }
  }

  void _showForwardConfirmation(ChatDestination destination) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Send to ${destination.name}?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _forwardToChat(destination);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF146D7A),
                    ),
                    child: const Text(
                      'Send',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _forwardToChat(ChatDestination destination) async {
    final shareController = Provider.of<ShareController>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    shareController.setProcessing(true);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Forwarding...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final messageData = <String, dynamic>{
        'senderId': currentUser.uid,
        'senderName': currentUser.name,
        'senderRole': currentUser.role.toString(),
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isForwarded': true,
        'forwardedFrom': 'External App',
      };

      // Handle different content types
      if (widget.shareData.hasText) {
        messageData['text'] = widget.shareData.text;
      } else {
        messageData['text'] = '';
      }

      // Handle files
      if (widget.shareData.hasFiles) {
        final file = File(widget.shareData.files.first);

        // Upload file
        final mediaMessage = await _mediaUploadService.uploadMedia(
          file: file,
          conversationId: destination.id,
          senderId: currentUser.uid,
          senderRole: currentUser.role.toString(),
          mediaType: 'forwarded',
          onProgress: (progress) {},
        );

        messageData['attachmentUrl'] = mediaMessage.r2Url;
        messageData['attachmentType'] = mediaMessage.fileType;
        messageData['attachmentName'] = mediaMessage.fileName;
        messageData['thumbnailUrl'] = mediaMessage.thumbnailUrl;
      }

      // Send to appropriate collection based on chat type
      if (destination.type == ChatType.staffRoom) {
        await FirebaseFirestore.instance
            .collection('staff_rooms')
            .doc(destination.instituteId)
            .collection('messages')
            .add(messageData);
      }

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Show success and navigate
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Forwarded successfully')),
        );

        // Clear share data
        shareController.clearShareData();

        // Navigate to the chat
        if (destination.type == ChatType.staffRoom) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => StaffRoomGroupChatPage(
                instituteId: destination.instituteId,
                instituteName: currentUser.name,
                isTeacher: false,
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      shareController.setProcessing(false);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to forward: $e')));
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF130F23)
          : const Color(0xFFF6F5F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF146D7A),
        foregroundColor: Colors.white,
        title: const Text('Forward to...'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1A2F) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Share preview
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1A2F) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF146D7A).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getIconForType(widget.shareData.type),
                  color: const Color(0xFF146D7A),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getTypeLabel(widget.shareData.type),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (widget.shareData.hasText)
                        Text(
                          widget.shareData.text!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      if (widget.shareData.hasFiles)
                        Text(
                          '${widget.shareData.files.length} file(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Chat list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredChats.isEmpty
                ? Center(
                    child: Text(
                      'No chats available',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredChats.length,
                    itemBuilder: (context, index) {
                      final chat = _filteredChats[index];
                      return _ChatTile(
                        chat: chat,
                        isDark: isDark,
                        onTap: () => _showForwardConfirmation(chat),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(ShareContentType type) {
    switch (type) {
      case ShareContentType.text:
        return Icons.text_fields;
      case ShareContentType.image:
        return Icons.image;
      case ShareContentType.audio:
        return Icons.audiotrack;
      case ShareContentType.file:
        return Icons.insert_drive_file;
      case ShareContentType.mixed:
        return Icons.attach_file;
    }
  }

  String _getTypeLabel(ShareContentType type) {
    switch (type) {
      case ShareContentType.text:
        return 'Text Message';
      case ShareContentType.image:
        return 'Image';
      case ShareContentType.audio:
        return 'Audio';
      case ShareContentType.file:
        return 'File';
      case ShareContentType.mixed:
        return 'Multiple Items';
    }
  }
}

class _ChatTile extends StatelessWidget {
  final ChatDestination chat;
  final bool isDark;
  final VoidCallback onTap;

  const _ChatTile({
    required this.chat,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A2F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF146D7A).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.business, color: Color(0xFF146D7A)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (chat.memberCount != null)
                        Text(
                          '${chat.memberCount} members',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Model for chat destinations
class ChatDestination {
  final String id;
  final String name;
  final ChatType type;
  final String instituteId;
  final int? memberCount;

  ChatDestination({
    required this.id,
    required this.name,
    required this.type,
    required this.instituteId,
    this.memberCount,
  });
}

enum ChatType { staffRoom, groupChat, community }
