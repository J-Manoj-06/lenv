/// Example Integration: Smart Media Caching in Staff Room Chat
///
/// This file demonstrates how to integrate the smart media caching system
/// into staff_room_chat_page.dart
///
/// Supported Media: Images, Audio, PDF, Documents (no video support)
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/cached_media_message.dart';
import '../models/staff_room_message.dart';
import '../services/media_cache_service.dart';
import '../services/smart_media_upload_service.dart';
import '../widgets/universal_media_widget.dart';

class StaffRoomChatIntegrationExample extends StatefulWidget {
  final String instituteId;
  final String instituteName;

  const StaffRoomChatIntegrationExample({
    super.key,
    required this.instituteId,
    required this.instituteName,
  });

  @override
  State<StaffRoomChatIntegrationExample> createState() =>
      _StaffRoomChatIntegrationExampleState();
}

class _StaffRoomChatIntegrationExampleState
    extends State<StaffRoomChatIntegrationExample> {
  // Add these services to your existing state
  final SmartMediaUploadService _uploadService = SmartMediaUploadService();
  final MediaCacheService _cacheService = MediaCacheService();
  final TextEditingController _messageController = TextEditingController();

  List<StaffRoomMessage> _messages = [];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  /// STEP 1: Load messages and check local cache
  Future<void> _loadMessages() async {
    try {
      // Load messages from Firestore (existing code)
      final snapshot = await FirebaseFirestore.instance
          .collection('institutes')
          .doc(widget.instituteId)
          .collection('staffRoomMessages')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final messages = snapshot.docs.map((doc) {
        return StaffRoomMessage.fromFirestore(doc.data(), doc.id);
      }).toList();

      // NEW: Check local cache for media messages
      await _initializeMediaMessages(messages);

      setState(() {
        _messages = messages;
      });
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
  }

  /// STEP 2: Initialize media messages with local cache check
  Future<void> _initializeMediaMessages(List<StaffRoomMessage> messages) async {
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];

      // Only process media messages
      if (message.mediaMetadata != null) {
        // Generate expected local path
        final mediaType = MediaTypeExtension.fromMimeType(
          message.mediaMetadata!.mimeType ?? 'image/jpeg',
        );

        final extension = _getExtensionFromMimeType(
          message.mediaMetadata!.mimeType ?? 'image/jpeg',
        );

        final expectedPath = await _cacheService.getLocalFilePath(
          messageId: message.id,
          mediaType: mediaType,
          extension: extension,
        );

        // Check if exists locally
        final exists = await _cacheService.checkIfMediaExists(expectedPath);

        if (exists) {
          // Update metadata with local path (in-memory only, not Firestore)
          message.mediaMetadata!.copyWith(localPath: expectedPath);
        }
      }
    }
  }

  String? _getExtensionFromMimeType(String mimeType) {
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return '.jpg';
    if (mimeType.contains('png')) return '.png';
    if (mimeType.contains('gif')) return '.gif';
    if (mimeType.contains('pdf')) return '.pdf';
    if (mimeType.contains('mp3')) return '.mp3';
    if (mimeType.contains('mp4')) return '.mp4';
    return null;
  }

  /// STEP 3: Build message list with UniversalMediaWidget
  Widget _buildMessageList() {
    return ListView.builder(
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  /// STEP 4: Build message bubble with media support
  Widget _buildMessageBubble(StaffRoomMessage message) {
    final isMe = message.senderId == _currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Sender name (if not me)
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Message content
          if (message.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message.text,
                style: TextStyle(color: isMe ? Colors.white : Colors.black87),
              ),
            ),

          // Media message
          if (message.mediaMetadata != null) _buildMediaMessage(message, isMe),
        ],
      ),
    );
  }

  /// STEP 5: Use UniversalMediaWidget for media messages
  Widget _buildMediaMessage(StaffRoomMessage message, bool isMe) {
    // Convert StaffRoomMessage to CachedMediaMessage
    final cachedMessage = CachedMediaMessage(
      messageId: message.id,
      senderId: message.senderId,
      senderRole: 'teacher', // Staff room is teachers only
      conversationId: widget.instituteId,
      fileName: message.mediaMetadata!.originalFileName ?? 'media',
      fileType: message.mediaMetadata!.mimeType ?? 'image/jpeg',
      fileSize: message.mediaMetadata!.fileSize ?? 0,
      cloudUrl: message.mediaMetadata!.publicUrl,
      thumbnailUrl: message.mediaMetadata!.thumbnail,
      // Don't set localPath from Firestore - it will be checked by widget
      localPath: null,
      isDownloaded: false, // Will be checked by widget
      mediaType: MediaTypeCategoryExtension.fromMimeType(
        message.mediaMetadata!.mimeType ?? 'image/jpeg',
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(message.createdAt),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: UniversalMediaWidget(
        message: cachedMessage,
        isMe: isMe,
        maxWidth: 250,
        onMediaUpdated: (updatedMessage) {
          // Optional: Update local state when media is downloaded
          // This ensures the UI stays in sync
        },
      ),
    );
  }

  /// STEP 6: Send media with local caching
  Future<void> _sendMedia(File file) async {
    try {
      // Generate message ID
      final messageId = FirebaseFirestore.instance
          .collection('institutes')
          .doc(widget.instituteId)
          .collection('staffRoomMessages')
          .doc()
          .id;

      // Show sending indicator
      setState(() {
        // Add placeholder message to UI
      });

      // Prepare media (saves locally FIRST, then uploads)
      final mediaMessage = await _uploadService.prepareMediaForSending(
        file: file,
        messageId: messageId,
        senderId: _currentUserId!,
        senderRole: 'teacher',
        conversationId: widget.instituteId,
        uploadUrl: 'YOUR_CLOUDFLARE_UPLOAD_URL_HERE', // Configure this
        onProgress: (progress) {
          // Update progress indicator
          debugPrint(
            'Upload progress: ${(progress * 100).toStringAsFixed(0)}%',
          );
        },
      );

      if (mediaMessage != null) {
        // Save to Firestore
        await FirebaseFirestore.instance
            .collection('institutes')
            .doc(widget.instituteId)
            .collection('staffRoomMessages')
            .doc(messageId)
            .set({
              'senderId': mediaMessage.senderId,
              'senderName': 'Current User Name', // Get from auth
              'text': '',
              'imageUrl': mediaMessage.cloudUrl,
              'mediaMetadata': {
                'messageId': mediaMessage.messageId,
                'r2Key': 'media/${mediaMessage.messageId}',
                'publicUrl': mediaMessage.cloudUrl,
                'thumbnail': '', // Generate thumbnail if needed
                'mimeType': mediaMessage.fileType,
                'fileSize': mediaMessage.fileSize,
                'originalFileName': mediaMessage.fileName,
                'serverStatus': 'available',
                'uploadedAt': FieldValue.serverTimestamp(),
                'expiresAt': Timestamp.fromDate(
                  DateTime.now().add(const Duration(days: 30)),
                ),
              },
              'createdAt': FieldValue.serverTimestamp(),
              'isDeleted': false,
            });

        // Reload messages
        await _loadMessages();

        // Show success
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Media sent successfully')),
          );
        }

        // Media is now immediately accessible from local storage!
        // No re-download needed when user taps on it
      } else {
        throw Exception('Failed to prepare media');
      }
    } catch (e) {
      debugPrint('Error sending media: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send media: $e')));
      }
    }
  }

  /// STEP 7: Pick and send image
  Future<void> _pickAndSendImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        await _sendMedia(file);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  /// STEP 8: Pick and send document
  Future<void> _pickAndSendDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await _sendMedia(file);
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Staff Room - ${widget.instituteName}'),
        actions: [
          // Cache stats button
          IconButton(
            icon: const Icon(Icons.storage),
            onPressed: _showCacheStats,
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(child: _buildMessageList()),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Image button
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _pickAndSendImage,
          ),

          // Document button
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _pickAndSendDocument,
          ),

          // Text input
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
              ),
            ),
          ),

          // Send button
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () {
              // Send text message
            },
          ),
        ],
      ),
    );
  }

  /// Show cache statistics dialog
  Future<void> _showCacheStats() async {
    final stats = await _cacheService.getCacheStatistics();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Media Cache Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Files: ${stats.totalFiles}'),
            Text('Total Size: ${stats.formattedTotalSize}'),
            const SizedBox(height: 16),
            const Text(
              'By Type:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...stats.stats.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text(
                  '${entry.key.name}: ${entry.value.fileCount} files (${entry.value.formattedSize})',
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmClearCache();
            },
            child: const Text(
              'Clear Cache',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will delete all cached media files from your device. '
          'You can re-download them later. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final results = await _cacheService.clearAllMediaCache();
      final totalCleared = results.values.fold(
        0,
        (total, fileCount) => total + fileCount,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared $totalCleared cached files')),
        );

        // Reload messages to reflect cache changes
        await _loadMessages();
      }
    }
  }
}
