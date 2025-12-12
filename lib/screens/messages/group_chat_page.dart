import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/group_chat_message.dart';
import '../../models/media_metadata.dart';
import '../../services/group_messaging_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/chat_image_widget.dart';
import '../../widgets/chat_attachment_tile.dart';

class GroupChatPage extends StatefulWidget {
  final String classId;
  final String subjectId;
  final String subjectName;
  final String teacherName;
  final String icon;
  final String? className;
  final String? section;

  const GroupChatPage({
    super.key,
    required this.classId,
    required this.subjectId,
    required this.subjectName,
    required this.teacherName,
    required this.icon,
    this.className,
    this.section,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final GroupMessagingService _messagingService = GroupMessagingService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final WhatsAppMediaUploadService _whatsappMediaUpload;

  late final MediaUploadService _mediaUploadService;
  bool _isUploading = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    // Initialize MediaUploadService with CloudflareConfig
    final r2Service = CloudflareR2Service(
      accountId: CloudflareConfig.accountId,
      bucketName: CloudflareConfig.bucketName,
      accessKeyId: CloudflareConfig.accessKeyId,
      secretAccessKey: CloudflareConfig.secretAccessKey,
      r2Domain: CloudflareConfig.r2Domain,
    );

    _mediaUploadService = MediaUploadService(
      r2Service: r2Service,
      firestore: FirebaseFirestore.instance,
      cacheService: LocalCacheService(),
    );

    // Initialize WhatsApp media upload service
    _whatsappMediaUpload = WhatsAppMediaUploadService(
      workerBaseUrl:
          'https://whatsapp-media-worker.giridharannj.workers.dev', // TODO: Update with actual worker URL
    );

    // Mark as read when entering chat
    _markAsRead();
    // Scroll to bottom on initial load
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(force: true),
    );
  }

