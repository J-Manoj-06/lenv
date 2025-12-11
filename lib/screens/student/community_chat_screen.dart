import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/community_model.dart';
import '../../models/community_message_model.dart';
import '../../providers/student_provider.dart';
import '../../services/community_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../widgets/chat_image_widget.dart';
import 'package:path_provider/path_provider.dart';

class CommunityChatScreen extends StatefulWidget {
  final CommunityModel community;

  const CommunityChatScreen({super.key, required this.community});

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final CommunityService _communityService = CommunityService();
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

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(force: true),
    );
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
    if (_scrollController.hasClients) {
      // Only auto-scroll if user is at bottom (within 100 pixels) or force is true
      if (force || _scrollController.offset < 100) {
        _scrollController.jumpTo(0);
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (!widget.community.allowImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Images are not allowed in this community'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image == null) return;

      final student = Provider.of<StudentProvider>(
        context,
        listen: false,
      ).currentStudent;
      if (student == null) return;

      setState(() => _isUploading = true);

      // WhatsApp-style upload: compression + thumbnails + temporary storage
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      final result = await _whatsappMediaUpload.uploadImage(
        imageFile: File(image.path),
        messageId: messageId,
        conversationId: widget.community.id,
        senderId: student.uid,
        onProgress: (progress) {
          print('Upload progress: ${(progress * 100).toInt()}%');
        },
      );

      setState(() => _isUploading = false);

      if (result.success && result.metadata != null) {
        // Send message with media metadata
        await _communityService.sendMessage(
          communityId: widget.community.id,
          senderId: student.uid,
          senderName: student.name,
          senderRole: 'Student',
          content: '', // Empty content for image-only messages
          imageUrl: '', // Keep empty, using mediaMetadata instead
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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;

      final student = Provider.of<StudentProvider>(
        context,
        listen: false,
      ).currentStudent;
      if (student == null) return;

      setState(() => _isUploading = true);

      // Upload to Cloudflare R2 using MediaUploadService
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.community.id,
        senderId: student.uid,
        senderRole: 'Student',
        mediaType: 'community', // Permanent storage for community messages
        onProgress: (progress) {
          print('Upload progress: $progress%');
        },
      );

      setState(() => _isUploading = false);

      // Send message with R2 URL
      await _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
        content: '', // Empty content for PDF-only messages
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

  Future<void> _recordAndSendAudio() async {
    try {
      if (_isRecording) {
        // Stop recording
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
        });

        if (path == null) return;

        final student = Provider.of<StudentProvider>(
          context,
          listen: false,
        ).currentStudent;
        if (student == null) return;

        setState(() => _isUploading = true);

        // Upload to Cloudflare R2 using MediaUploadService
        final mediaMessage = await _mediaUploadService.uploadMedia(
          file: File(path),
          conversationId: widget.community.id,
          senderId: student.uid,
          senderRole: 'Student',
          mediaType: 'community', // Permanent storage for community messages
          onProgress: (progress) {
            print('Upload progress: $progress%');
          },
        );

        setState(() => _isUploading = false);

        // Send message with R2 URL
        await _communityService.sendMessage(
          communityId: widget.community.id,
          senderId: student.uid,
          senderName: student.name,
          senderRole: 'Student',
          content: '', // Empty content for audio-only messages
          fileUrl: mediaMessage.r2Url,
          fileName: 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
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
                backgroundColor: Colors.red,
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
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final student = Provider.of<StudentProvider>(
      context,
      listen: false,
    ).currentStudent;
    if (student == null) return;

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

    // Clear input immediately for instant feedback
    _messageController.clear();

    // Keep keyboard open after clearing text
    _messageFocusNode.requestFocus();

    try {
      // Send without blocking UI
      _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
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
    final student = Provider.of<StudentProvider>(context).currentStudent;
    if (student == null) {
      return const Scaffold(body: Center(child: Text('No student data')));
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
                    child: CircularProgressIndicator(color: Color(0xFFFFA929)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
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
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.3),
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
                          'Be the first to say hello!',
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
                    final isCurrentUser = message.senderId == student.uid;
                    final showDateDivider =
                        index == messages.length - 1 ||
                        _formatDate(message.createdAt) !=
                            _formatDate(messages[index + 1].createdAt);

                    return Column(
                      children: [
                        if (message.type == 'announcement')
                          _buildAnnouncement(message)
                        else
                          _buildMessageBubble(
                            message,
                            isCurrentUser,
                            student.name,
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
                colors: [Color(0xFFFFA726), Color(0xFFFFB26B)],
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
            child: Text(
              widget.community.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
          onPressed: () {
            // TODO: Implement message search
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search coming soon!')),
            );
          },
        ),
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
      child: Center(
        child: Text(
          message.content,
          style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
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
              backgroundColor: const Color(0xFFFFA929),
              child: Text(
                message.senderName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
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
                    child: Text(
                      message.senderName,
                      style: const TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 12,
                      ),
                    ),
                  ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: isCurrentUser
                            ? const LinearGradient(
                                colors: [Color(0xFFFFA726), Color(0xFFFFB26B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isCurrentUser ? null : const Color(0xFF1F2228),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(isCurrentUser ? 12 : 4),
                          bottomRight: Radius.circular(isCurrentUser ? 4 : 12),
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
                              style: TextStyle(
                                color: isCurrentUser
                                    ? Colors.white
                                    : const Color(0xFFCCCCCC),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!isCurrentUser && message.senderRole == 'Teacher')
                      Positioned(
                        left: -6,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF64B5F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.school, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Teacher',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF757575),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      color: const Color(0xFF1A1C20),
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F25),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined),
              color: const Color(0xFF9E9E9E),
              onPressed: () {
                // TODO: Implement emoji picker
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Emoji picker coming soon!')),
                );
              },
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  _sendMessage();
                  // Keep keyboard open by requesting focus again
                  Future.delayed(const Duration(milliseconds: 50), () {
                    _messageFocusNode.requestFocus();
                  });
                },
              ),
            ),
            if (_isUploading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFA929),
                    ),
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  _isRecording ? Icons.stop : Icons.attach_file,
                  color: _isRecording ? Colors.red : const Color(0xFF9E9E9E),
                ),
                onPressed: _isRecording
                    ? _recordAndSendAudio
                    : _showMediaOptions,
              ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFA929),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.black),
                onPressed: _sendMessage,
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
                  enabled: widget.community.allowImages,
                ),
                _buildMediaOption(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  color: const Color(0xFFF44336),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendPDF();
                  },
                  enabled: true,
                ),
                _buildMediaOption(
                  icon: Icons.mic,
                  label: 'Audio',
                  color: const Color(0xFF2196F3),
                  onTap: () {
                    Navigator.pop(context);
                    _recordAndSendAudio();
                  },
                  enabled: true,
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
    required bool enabled,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: enabled ? color : Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
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
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
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
                      colors: [Color(0xFFFFA726), Color(0xFFFFB26B)],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.community.getCategoryIcon(),
                      style: const TextStyle(fontSize: 28),
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
                        style: const TextStyle(
                          color: Color(0xFF9E9E9E),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (widget.community.description.isNotEmpty) ...[
              const Text(
                'Description',
                style: TextStyle(
                  color: Color(0xFFFFA929),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.community.description,
                style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
              ),
              const SizedBox(height: 20),
            ],
            const Text(
              'Community Rules',
              style: TextStyle(
                color: Color(0xFFFFA929),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildRuleChip(
              'Links ${widget.community.allowLinks ? 'Allowed' : 'Not Allowed'}',
              widget.community.allowLinks,
            ),
            const SizedBox(height: 8),
            _buildRuleChip(
              'Images ${widget.community.allowImages ? 'Allowed' : 'Not Allowed'}',
              widget.community.allowImages,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleChip(String text, bool isAllowed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isAllowed
            ? const Color(0xFF1F2228)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAllowed
              ? const Color(0xFF2E3239)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAllowed ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: isAllowed ? const Color(0xFF4CAF50) : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isAllowed ? const Color(0xFFCCCCCC) : Colors.red.shade300,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
