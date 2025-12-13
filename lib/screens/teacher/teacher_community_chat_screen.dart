import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../models/community_model.dart';
import '../../models/community_message_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/community_service.dart';
import '../common/announcement_pageview_screen.dart';
import '../../services/media_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../widgets/chat_image_widget.dart';
import 'package:path_provider/path_provider.dart';
import '../../widgets/modern_attachment_sheet.dart';

class TeacherCommunityChatScreen extends StatefulWidget {
  final CommunityModel community;

  const TeacherCommunityChatScreen({super.key, required this.community});

  @override
  State<TeacherCommunityChatScreen> createState() =>
      _TeacherCommunityChatScreenState();
}

class _TeacherCommunityChatScreenState
    extends State<TeacherCommunityChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final CommunityService _communityService = CommunityService();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  late final WhatsAppMediaUploadService _whatsappMediaUpload;
  String? _teacherName;
  String? _teacherId;
  bool _showEmojiPicker = false;
  bool _isUploading = false;
  bool _isRecording = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  late Timer _recordingTimer;
  double _slideOffsetX = 0;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
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

    _whatsappMediaUpload = WhatsAppMediaUploadService(
      workerBaseUrl: 'https://whatsapp-media-worker.giridharannj.workers.dev',
    );

    _loadTeacherData();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(force: true),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioRecorder.dispose();
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

  Future<void> _loadTeacherData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser != null) {
      // Get teacher data from Firestore
      final teacherDoc = await FirebaseFirestore.instance
          .collection('teachers')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();

      if (teacherDoc.docs.isNotEmpty) {
        setState(() {
          _teacherId = currentUser.uid;
          _teacherName = teacherDoc.docs.first.data()['name'] ?? 'Teacher';
        });
      }
    }
  }

  void _scrollToBottom({bool force = false}) {
    if (_scrollController.hasClients) {
      // Only auto-scroll if user is at bottom (within 100 pixels) or force is true
      if (force || _scrollController.offset < 100) {
        _scrollController.jumpTo(0);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _teacherId == null || _teacherName == null) return;

    // Check for links if not allowed
    if (!widget.community.allowLinks && _containsUrl(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Links are not allowed in this community'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _messageController.clear();

    try {
      await _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
        content: text,
      );

      // Don't auto-scroll - let user stay where they are
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _containsUrl(String text) {
    final urlPattern = RegExp(
      r'(https?:\/\/)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text);
  }

  void _showMediaOptions() {
    showModernAttachmentSheet(
      context,
      onImageTap: _pickAndSendImage,
      onPdfTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudio,
      imageEnabled: widget.community.allowImages,
    );
  }

  Future<void> _pickAndSendImage() async {
    if (_teacherId == null || _teacherName == null) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);

      setState(() => _isUploading = true);

      // WhatsApp-style upload: compression + thumbnails + temporary storage
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      final result = await _whatsappMediaUpload.uploadImage(
        imageFile: file,
        messageId: messageId,
        conversationId: widget.community.id,
        senderId: _teacherId!,
        onProgress: (progress) {
          debugPrint('Upload progress: ${(progress * 100).toInt()}%');
        },
      );

      setState(() => _isUploading = false);

      if (result.success && result.metadata != null) {
        await _communityService.sendMessage(
          communityId: widget.community.id,
          senderId: _teacherId!,
          senderName: _teacherName!,
          senderRole: 'Teacher',
          content: '',
          imageUrl: '',
          mediaType: 'image',
          mediaMetadata: result.metadata,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image sent successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(result.error?.message ?? 'Upload failed');
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendPDF() async {
    if (_teacherId == null || _teacherName == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;

      setState(() => _isUploading = true);

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.community.id,
        senderId: _teacherId!,
        senderRole: 'Teacher',
        mediaType: 'community',
        onProgress: (progress) {
          debugPrint('Upload progress: $progress%');
        },
      );

      setState(() => _isUploading = false);

      await _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
        content: '',
        fileUrl: mediaMessage.r2Url,
        fileName: fileName,
        mediaType: 'pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendAudio() async {
    if (_teacherId == null || _teacherName == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;

      setState(() => _isUploading = true);

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.community.id,
        senderId: _teacherId!,
        senderRole: 'Teacher',
        mediaType: 'community',
        onProgress: (progress) {
          debugPrint('Upload progress: $progress%');
        },
      );

      setState(() => _isUploading = false);

      await _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
        content: '',
        fileUrl: mediaMessage.r2Url,
        fileName: fileName,
        mediaType: 'audio',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM dd, yyyy').format(dateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_teacherId == null || _teacherName == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF101214),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6A4FF7)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF101214),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<CommunityMessageModel>>(
              stream: _communityService.getMessagesStream(widget.community.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6A4FF7)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading messages',
                      style: TextStyle(color: Colors.red[300]),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Be the first to start a conversation!',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 14,
                          ),
                        ),
                      ],
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
                    final isCurrentUser = message.senderId == _teacherId;
                    final showDateDivider =
                        index == messages.length - 1 ||
                        _formatDate(message.createdAt) !=
                            _formatDate(messages[index + 1].createdAt);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.type == 'announcement')
                          _buildAnnouncement(message)
                        else
                          _buildMessageBubble(
                            message,
                            isCurrentUser,
                            _teacherName!,
                          ),
                        if (showDateDivider)
                          _buildDateDivider(message.createdAt),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
          if (_showEmojiPicker)
            EmojiPicker(
              onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
              onBackspacePressed: _onBackspacePressed,
              config: Config(
                height: 250,
                checkPlatformCompatibility: false,
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: const Color(0xFF0B141A),
                  columns: 7,
                  emojiSizeMax: 28,
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: const Color(0xFF0B141A),
                  iconColorSelected: const Color(0xFF6A4FF7),
                  indicatorColor: const Color(0xFF6A4FF7),
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: const Color(0xFF0B141A),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1C20),
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6A4FF7), Color(0xFF8B6FFF)],
              ),
            ),
            child: Center(
              child: Text(
                widget.community.getCategoryIcon(),
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.community.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.community.memberCount} members',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: () => _showCommunityInfo(),
        ),
      ],
    );
  }

  Widget _buildDateDivider(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF262A30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _formatDate(date),
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncement(CommunityMessageModel message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: InkWell(
        onTap: () {
          final role = message.senderRole.toLowerCase();
          final postedByLabel =
              'Posted by ${message.senderRole[0].toUpperCase()}${message.senderRole.substring(1)}';
          openAnnouncementPageView(
            context,
            announcements: [
              {
                'role': role,
                'title': message.content.isNotEmpty
                    ? message.content
                    : 'Announcement',
                'subtitle': '',
                'postedByLabel': postedByLabel,
                'avatarUrl': message.senderAvatar.isNotEmpty
                    ? message.senderAvatar
                    : null,
                'postedAt': message.createdAt,
                'expiresAt': message.createdAt.add(const Duration(hours: 24)),
              },
            ],
            initialIndex: 0,
          );
        },
        child: Center(
          child: Text(
            message.content,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    CommunityMessageModel message,
    bool isCurrentUser,
    String currentUserName,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isCurrentUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCurrentUser) ...[
            CircleAvatar(
              radius: 16,
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isCurrentUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.senderName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF6A4FF7,
                            ).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            message.senderRole,
                            style: const TextStyle(
                              color: Color(0xFF6A4FF7),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: isCurrentUser
                        ? const LinearGradient(
                            colors: [Color(0xFF6A4FF7), Color(0xFF8B6FFF)],
                          )
                        : null,
                    color: isCurrentUser ? null : const Color(0xFF1E2228),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isCurrentUser ? 16 : 4),
                      bottomRight: Radius.circular(isCurrentUser ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // WhatsApp-style media with metadata
                      if (message.mediaMetadata != null) ...[
                        ChatImageWidget(metadata: message.mediaMetadata!),
                        if (message.content.isNotEmpty)
                          const SizedBox(height: 8),
                      ],
                      // Text content
                      if (message.content.isNotEmpty)
                        Text(
                          message.content,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(message.createdAt),
                        style: TextStyle(
                          color: isCurrentUser
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF6A4FF7),
              child: Text(
                currentUserName.isNotEmpty
                    ? currentUserName[0].toUpperCase()
                    : 'T',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final hasText = _messageController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: const BoxDecoration(
        color: Color(0xFF0B141A),
        border: Border(top: BorderSide(color: Color(0xFF131C21))),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
                          _focusNode.requestFocus();
                        } else {
                          _focusNode.unfocus();
                        }
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: Color(0xFF8696A0)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.attach_file,
                color: Color(0xFF8696A0),
                size: 26,
              ),
              padding: const EdgeInsets.all(8),
              onPressed: _isUploading ? null : _showMediaOptions,
            ),
            const SizedBox(width: 8),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF00A884),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  hasText ? Icons.send_rounded : Icons.mic,
                  color: Colors.white,
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                onPressed: hasText ? _sendMessage : () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommunityInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1C20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6A4FF7), Color(0xFF8B6FFF)],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          widget.community.getCategoryIcon(),
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.community.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.community.memberCount} members',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  widget.community.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      widget.community.category.toUpperCase(),
                      const Color(0xFF6A4FF7),
                    ),
                    _buildInfoChip(
                      widget.community.scope == 'global' ? 'Global' : 'School',
                      const Color(0xFF4CAF50),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Community Rules',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.community.rules,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