  Future<void> _markAsRead() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        await _messagingService.markGroupAsRead(
          widget.classId,
          widget.subjectId,
          currentUser.uid,
        );
      }
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _audioRecorder.dispose();
    super.dispose();
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

  Future<void> _sendMessage({
    String? imageUrl,
    MediaMetadata? mediaMetadata,
  }) async {
    print('📤 _sendMessage called');
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null && mediaMetadata == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    print('🧹 Clearing text field');
    _messageController.clear();

    print('⌨️ Requesting focus to keep keyboard open');
    _messageFocusNode.requestFocus();

    try {
      final message = GroupChatMessage(
        id: '',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: text,
        imageUrl: imageUrl,
        mediaMetadata: mediaMetadata,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      print('📨 Sending message to Firestore');
      await _messagingService.sendGroupMessage(
        widget.classId,
        widget.subjectId,
        message,
      );
      print('✅ Message sent successfully');

      // Don't auto-scroll - let user stay where they are
    } catch (e) {
      print('❌ Error sending message: $e');
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
      );

      if (image == null) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      setState(() => _isUploading = true);

      // WhatsApp-style upload: compression + thumbnails + temporary storage
      final conversationId = '${widget.classId}_${widget.subjectId}';
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      final result = await _whatsappMediaUpload.uploadImage(
        imageFile: File(image.path),
        messageId: messageId,
        conversationId: conversationId,
        senderId: currentUserId,
        onProgress: (progress) {
          print('Upload progress: ${(progress * 100).toInt()}%');
        },
      );

      setState(() => _isUploading = false);

      if (result.success && result.metadata != null) {
        // Send message with media metadata (no imageUrl for WhatsApp-style)
        await _sendMessage(mediaMetadata: result.metadata);
      } else {
        throw Exception(result.error?.message ?? 'Upload failed');
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  Future<void> _pickAndSendPDF() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      setState(() => _isUploading = true);

      // Upload to Cloudflare R2 using MediaUploadService
      final conversationId = '${widget.classId}_${widget.subjectId}';

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: conversationId,
        senderId: currentUserId,
        senderRole: 'student',
        mediaType: 'message', // Permanent storage for group messages
        onProgress: (progress) {
          print('Upload progress: $progress%');
        },
      );

      setState(() => _isUploading = false);

      // Send message with R2 URL (using imageUrl field for simplicity)
      await _sendMessage(imageUrl: mediaMessage.r2Url);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF sent successfully')));
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send PDF: $e')));
      }
    }
  }

  Future<void> _recordAndSendAudio() async {
    try {
      if (_isRecording) {
        // Stop recording
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
        });

        if (path == null) return;

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUserId = authProvider.currentUser?.uid;

        if (currentUserId == null) {
          throw Exception('User not authenticated');
        }

        setState(() => _isUploading = true);

        // Upload to Cloudflare R2 using MediaUploadService
        final conversationId = '${widget.classId}_${widget.subjectId}';

        final mediaMessage = await _mediaUploadService.uploadMedia(
          file: File(path),
          conversationId: conversationId,
          senderId: currentUserId,
          senderRole: 'student',
          mediaType: 'message', // Permanent storage for group messages
          onProgress: (progress) {
            print('Upload progress: $progress%');
          },
        );

        setState(() => _isUploading = false);

        // Send message with R2 URL
        await _sendMessage(imageUrl: mediaMessage.r2Url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audio sent successfully')),
          );
        }
      } else {
        // Start recording - use record package's built-in permission check
        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Microphone permission denied. Please enable it in Settings.',
                ),
              ),
            );
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        setState(() => _isRecording = true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording... Tap again to stop'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to record audio: $e')));
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
                    widget.subjectName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.className != null && widget.section != null
                        ? '${widget.className} - Section ${widget.section}'
                        : widget.teacherName,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
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
              stream: _messagingService.getGroupMessages(
                widget.classId,
                widget.subjectId,
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

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == currentUserId;

                    return _MessageBubble(message: message, isMe: isMe);
                  },
                );
              },
            ),
          ),

          // Input Bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
        child: Row(
          children: [
            IconButton(
              icon: _isUploading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF8800),
                        ),
                      ),
                    )
                  : Icon(
                      _isRecording ? Icons.stop : Icons.attach_file,
                      color: _isRecording
                          ? Colors.red
                          : const Color(0xFFFF8800),
                    ),
              onPressed: _isUploading
                  ? null
                  : (_isRecording ? _recordAndSendAudio : _showMediaOptions),
            ),
            const SizedBox(width: 8),

            // Text Input
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageFocusNode,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  // Don't disable TextField - it causes keyboard to close!
                  // enabled: !_isSending,
                  onSubmitted: (_) {
                    print('⌨️ onSubmitted triggered - keyboard send pressed');
                    _sendMessage();
                    // Keep keyboard open by requesting focus again
                    Future.delayed(const Duration(milliseconds: 50), () {
                      print(
                        '⌨️ onSubmitted - requesting focus after 50ms delay',
                      );
                      _messageFocusNode.requestFocus();
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Send Button
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8800), Color(0xFFFF9E2A)],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: () => _sendMessage(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMediaOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1C20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Send Media',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMediaOption(
                  icon: Icons.image,
                  label: 'Image',
                  color: const Color(0xFF4CAF50),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendImage();
                  },
                ),
                _buildMediaOption(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  color: const Color(0xFFF44336),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendPDF();
                  },
                ),
                _buildMediaOption(
                  icon: Icons.mic,
                  label: 'Audio',
                  color: const Color(0xFF2196F3),
                  onTap: () {
                    Navigator.pop(context);
                    _recordAndSendAudio();
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

  Widget _buildMediaOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
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
                      // Media handling
                      if (message.mediaMetadata != null) ...[
                        _buildMetadataAttachment(
                          context,
                          message.mediaMetadata!,
                        ),
                        if (message.message.isNotEmpty)
                          const SizedBox(height: 8),
                      ]
                      // Legacy URL support (images/PDFs)
                      else if (message.imageUrl != null) ...[
                        _buildLegacyAttachment(context, message.imageUrl!),
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

  Widget _buildMetadataAttachment(
    BuildContext context,
    MediaMetadata metadata,
  ) {
    if (_isImageMime(metadata.mimeType)) {
      return ChatImageWidget(metadata: metadata, isMe: isMe);
    }

    return ChatAttachmentTile(
      fileName: _fileNameFromMetadata(metadata),
      url: metadata.publicUrl,
      mimeType: metadata.mimeType,
      isMe: isMe,
    );
  }

  Widget _buildLegacyAttachment(BuildContext context, String url) {
    if (_looksLikePdf(url)) {
      return ChatAttachmentTile(
        fileName: _fileNameFromUrl(url),
        url: url,
        mimeType: 'application/pdf',
        isMe: isMe,
      );
    }

    if (_looksLikeAudio(url)) {
      return ChatAttachmentTile(
        fileName: _fileNameFromUrl(url),
        url: url,
        mimeType: 'audio/mpeg',
        isMe: isMe,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url, width: 200, fit: BoxFit.cover),
    );
  }

  bool _isImageMime(String? mime) {
    return mime?.toLowerCase().startsWith('image/') ?? false;
  }

  bool _looksLikePdf(String url) {
    return url.toLowerCase().contains('.pdf');
  }

  bool _looksLikeAudio(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m4a') ||
        lower.contains('.mp3') ||
        lower.contains('.wav') ||
        lower.contains('.aac');
  }

  String _fileNameFromMetadata(MediaMetadata metadata) {
    final parts = metadata.r2Key.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.last;
    return _fileNameFromUrl(metadata.publicUrl);
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
