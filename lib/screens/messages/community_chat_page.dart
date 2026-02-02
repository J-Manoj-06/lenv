import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:convert';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/link_utils.dart';
import '../../models/group_chat_message.dart';
import '../../services/group_messaging_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../utils/chat_type_config.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/multi_image_message_bubble.dart';
import '../../models/media_metadata.dart';
import '../../services/background_upload_service.dart';

class CommunityChatPage extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String icon;

  const CommunityChatPage({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.icon,
  });

  @override
  State<CommunityChatPage> createState() => _CommunityChatPageState();
}

class _CommunityChatPageState extends State<CommunityChatPage> {
  final GroupMessagingService _messagingService = GroupMessagingService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Stream<Timestamp?> _lastReadAtStream;
  final bool _showUnreadDivider = true;

  // ===== Date helpers for day separators =====
  String _formatDayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM dd, yyyy').format(dt);
  }

  Widget _buildDayDivider(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _formatDayLabel(dt),
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: const [
          Expanded(child: Divider(color: Color(0x339E9E9E), thickness: 1)),
          SizedBox(width: 8),
          Text(
            'Unread messages',
            style: TextStyle(
              color: Color(0xFFFF8800),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 8),
          Expanded(child: Divider(color: Color(0x339E9E9E), thickness: 1)),
        ],
      ),
    );
  }

  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  bool _showEmojiPicker = false;

  // Optimistic pending uploads (parity with student group chat)
  final List<GroupChatMessage> _pendingMessages = [];
  final Set<String> _uploadingMessageIds = {};
  final Map<String, double> _pendingUploadProgress = {};
  final Map<String, String> _localSenderMediaPaths = {};
  DateTime? _lastMarkedMessageAt;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });

    // Track upload progress so pending bubbles show overlays
    BackgroundUploadService().onUploadProgress =
        (messageId, isUploading, progress) {
          if (!mounted) return;
          setState(() {
            if (isUploading) {
              _uploadingMessageIds.add(messageId);
              _pendingUploadProgress[messageId] = progress;
            } else {
              _uploadingMessageIds.remove(messageId);
              _pendingUploadProgress.remove(messageId);
            }
          });
        };

    // Setup last read stream for unread divider
    _setupLastReadStream();
    // Mark as read on entry and refresh unread counts
    _markAsRead();
    // Scroll to bottom on initial load only
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
      // Refresh unread counts after marking as read
      try {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        unread.refreshChat(widget.communityId);
      } catch (_) {}
    });
  }

  void _setupLastReadStream() {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      _lastReadAtStream = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chatReads')
          .doc(widget.communityId)
          .snapshots()
          .map((doc) {
            if (doc.exists && doc.data() != null && doc['lastReadAt'] != null) {
              return doc['lastReadAt'] as Timestamp?;
            }
            return Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 30)),
            );
          });
    } catch (e) {
      _lastReadAtStream = Stream.value(
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))),
      );
    }
  }

  Future<void> _markAsRead() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        debugPrint(
          '[CommunityChat] 🔔 Marking chat as read: ${widget.communityId}',
        );
        await unread.markChatAsRead(widget.communityId);
        // Force reload unread count for this chat after marking as read
        await unread.loadUnreadCount(
          chatId: widget.communityId,
          chatType: ChatTypeConfig.communityChat,
        );
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    // Mark chat as read when leaving to prevent self-unread badges
    try {
      final unread = Provider.of<UnreadCountProvider>(context, listen: false);
      unread.markChatAsRead(widget.communityId);
      _lastMarkedMessageAt = DateTime.now();
    } catch (_) {}

    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _onEmojiSelected(Emoji emoji) {
    _messageController.text += emoji.emoji;
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    if (text.isNotEmpty) {
      _messageController.text = text.substring(0, text.length - 1);
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Only auto-scroll if user is at bottom (within 100 pixels) or force is true
        if (force || _scrollController.offset < 100) {
          _scrollController.jumpTo(0);
        }
      }
    });
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    // Clear input immediately for instant feedback
    _messageController.clear();

    // Keep keyboard open after clearing text
    _messageFocusNode.requestFocus();

    try {
      final message = GroupChatMessage(
        id: '',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: text,
        imageUrl: imageUrl,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Send without blocking UI
      _messagingService.sendCommunityMessage(widget.communityId, message);
      // Don't auto-scroll - let user stay where they are
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  Future<void> _pickAndSendImages() async {
    try {
      print('🖼️ Starting image picker...');

      // Try pickMultiImage first
      List<XFile> images = [];
      try {
        images = await _imagePicker.pickMultiImage(
          limit: 5,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        print('📸 Picked ${images.length} images via pickMultiImage');
      } catch (e) {
        print('⚠️ pickMultiImage failed: $e, trying pickImage instead');
        // Fallback to single image picker if multi doesn't work
        final image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        if (image != null) {
          images = [image];
          print('📸 Fallback: Picked 1 image via pickImage');
        }
      }

      if (images.isEmpty) {
        print('⚠️ No images selected');
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        print('❌ User not authenticated');
        return;
      }

      final conversationId = widget.communityId;
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final groupMessageId =
          'upload_${baseTimestamp}_${currentUser.uid.hashCode}';
      final List<MediaMetadata> mediaList = [];
      final List<String> localPaths = [];

      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        final file = File(image.path);
        if (!file.existsSync()) {
          print('⚠️ File does not exist: ${image.path}');
          continue;
        }

        final messageId = '${groupMessageId}_$i';
        localPaths.add(file.path);

        mediaList.add(
          MediaMetadata(
            messageId: messageId,
            r2Key: 'pending/$messageId',
            publicUrl: '',
            thumbnail: file.path,
            localPath: file.path,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            uploadedAt: DateTime.now(),
            originalFileName: file.path.split('/').last,
            fileSize: await file.length(),
            mimeType: 'image/jpeg',
          ),
        );
      }

      if (mediaList.isEmpty) {
        print('❌ No valid images found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No valid images found')),
          );
        }
        return;
      }

      print('✅ Created pending message with ${mediaList.length} images');
      final pendingMessage = GroupChatMessage(
        id: 'pending:$groupMessageId',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: '',
        timestamp: baseTimestamp,
        mediaMetadata: mediaList.first,
        multipleMedia: mediaList.length > 1 ? mediaList : null,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        for (int i = 0; i < mediaList.length; i++) {
          final messageId = mediaList[i].messageId;
          _uploadingMessageIds.add(messageId);
          _pendingUploadProgress[messageId] = 0.0;
          _localSenderMediaPaths[messageId] = localPaths[i];
        }
        print(
          '📝 Updated state with ${_pendingMessages.length} pending messages',
        );
      });

      // Queue uploads in background
      for (int i = 0; i < images.length; i++) {
        final file = File(images[i].path);
        if (!file.existsSync()) continue;
        final messageId = '${groupMessageId}_$i';

        print('📤 Queueing upload for $messageId');
        await BackgroundUploadService().queueUpload(
          file: file,
          conversationId: conversationId,
          senderId: currentUser.uid,
          senderRole: 'student',
          mediaType: 'message',
          chatType: 'community',
          senderName: currentUser.name,
          messageId: messageId,
          groupId: groupMessageId,
        );
      }

      print('✅ All uploads queued, scrolling to bottom');
      _scrollToBottom(force: true);
    } catch (e) {
      print('❌ Error in _pickAndSendImages: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send images: $e')));
      }
    }
  }

  Future<void> _pickCamera() async {
    try {
      print('📷 Starting camera...');

      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) {
        print('⚠️ No image captured');
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        print('❌ User not authenticated');
        return;
      }

      final conversationId = widget.communityId;
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final groupMessageId =
          'upload_${baseTimestamp}_${currentUser.uid.hashCode}';
      final messageId = '${groupMessageId}_0';
      final file = File(image.path);

      if (!file.existsSync()) {
        print('⚠️ File does not exist: ${image.path}');
        return;
      }

      final mediaList = [
        MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '',
          thumbnail: file.path,
          localPath: file.path,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
          originalFileName: file.path.split('/').last,
          fileSize: await file.length(),
          mimeType: 'image/jpeg',
        ),
      ];

      print('✅ Created pending message with camera image');
      final pendingMessage = GroupChatMessage(
        id: 'pending:$groupMessageId',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: '',
        timestamp: baseTimestamp,
        mediaMetadata: mediaList.first,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.0;
        _localSenderMediaPaths[messageId] = file.path;
      });

      print('📤 Queueing camera upload for $messageId');
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: conversationId,
        senderId: currentUser.uid,
        senderRole: 'student',
        mediaType: 'message',
        chatType: 'community',
        senderName: currentUser.name,
        messageId: messageId,
        groupId: groupMessageId,
      );

      print('✅ Camera upload queued, scrolling to bottom');
      _scrollToBottom(force: true);
    } catch (e) {
      print('❌ Error in _pickCamera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send camera image: $e')),
        );
      }
    }
  }

  void _showAttachmentPicker() {
    final primaryColor = const Color(0xFF00A884); // Community chat green
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF222222)
        : const Color(0xFFFFFFFF);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
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
            const Text(
              'Send Attachment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.image,
                  label: 'Gallery',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendImages();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: primaryColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickCamera();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.currentUser?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final appBarColor = isDark ? const Color(0xFF141414) : Colors.white;
    final cardColor = isDark
        ? const Color(0xFF222222)
        : const Color(0xFFFFFFFF);
    final inputBgColor = isDark
        ? const Color(0xFF1F2C34)
        : const Color(0xFFF1F5F9);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final hintColor = isDark
        ? const Color(0xFF8696A0)
        : const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF00A884);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(widget.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.communityName,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Open Community',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: StreamBuilder<List<GroupChatMessage>>(
              stream: _messagingService.getCommunityMessages(
                widget.communityId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading messages',
                      style: TextStyle(color: subtitleColor),
                    ),
                  );
                }

                // Proceed even while connecting so pending messages render immediately
                final firestoreMessages =
                    snapshot.data ?? const <GroupChatMessage>[];

                if (firestoreMessages.isEmpty && _pendingMessages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.\nBe the first to say hello! 👋',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: hintColor),
                    ),
                  );
                }

                return StreamBuilder<Timestamp?>(
                  stream: _lastReadAtStream,
                  builder: (context, readSnapshot) {
                    final hasValidData = readSnapshot.data != null;
                    final lastReadMs =
                        readSnapshot.data?.toDate().millisecondsSinceEpoch ??
                        DateTime.now()
                            .subtract(const Duration(days: 30))
                            .millisecondsSinceEpoch;

                    // Merge pending + Firestore messages and de-duplicate when server versions arrive
                    final allMessages = <GroupChatMessage>[
                      ..._pendingMessages,
                      ...firestoreMessages,
                    ];
                    final uploadingMessageIds = <String>{
                      ..._uploadingMessageIds,
                    };
                    final pendingIdsToRemove = <String>[];

                    allMessages.removeWhere((pendingMsg) {
                      if (!pendingMsg.id.startsWith('pending:')) return false;

                      final pendingMediaIds = <String>{};
                      if (pendingMsg.multipleMedia != null) {
                        pendingMediaIds.addAll(
                          pendingMsg.multipleMedia!.map((m) => m.messageId),
                        );
                      }
                      if (pendingMsg.mediaMetadata != null) {
                        pendingMediaIds.add(
                          pendingMsg.mediaMetadata!.messageId,
                        );
                      }

                      final hasMatchingMedia =
                          pendingMediaIds.isNotEmpty &&
                          firestoreMessages.any((fsMsg) {
                            if (fsMsg.id.startsWith('pending:')) return false;
                            final fsMediaIds = <String>{};
                            if (fsMsg.multipleMedia != null) {
                              fsMediaIds.addAll(
                                fsMsg.multipleMedia!.map((m) => m.messageId),
                              );
                            }
                            if (fsMsg.mediaMetadata != null) {
                              fsMediaIds.add(fsMsg.mediaMetadata!.messageId);
                            }
                            if (fsMediaIds.isEmpty) return false;
                            return fsMediaIds.any(pendingMediaIds.contains);
                          });

                      final hasServerVersion =
                          hasMatchingMedia ||
                          firestoreMessages.any((fsMsg) {
                            final senderMatch =
                                fsMsg.senderId == pendingMsg.senderId;
                            final diff =
                                (fsMsg.timestamp - pendingMsg.timestamp).abs();
                            final timeMatch = diff < 30000;
                            final isNotPending = !fsMsg.id.startsWith(
                              'pending:',
                            );
                            return senderMatch && timeMatch && isNotPending;
                          });

                      if (hasServerVersion) {
                        if (pendingMsg.multipleMedia != null) {
                          for (final pm in pendingMsg.multipleMedia!) {
                            if (pm.localPath != null &&
                                pm.localPath!.isNotEmpty) {
                              _localSenderMediaPaths[pm.messageId] =
                                  pm.localPath!;
                            }
                            _uploadingMessageIds.remove(pm.messageId);
                            _pendingUploadProgress.remove(pm.messageId);
                          }
                        }
                        if (pendingMsg.mediaMetadata?.localPath != null) {
                          _localSenderMediaPaths[pendingMsg
                                  .mediaMetadata!
                                  .messageId] =
                              pendingMsg.mediaMetadata!.localPath!;
                        }
                        if (pendingMsg.mediaMetadata != null) {
                          _uploadingMessageIds.remove(
                            pendingMsg.mediaMetadata!.messageId,
                          );
                          _pendingUploadProgress.remove(
                            pendingMsg.mediaMetadata!.messageId,
                          );
                        }

                        pendingIdsToRemove.add(pendingMsg.id);
                        return true;
                      }

                      if (pendingMsg.multipleMedia != null &&
                          pendingMsg.multipleMedia!.isNotEmpty) {
                        final anyStillUploading = pendingMsg.multipleMedia!.any(
                          (m) => uploadingMessageIds.contains(m.messageId),
                        );
                        if (anyStillUploading) return false;
                      } else if (pendingMsg.mediaMetadata != null) {
                        if (uploadingMessageIds.contains(
                          pendingMsg.mediaMetadata!.messageId,
                        )) {
                          return false;
                        }
                      }

                      return false;
                    });

                    if (pendingIdsToRemove.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _pendingMessages.removeWhere(
                            (m) => pendingIdsToRemove.contains(m.id),
                          );
                        });
                      });
                    }

                    allMessages.sort(
                      (a, b) => b.timestamp.compareTo(a.timestamp),
                    );

                    // Auto-mark as read when newest message is seen and newer than our last mark
                    if (allMessages.isNotEmpty) {
                      final latest = DateTime.fromMillisecondsSinceEpoch(
                        allMessages.first.timestamp,
                      );
                      if (_lastMarkedMessageAt == null ||
                          latest.isAfter(_lastMarkedMessageAt!)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _markAsRead();
                          _lastMarkedMessageAt = latest;
                        });
                      }
                    }

                    int? unreadDividerIndex;
                    bool hasUnread = false;
                    bool hasRead = false;
                    for (int i = 0; i < allMessages.length; i++) {
                      final isUnread = allMessages[i].timestamp > lastReadMs;
                      hasUnread = hasUnread || isUnread;
                      hasRead = hasRead || !isUnread;
                      if (i > 0) {
                        final prevUnread =
                            allMessages[i - 1].timestamp > lastReadMs;
                        final currUnread = isUnread;
                        if (prevUnread &&
                            !currUnread &&
                            unreadDividerIndex == null) {
                          unreadDividerIndex = i;
                        }
                      }
                    }
                    if (unreadDividerIndex == null && hasUnread && hasRead) {
                      unreadDividerIndex = allMessages.length - 1;
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: allMessages.length,
                      itemBuilder: (context, index) {
                        final message = allMessages[index];
                        final isMe = message.senderId == currentUserId;
                        final currentDate = DateTime.fromMillisecondsSinceEpoch(
                          message.timestamp,
                        );
                        final isOldest = index == allMessages.length - 1;
                        final nextDate = isOldest
                            ? null
                            : DateTime.fromMillisecondsSinceEpoch(
                                allMessages[index + 1].timestamp,
                              );
                        final showDayDivider =
                            isOldest ||
                            _formatDayLabel(currentDate) !=
                                _formatDayLabel(nextDate!);

                        final isPending =
                            message.id.startsWith('pending:') ||
                            (message.mediaMetadata?.r2Key.startsWith(
                                  'pending/',
                                ) ??
                                false);
                        final uploadProgress = isPending
                            ? _pendingUploadProgress[message
                                  .mediaMetadata
                                  ?.messageId]
                            : null;

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showUnreadDivider &&
                                hasValidData &&
                                unreadDividerIndex == index)
                              _buildUnreadDivider(),
                            if (showDayDivider) _buildDayDivider(currentDate),
                            _MessageBubble(
                              message: message,
                              isMe: isMe,
                              uploading: isPending,
                              uploadProgress: uploadProgress,
                              localSenderMediaPaths: _localSenderMediaPaths,
                              uploadingMessageIds: _uploadingMessageIds,
                              pendingUploadProgress: _pendingUploadProgress,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Input Bar
          _buildInputBar(
            cardColor: cardColor,
            inputBgColor: inputBgColor,
            textColor: textColor,
            hintColor: hintColor,
            primaryColor: primaryColor,
            isDark: isDark,
          ),
          if (_showEmojiPicker)
            EmojiPicker(
              onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
              onBackspacePressed: _onBackspacePressed,
              config: Config(
                height: 250,
                checkPlatformCompatibility: false,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: cardColor,
                  columns: 7,
                  emojiSizeMax: 28,
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: cardColor,
                  iconColorSelected: primaryColor,
                  indicatorColor: primaryColor,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: cardColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar({
    required Color cardColor,
    required Color inputBgColor,
    required Color textColor,
    required Color hintColor,
    required Color primaryColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cardColor,
        border: isDark
            ? null
            : const Border(
                top: BorderSide(color: Color(0xFFE2E8F0), width: 0.5),
              ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -4),
                ),
              ]
            : null,
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Row(
          children: [
            // Text Input
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: inputBgColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _showEmojiPicker
                            ? Icons.keyboard
                            : Icons.sentiment_satisfied_outlined,
                        color: hintColor,
                        size: 26,
                      ),
                      padding: const EdgeInsets.all(8),
                      onPressed: () {
                        setState(() {
                          _showEmojiPicker = !_showEmojiPicker;
                        });
                        if (!_showEmojiPicker) {
                          _messageFocusNode.requestFocus();
                        } else {
                          _messageFocusNode.unfocus();
                        }
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        style: TextStyle(color: textColor, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: hintColor),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          _sendMessage();
                          Future.delayed(const Duration(milliseconds: 50), () {
                            _messageFocusNode.requestFocus();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.attach_file, color: hintColor, size: 26),
              padding: const EdgeInsets.all(8),
              onPressed: _showAttachmentPicker,
            ),
            const SizedBox(width: 8),
            // Mic/Send Button
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _messageController.text.trim().isNotEmpty
                      ? Icons.send_rounded
                      : Icons.mic,
                  color: Colors.white,
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                onPressed: _messageController.text.trim().isNotEmpty
                    ? () => _sendMessage()
                    : () {
                        // Handle mic recording
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final GroupChatMessage message;
  final bool isMe;
  final bool uploading;
  final double? uploadProgress;
  final Map<String, String> localSenderMediaPaths;
  final Set<String> uploadingMessageIds;
  final Map<String, double> pendingUploadProgress;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.uploading,
    required this.uploadProgress,
    required this.localSenderMediaPaths,
    required this.uploadingMessageIds,
    required this.pendingUploadProgress,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMe
        ? const Color(0xFFFF8800)
        : const Color(0xFF2A2A2A);
    final textColor = Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFF8800).withOpacity(0.16),
              child: Text(
                message.senderName[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFFF8800),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      style: const TextStyle(
                        color: Color(0xFFFF8800),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (message.multipleMedia != null &&
                    message.multipleMedia!.isNotEmpty) ...[
                  MultiImageMessageBubble(
                    imageUrls: message.multipleMedia!
                        .map((m) => m.localPath ?? m.publicUrl)
                        .toList(),
                    isMe: isMe,
                    uploadProgress: message.multipleMedia!
                        .map((m) => pendingUploadProgress[m.messageId])
                        .toList(),
                    onImageTap: (index) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ImageGalleryViewer(
                            mediaList: message.multipleMedia!,
                            initialIndex: index,
                            localSenderMediaPaths: localSenderMediaPaths,
                            isMe: isMe,
                          ),
                        ),
                      );
                    },
                  ),
                  if (message.message.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                      ),
                      child: _buildLinkifiedText(textColor),
                    ),
                  ],
                ] else ...[
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          (message.mediaMetadata != null ||
                                  message.imageUrl != null) &&
                              message.message.isEmpty
                          ? 6
                          : 16,
                      vertical:
                          (message.mediaMetadata != null ||
                                  message.imageUrl != null) &&
                              message.message.isEmpty
                          ? 6
                          : 10,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.mediaMetadata != null) ...[
                          _buildMetadataAttachment(
                            context,
                            message.mediaMetadata!,
                          ),
                          if (message.message.isNotEmpty)
                            const SizedBox(height: 8),
                        ] else if (message.imageUrl != null) ...[
                          _buildLegacyAttachment(context, message.imageUrl!),
                          if (message.message.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        if (message.message.isNotEmpty)
                          _buildLinkifiedText(textColor),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkifiedText(Color textColor) {
    return Linkify(
      onOpen: (link) async {
        final uri = Uri.parse(link.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      text: LinkUtils.addProtocolToBareUrls(message.message),
      options: const LinkifyOptions(defaultToHttps: true),
      style: TextStyle(color: textColor, fontSize: 14),
      linkStyle: const TextStyle(
        color: Color(0xFF90CAF9),
        fontSize: 14,
        decoration: TextDecoration.underline,
      ),
    );
  }

  Widget _buildMetadataAttachment(
    BuildContext context,
    MediaMetadata metadata,
  ) {
    final fileSize = metadata.fileSize ?? 0;
    final isUploading = uploadingMessageIds.contains(metadata.messageId);
    final uploadProgressVal = pendingUploadProgress[metadata.messageId];

    return MediaPreviewCard(
      r2Key: metadata.r2Key,
      fileName: _fileNameFromMetadata(metadata),
      mimeType: metadata.mimeType ?? 'application/octet-stream',
      fileSize: fileSize,
      thumbnailBase64: metadata.thumbnail,
      localPath:
          metadata.localPath ?? localSenderMediaPaths[metadata.messageId],
      isMe: isMe,
      uploading: isUploading,
      uploadProgress: uploadProgressVal,
    );
  }

  Widget _buildLegacyAttachment(BuildContext context, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return const SizedBox();
    final r2Key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final fileName = _fileNameFromUrl(url);
    final mimeType = _guessMimeType(fileName);

    return MediaPreviewCard(
      r2Key: r2Key,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: 0,
      isMe: isMe,
      uploading: uploading,
      uploadProgress: uploadProgress,
    );
  }

  String _fileNameFromMetadata(MediaMetadata metadata) {
    return metadata.originalFileName ?? metadata.r2Key.split('/').last;
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return 'file';
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}

class _ImageGalleryViewer extends StatefulWidget {
  final List<MediaMetadata> mediaList;
  final int initialIndex;
  final Map<String, String> localSenderMediaPaths;
  final bool isMe;

  const _ImageGalleryViewer({
    required this.mediaList,
    required this.initialIndex,
    required this.localSenderMediaPaths,
    required this.isMe,
  });

  @override
  State<_ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<_ImageGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1} / ${widget.mediaList.length}',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.mediaList.length,
        itemBuilder: (context, index) {
          final metadata = widget.mediaList[index];
          final localPath =
              metadata.localPath ??
              widget.localSenderMediaPaths[metadata.messageId];

          return _buildImageViewer(metadata, localPath);
        },
      ),
    );
  }

  Widget _buildImageViewer(MediaMetadata metadata, String? localPath) {
    Widget imageWidget;
    final file = (localPath != null && localPath.isNotEmpty)
        ? File(localPath)
        : null;
    final hasLocalFile = file != null && file.existsSync();
    final hasNetwork = metadata.publicUrl.isNotEmpty;

    if (hasLocalFile) {
      imageWidget = Image.file(
        file,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
      );
    } else if (hasNetwork) {
      imageWidget = Image.network(
        metadata.publicUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
      );
    } else if (metadata.thumbnail.isNotEmpty) {
      if (metadata.thumbnail.startsWith('/')) {
        imageWidget = Image.file(
          File(metadata.thumbnail),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
        );
      } else {
        try {
          final bytes = base64Decode(metadata.thumbnail);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
          );
        } catch (e) {
          imageWidget = _buildFallbackImage(metadata);
        }
      }
    } else {
      imageWidget = _buildFallbackImage(metadata);
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(child: imageWidget),
    );
  }

  Widget _buildFallbackImage(MediaMetadata metadata) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Image not available locally',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            metadata.originalFileName ?? 'image.jpg',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
