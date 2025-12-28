import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../models/group_chat_message.dart';
import '../../services/group_messaging_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../widgets/media_preview_card.dart';

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

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
    // Setup last read stream for unread divider
    _setupLastReadStream();
    // Mark as read on entry
    _markAsRead();
    // Scroll to bottom on initial load only
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true);
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
        Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 30)),
        ),
      );
    }
  }

  Future<void> _markAsRead() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        await unread.markChatAsRead(widget.communityId);
      }
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  @override
  void dispose() {
    // Mark chat as read when leaving to prevent self-unread badges
    try {
      final unread = Provider.of<UnreadCountProvider>(context, listen: false);
      unread.markChatAsRead(widget.communityId);
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

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('community_messages')
          .child(widget.communityId)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(File(image.path));
      final imageUrl = await storageRef.getDownloadURL();

      await _sendMessage(imageUrl: imageUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Open Community',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
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
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF8800)),
                  );
                }

                final messages = snapshot.data!;

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.\nBe the first to say hello! 👋',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return StreamBuilder<Timestamp?>(
                  stream: _lastReadAtStream,
                  builder: (context, readSnapshot) {
                    final lastReadMs = readSnapshot.data?.toDate().millisecondsSinceEpoch ?? 0;
                    
                    // Pre-compute a single divider position: the first read message after unread ones
                    int? unreadDividerIndex;
                    bool hasUnread = false;
                    bool hasRead = false;
                    for (int i = 0; i < messages.length; i++) {
                      final isUnread = messages[i].timestamp > lastReadMs;
                      hasUnread = hasUnread || isUnread;
                      hasRead = hasRead || !isUnread;
                      if (i > 0) {
                        final prevUnread = messages[i - 1].timestamp > lastReadMs;
                        final currUnread = isUnread;
                        if (prevUnread && !currUnread && unreadDividerIndex == null) {
                          unreadDividerIndex = i;
                        }
                      }
                    }
                    // If both read and unread exist but no boundary found, place at last item
                    if (unreadDividerIndex == null && hasUnread && hasRead) {
                      unreadDividerIndex = messages.length - 1;
                    }
                    
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMe = message.senderId == currentUserId;
                        final currentDate =
                            DateTime.fromMillisecondsSinceEpoch(message.timestamp);
                        // Reverse ListView with messages sorted desc: compare with next item (index+1)
                        // because that is visually above. Oldest message must always show divider.
                        final isOldest = index == messages.length - 1;
                        final nextDate = isOldest
                          ? null
                          : DateTime.fromMillisecondsSinceEpoch(
                            messages[index + 1].timestamp,
                            );
                        final showDayDivider = isOldest ||
                          _formatDayLabel(currentDate) !=
                            _formatDayLabel(nextDate!);

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showUnreadDivider && unreadDividerIndex == index)
                              _buildUnreadDivider(),
                            if (showDayDivider) _buildDayDivider(currentDate),
                            _MessageBubble(message: message, isMe: isMe),
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
          _buildInputBar(),
          if (_showEmojiPicker)
            EmojiPicker(
              onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
              onBackspacePressed: _onBackspacePressed,
              config: Config(
                height: 250,
                checkPlatformCompatibility: false,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: const Color(0xFF222222),
                  columns: 7,
                  emojiSizeMax: 28,
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: const Color(0xFF222222),
                  iconColorSelected: const Color(0xFF00A884),
                  indicatorColor: const Color(0xFF00A884),
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: const Color(0xFF222222),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
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
                  color: const Color(0xFF1F2C34),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _showEmojiPicker
                            ? Icons.keyboard
                            : Icons.sentiment_satisfied_outlined,
                        color: const Color(0xFF8696A0),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: Color(0xFF8696A0)),
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
              icon: const Icon(
                Icons.attach_file,
                color: Color(0xFF8696A0),
                size: 26,
              ),
              padding: const EdgeInsets.all(8),
              onPressed: _pickAndSendImage,
            ),
            const SizedBox(width: 8),
            // Mic/Send Button
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF00A884),
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

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            // Avatar for others
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFF8800),
              child: Text(
                message.senderName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Message Content
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFFFF8800)
                        : const Color(0xFF2A2A2A),
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
                      if (message.imageUrl != null) ...[
                        _buildAttachment(context, message.imageUrl!),
                        if (message.message.isNotEmpty)
                          const SizedBox(height: 8),
                      ],
                      if (message.message.isNotEmpty)
                        Text(
                          message.message,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.white,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
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

  Widget _buildAttachment(BuildContext context, String url) {
    // Extract R2 key from URL for legacy messages
    final uri = Uri.tryParse(url);
    if (uri == null) return const SizedBox();

    final r2Key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;

    final fileName = _fileNameFromUrl(url);
    final mimeType = _guessMimeType(fileName);

    return MediaPreviewCard(
      r2Key: r2Key,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: 0, // Unknown for legacy
      isMe: isMe,
    );
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
