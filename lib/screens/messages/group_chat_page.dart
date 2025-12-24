import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../models/group_chat_message.dart';
import '../../models/media_metadata.dart';
import '../../services/group_messaging_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/modern_attachment_sheet.dart';

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
  String _uploadingMediaType =
      ''; // Track what type of media is uploading: 'image', 'pdf', 'audio'
  bool _showEmojiPicker = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  double _slideOffsetX = 0;
  bool _isCancelled = false;
  final Set<String> _selectedMessages = {};
  bool _isSelectionMode = false;

  // Extract R2 key from full URL
  // https://files.lenv1.tech/media/1234567/file.pdf → media/1234567/file.pdf
  String _extractR2Key(String url) {
    final uri = Uri.parse(url);
    // Remove leading slash if present
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    print('📝 Extracted R2 key from $url: $path');
    return path;
  }

  @override
  void initState() {
    super.initState();
    // Remove global setState - it causes image blinking
    // Only rebuild when focus/emoji picker changes
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
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
    _recordingTimer?.cancel();
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

      setState(() {
        _isUploading = true;
        _uploadingMediaType = 'image';
      });

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

      setState(() {
        _isUploading = false;
        _uploadingMediaType = '';
      });

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

      setState(() {
        _isUploading = true;
        _uploadingMediaType = 'pdf';
      });

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

      print('📦 PDF Upload complete:');
      print('   File size: ${mediaMessage.fileSize} bytes');
      print('   File type: ${mediaMessage.fileType}');
      print('   R2 URL: ${mediaMessage.r2Url}');
      print('   File name: ${mediaMessage.fileName}');

      // Create MediaMetadata with file size for proper display
      final r2Key = _extractR2Key(mediaMessage.r2Url);
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '', // No thumbnail for PDF
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
      );

      print('📝 Creating metadata:');
      print('   R2 Key: ${metadata.r2Key}');
      print('   File Size: ${metadata.fileSize} bytes');
      print('   MIME Type: ${metadata.mimeType}');

      // Send message with metadata (not just URL)
      await _sendMessage(mediaMetadata: metadata);

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

  Future<void> _pickAndSendAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      setState(() {
        _isUploading = true;
        _uploadingMediaType = 'audio';
      });

      final conversationId = '${widget.classId}_${widget.subjectId}';

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: conversationId,
        senderId: currentUserId,
        senderRole: 'student',
        mediaType: 'message',
        onProgress: (progress) {
          print('Upload progress: $progress%');
        },
      );

      setState(() => _isUploading = false);

      final r2Key = _extractR2Key(mediaMessage.r2Url);
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
      );

      await _sendMessage(mediaMetadata: metadata);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio sent successfully')),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send audio: $e')));
      }
    }
  }

  Future<void> _recordAndSendAudio() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Stop recording FIRST
      if (_isRecording) {
        try {
          await _audioRecorder.stop();
        } catch (e) {
          print('Error stopping recorder: $e');
        }

        _recordingTimer?.cancel();
      }

      // IMMEDIATELY update UI
      setState(() {
        _isRecording = false;
        _isUploading = true;
      });

      // Upload to Cloudflare R2 using MediaUploadService
      final conversationId = '${widget.classId}_${widget.subjectId}';

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: File(_recordingPath!),
        conversationId: conversationId,
        senderId: currentUserId,
        senderRole: 'student',
        mediaType: 'message',
        onProgress: (progress) {
          print('Upload progress: $progress%');
        },
      );

      final r2Key = _extractR2Key(mediaMessage.r2Url);
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
      );

      await _sendMessage(mediaMetadata: metadata);

      // Delete temp file
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting temp file: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio sent successfully'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
          _recordingPath = null;
          _recordingDuration.value = 0;
          _slideOffsetX = 0;
          _isCancelled = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteRecording() async {
    // Stop recording if active
    if (_isRecording) {
      await _audioRecorder.stop();
      _recordingTimer?.cancel();
    }

    // Delete the file
    if (_recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting recording: $e');
      }
    }

    // Clear state
    setState(() {
      _isRecording = false;
      _recordingPath = null;
      _recordingDuration.value = 0;
      _slideOffsetX = 0;
      _isCancelled = false;
    });
  }

  Widget _buildRecordingOverlay() {
    if (_recordingPath == null && !_isUploading) return const SizedBox();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: const Color(0xFF2A2A2A),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: SafeArea(
          top: false,
          child: _isUploading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF00A884),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _uploadingMediaType == 'image'
                          ? 'Sending image...'
                          : _uploadingMediaType == 'pdf'
                          ? 'Sending PDF...'
                          : _uploadingMediaType == 'audio'
                          ? 'Sending audio...'
                          : 'Uploading...',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                )
              : Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: _deleteRecording,
                    ),
                    Expanded(
                      child: Center(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _recordingDuration,
                          builder: (context, duration, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isRecording)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  _formatDuration(duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF00A884)),
                      onPressed: _recordAndSendAudio,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.currentUser?.uid;
    final theme = Theme.of(context);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                _isSelectionMode ? Icons.close : Icons.arrow_back_ios_new,
                color: theme.iconTheme.color,
                size: 20,
              ),
              onPressed: () {
                if (_isSelectionMode) {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedMessages.clear();
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            title: _isSelectionMode
                ? Text(
                    '${_selectedMessages.length} selected',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Row(
                    children: [
                      Text(widget.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.subjectName,
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.className != null && widget.section != null
                            ? '${widget.className} - Section ${widget.section}'
                            : widget.teacherName,
                        style: TextStyle(
                          color: theme.textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: _isSelectionMode
                ? [
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 24,
                      ),
                      onPressed:
                          _selectedMessages.isEmpty ? null : _showDeleteDialog,
                    ),
                  ]
                : null,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                color: theme.dividerColor.withOpacity(0.1),
              ),
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
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF8800),
                        ),
                      );
                    }

                    // Filter out messages deleted by current user
                    final messages = snapshot.data!
                        .where((m) =>
                            !(m.deletedFor?.contains(currentUserId) ?? false))
                        .toList();

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
                        final isSelected = _selectedMessages.contains(message.id);

                        return GestureDetector(
                          onLongPress: () {
                            setState(() {
                              _isSelectionMode = true;
                              _selectedMessages.add(message.id);
                            });
                          },
                          onTap: _isSelectionMode
                              ? () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedMessages.remove(message.id);
                                      if (_selectedMessages.isEmpty) {
                                        _isSelectionMode = false;
                                      }
                                    } else {
                                      _selectedMessages.add(message.id);
                                    }
                                  });
                                }
                              : null,
                          child: Row(
                            children: [
                              if (_isSelectionMode)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: isSelected
                                        ? const Color(0xFFFFA929)
                                        : Colors.grey,
                                    size: 24,
                                  ),
                                ),
                              Expanded(
                                child: _MessageBubble(
                                    message: message, isMe: isMe),
                              ),
                            ],
                          ),
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
                    height: 300,
                    checkPlatformCompatibility: false,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: const Color(0xFF1A1A1A),
                      columns: 7,
                      emojiSizeMax: 28,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: const Color(0xFF1A1A1A),
                      iconColorSelected: const Color(0xFF00A884),
                      indicatorColor: const Color(0xFF00A884),
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _buildRecordingOverlay(),
      ],
    );
  }

  Widget _buildInputBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inputBg = isDark ? theme.colorScheme.surface : Colors.white;
    final borderColor = theme.colorScheme.outline.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withOpacity(0.1), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Emoji toggle
              IconButton(
                icon: Icon(
                  _showEmojiPicker
                      ? Icons.keyboard
                      : Icons.sentiment_satisfied_outlined,
                  color: theme.iconTheme.color?.withOpacity(0.6),
                  size: 20,
                ),
                padding: const EdgeInsets.all(6),
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
              // Text input (embedded)
              Expanded(
                child: Theme(
                  data: theme.copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      cursorColor: theme.colorScheme.onSurface,
                      selectionColor: theme.colorScheme.onSurface.withOpacity(
                        0.2,
                      ),
                      selectionHandleColor: theme.colorScheme.onSurface,
                    ),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    cursorColor: theme.colorScheme.onSurface,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 16,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(
                        color: (theme.textTheme.bodySmall?.color ?? Colors.grey)
                            .withOpacity(0.8),
                      ),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    enabled: !_isRecording && !_isUploading,
                    onSubmitted: (_) {
                      _sendMessage();
                      Future.delayed(const Duration(milliseconds: 50), () {
                        _messageFocusNode.requestFocus();
                      });
                    },
                  ),
                ),
              ),
              // Attachment
              IconButton(
                icon: Icon(
                  Icons.attach_file,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  size: 22,
                ),
                padding: const EdgeInsets.all(6),
                onPressed: _isUploading ? null : _showMediaOptions,
              ),
              const SizedBox(width: 4),
              // Mic/Send Button - Use ValueListenableBuilder to avoid rebuilding entire screen
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, value, child) {
                  final hasText = value.text.trim().isNotEmpty;
                  return GestureDetector(
                    onTap: () async {
                      if (hasText && !_isUploading) {
                        _sendMessage();
                      } else if (!_isRecording &&
                          !hasText &&
                          !_isUploading) {
                    // Single tap to start recording
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
                    setState(() {
                      _isRecording = true;
                      _recordingPath = path;
                      _recordingDuration.value = 0;
                      _slideOffsetX = 0;
                      _isCancelled = false;
                    });
                    _recordingTimer = Timer.periodic(
                      const Duration(seconds: 1),
                      (_) {
                        _recordingDuration.value++;
                      },
                    );
                  }
                },
                onHorizontalDragUpdate: (details) {
                  if (!_isRecording) return;
                  setState(() {
                    _slideOffsetX += details.delta.dx;
                    _isCancelled = _slideOffsetX < -80;
                  });
                },
                onHorizontalDragEnd: (details) {
                  if (!_isRecording) return;
                  if (_isCancelled) {
                    _deleteRecording();
                  }
                  setState(() {
                    _slideOffsetX = 0;
                    _isCancelled = false;
                  });
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? theme.colorScheme.error
                        : const Color(0xFFF2800D),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF2800D).withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording
                        ? Icons.mic
                        : (hasText
                              ? Icons.send_rounded
                              : Icons.mic),
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaOptions() {
    showModernAttachmentSheet(
      context,
      onImageTap: _pickAndSendImage,
      onPdfTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudio,
    );
  }

  Future<void> _deleteMessages(bool deleteForEveryone) async {
    final messagesToDelete = _selectedMessages.toList();
    if (messagesToDelete.isEmpty) return;

    try {
      for (final messageId in messagesToDelete) {
        if (deleteForEveryone) {
          // Get message to check for media
          final docSnapshot = await FirebaseFirestore.instance
              .collection('classes')
              .doc(widget.classId)
              .collection('subjects')
              .doc(widget.subjectId)
              .collection('messages')
              .doc(messageId)
              .get();

          if (docSnapshot.exists) {
            final data = docSnapshot.data();
            // Delete media from Cloudflare if exists
            if (data?['mediaMetadata'] != null) {
              final r2Key = data!['mediaMetadata']['r2Key'] as String?;
              if (r2Key != null) {
                try {
                  final r2Service = CloudflareR2Service(
                    accountId: CloudflareConfig.accountId,
                    bucketName: CloudflareConfig.bucketName,
                    accessKeyId: CloudflareConfig.accessKeyId,
                    secretAccessKey: CloudflareConfig.secretAccessKey,
                    r2Domain: CloudflareConfig.r2Domain,
                  );
                  await r2Service.deleteFile(key: r2Key);
                  print('🗑️ Deleted media from Cloudflare: $r2Key');
                } catch (e) {
                  print('⚠️ Failed to delete media from Cloudflare: $e');
                }
              }
            }
          }

          // Delete message from Firestore for everyone
          await FirebaseFirestore.instance
              .collection('classes')
              .doc(widget.classId)
              .collection('subjects')
              .doc(widget.subjectId)
              .collection('messages')
              .doc(messageId)
              .delete();
        } else {
          // Delete for me only - mark as deleted for this user
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final currentUserId = authProvider.currentUser?.uid;
          if (currentUserId != null) {
            await FirebaseFirestore.instance
                .collection('classes')
                .doc(widget.classId)
                .collection('subjects')
                .doc(widget.subjectId)
                .collection('messages')
                .doc(messageId)
                .update({
              'deletedFor': FieldValue.arrayUnion([currentUserId]),
            });
          }
        }
      }

      setState(() {
        _selectedMessages.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              deleteForEveryone
                  ? 'Deleted for everyone'
                  : 'Deleted for you',
            ),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      print('❌ Error deleting messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Messages',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Choose delete option',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessages(false);
            },
            child: const Text(
              'Delete for me',
              style: TextStyle(color: Color(0xFFFFA929)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessages(true);
            },
            child: const Text(
              'Delete for everyone',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final myBubbleColor = const Color(0xFFFFE8D1);
    final otherBubbleColor = isDark
        ? theme.colorScheme.surface
        : theme.cardColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            // Avatar for others
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.primaryColor.withOpacity(0.2),
              child: Text(
                message.senderName[0].toUpperCase(),
                style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Material(
                  elevation: isDark ? 0 : 1,
                  color: isMe ? myBubbleColor : otherBubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isMe ? 12 : 6),
                    bottomRight: Radius.circular(isMe ? 6 : 12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
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
                              color: isMe
                                  ? const Color(0xFF1A1D21)
                                  : theme.colorScheme.onSurface,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    fontSize: 10,
                  ),
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
    // Use optimized MediaPreviewCard for ALL media types
    // This prevents auto-downloads and provides on-demand loading
    final fileSize = metadata.fileSize ?? 0;
    print(
      '📦 Building attachment: ${metadata.r2Key} with size: $fileSize bytes',
    );

    return MediaPreviewCard(
      r2Key: metadata.r2Key,
      fileName: _fileNameFromMetadata(metadata),
      mimeType: metadata.mimeType ?? 'application/octet-stream',
      fileSize: fileSize,
      thumbnailBase64: metadata.thumbnail,
      localPath: metadata.localPath, // Use already-saved path
      isMe: isMe,
    );
  }

  Widget _buildLegacyAttachment(BuildContext context, String url) {
    // Extract R2 key from URL for legacy messages
    // URL format: https://files.lenv1.tech/media/timestamp/filename.ext
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
