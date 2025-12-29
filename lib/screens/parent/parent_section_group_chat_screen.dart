import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../config/cloudflare_config.dart';
import '../../models/community_message_model.dart';
import '../../models/media_metadata.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/parent_teacher_group_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../common/announcement_view_screen.dart';

class ParentSectionGroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? className;
  final String? section;
  final String childName;
  final String childId;
  final String? schoolCode;
  final String senderRole;

  const ParentSectionGroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.childName,
    required this.childId,
    this.className,
    this.section,
    this.schoolCode,
    this.senderRole = 'parent',
  });

  @override
  State<ParentSectionGroupChatScreen> createState() =>
      _ParentSectionGroupChatScreenState();
}

class _ParentSectionGroupChatScreenState
    extends State<ParentSectionGroupChatScreen> {
  static const Color parentGreen = Color(0xFF14A670);
  static const Color teacherViolet = Color(0xFF6366F1);
  static const Color backgroundDark = Color(0xFF101214);
  static const Color bubbleDark = Color(0xFF1A1C20);

  final ParentTeacherGroupService _service = ParentTeacherGroupService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  late final WhatsAppMediaUploadService _whatsappMediaUpload;
  bool _isUploading = false;
  bool _isRecording = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  final List<CommunityMessageModel> _pendingMessages = [];
  final Map<String, ValueNotifier<double>> _pendingUploadNotifiers = {};
  final Map<String, String> _localSenderMediaPaths = {};
  // Throttle progress updates to avoid rebuilding the entire list too frequently
  final Map<String, int> _lastUploadPercent = {};

  @override
  void dispose() {
    for (final notifier in _pendingUploadNotifiers.values) {
      notifier.dispose();
    }
    _controller.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

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
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  String _getFileName(CommunityMessageModel msg) {
    final meta = msg.mediaMetadata;
    if (meta?.originalFileName != null && meta!.originalFileName!.isNotEmpty) {
      return meta.originalFileName!;
    }
    if (meta != null && meta.r2Key.isNotEmpty) {
      final parts = meta.r2Key.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.last;
    }
    if (meta != null && meta.publicUrl.isNotEmpty) {
      final uri = Uri.tryParse(meta.publicUrl);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    }
    return 'file';
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    final senderId = user?.uid ?? '';
    final senderName = user?.name ?? 'Parent';

    // Clear immediately like WhatsApp (no loading state)
    _controller.clear();

    try {
      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: senderId,
        senderName: senderName,
        senderRole: widget.senderRole,
        content: text,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
        '';
    final primaryColor = widget.senderRole == 'teacher'
        ? teacherViolet
        : parentGreen;

    return Scaffold(
      backgroundColor: isDark ? backgroundDark : const Color(0xFFF6F7F8),
      appBar: AppBar(
        backgroundColor: isDark ? bubbleDark : Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupName,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.className ?? ''}${widget.section != null ? ' - ${widget.section}' : ''} · ${widget.childName}',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<CommunityMessageModel>>(
              stream: _service.getMessagesStream(widget.groupId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading messages',
                      style: TextStyle(
                        color: isDark ? Colors.red[200] : Colors.red[600],
                      ),
                    ),
                  );
                }

                final firestoreMessages = snapshot.data ?? [];
                final allMessages = [..._pendingMessages, ...firestoreMessages];
                if (allMessages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 64,
                          color: isDark
                              ? Colors.white.withOpacity(0.2)
                              : Colors.grey[500],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withOpacity(0.7)
                                : Colors.grey[700],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Say hello to the teachers and parents of this section',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withOpacity(0.6)
                                : Colors.grey[600],
                            fontSize: 13,
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
                  itemCount: allMessages.length,
                  itemBuilder: (context, index) {
                    final msg = allMessages[index];
                    final isCurrentUser = msg.senderId == currentUserId;
                    final hasMedia = msg.mediaMetadata != null;
                    final bubbleColor = hasMedia
                        ? Colors.transparent
                        : (isCurrentUser
                              ? primaryColor
                              : (isDark ? bubbleDark : Colors.grey[200]));
                    final textColor = isCurrentUser
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87);
                    final isPending = msg.messageId.startsWith('pending:');
                    final progressNotifier = isPending
                      ? _pendingUploadNotifiers[msg.messageId]
                      : null;
                    final localPath = _localSenderMediaPaths[msg.messageId];

                    if (msg.type == 'announcement') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: InkWell(
                            onTap: () {
                              final role = (msg.senderRole).toLowerCase();
                              final postedByLabel =
                                  'Posted by ${msg.senderRole}';
                              openAnnouncementView(
                                context,
                                role: role,
                                title: msg.content.isNotEmpty
                                    ? msg.content
                                    : 'Announcement',
                                subtitle: '',
                                postedByLabel: postedByLabel,
                                avatarUrl: null,
                                postedAt: msg.createdAt,
                                expiresAt: msg.createdAt.add(
                                  const Duration(hours: 24),
                                ),
                              );
                            },
                            child: Text(
                              msg.content,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return Padding(
                      key: ValueKey(msg.messageId),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: isCurrentUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                border: hasMedia
                                    ? Border.all(
                                        color: primaryColor,
                                        width: 1.5,
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(12)
                                    .copyWith(
                                      bottomRight: isCurrentUser
                                          ? const Radius.circular(4)
                                          : null,
                                      bottomLeft: !isCurrentUser
                                          ? const Radius.circular(4)
                                          : null,
                                    ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: hasMedia ? 4 : 12,
                                  vertical: hasMedia ? 4 : 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: isCurrentUser
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isCurrentUser)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 3,
                                        ),
                                        child: Text(
                                          msg.senderName,
                                          style: TextStyle(
                                            color: isDark
                                                ? primaryColor
                                                : primaryColor.withOpacity(0.8),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    if (msg.mediaMetadata != null) ...[
                                        RepaintBoundary(
                                        child: progressNotifier != null
                                          ? ValueListenableBuilder<double>(
                                            valueListenable:
                                              progressNotifier,
                                            builder: (_, value, __) {
                                              final progress =
                                                ((value / 100)
                                                    .clamp(0.0, 1.0))
                                                  .toDouble();
                                              return MediaPreviewCard(
                                              r2Key: msg
                                                .mediaMetadata!.r2Key,
                                              fileName: _getFileName(msg),
                                              mimeType:
                                                msg.mediaMetadata!
                                                    .mimeType ??
                                                  'application/octet-stream',
                                              fileSize: msg.mediaMetadata!
                                                  .fileSize ??
                                                0,
                                              thumbnailBase64:
                                                msg.mediaMetadata!
                                                  .thumbnail,
                                              localPath: localPath,
                                              isMe: isCurrentUser,
                                              uploading: true,
                                              uploadProgress: progress,
                                              );
                                            },
                                            )
                                          : MediaPreviewCard(
                                            r2Key: msg.mediaMetadata!.r2Key,
                                            fileName: _getFileName(msg),
                                            mimeType: msg.mediaMetadata!
                                                .mimeType ??
                                              'application/octet-stream',
                                            fileSize: msg.mediaMetadata!
                                                .fileSize ??
                                              0,
                                            thumbnailBase64:
                                              msg.mediaMetadata!.thumbnail,
                                            localPath: localPath,
                                            isMe: isCurrentUser,
                                            uploading: isPending,
                                            uploadProgress: null,
                                            ),
                                        ),
                                      if (msg.content.isNotEmpty)
                                        const SizedBox(height: 8),
                                    ],
                                    if (msg.content.isNotEmpty)
                                      Text(
                                        msg.content,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 15,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Padding(
                            padding: EdgeInsets.only(
                              left: isCurrentUser ? 0 : 8,
                              right: isCurrentUser ? 8 : 0,
                            ),
                            child: Text(
                              _formatTime(msg.createdAt),
                              style: TextStyle(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.5),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(isDark),
        ],
      ),
    );
  }

  Widget _buildMessageInput(bool isDark) {
    final primaryColor = widget.senderRole == 'teacher'
        ? teacherViolet
        : parentGreen;
    final hasText = _controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: isDark ? bubbleDark : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, color: Colors.grey),
              onPressed: _isUploading ? null : _showAttachmentSheet,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black : const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.2),
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Message the section group…',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: hasText
                  ? _sendMessage
                  : (_isRecording ? _stopAndSendRecording : _startRecording),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasText
                      ? primaryColor
                      : (_isRecording
                            ? Colors.red
                            : primaryColor.withOpacity(0.85)),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  hasText
                      ? Icons.send_rounded
                      : (_isRecording ? Icons.stop : Icons.mic),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    showModernAttachmentSheet(
      context,
      onImageTap: _pickAndSendImage,
      onPdfTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudioFile,
    );
  }

  Future<void> _pickAndSendImage() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final file = File(picked.path);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';

      // Create optimistic pending message
      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/${file.path.split('/').last}',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await file.length(),
        mimeType: 'image/jpeg',
        originalFileName: file.path.split('/').last,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name ?? 'User',
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'image',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: file.path.split('/').last,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0);
        _localSenderMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // Scroll to bottom to show new message
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });

      // Upload in background
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          if (!mounted) return;

          // Convert to integer percent and throttle updates to reduce list rebuilds
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;

          // Always allow first update and 100%; otherwise update on >= 5% change
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;

          _lastUploadPercent[pendingId] = percent;
          _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();
        },
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name ?? 'User',
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'image',
        mediaMetadata: metadata,
      );

      // Remove pending message after successful upload
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _localSenderMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  Future<void> _pickAndSendPDF() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/$fileName',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: fileSize,
        mimeType: 'application/pdf',
        originalFileName: fileName,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name ?? 'User',
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'pdf',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0);
        _lastUploadPercent[pendingId] = -1;
      });

      // Upload in background with optimistic UI
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          if (!mounted) return;
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;
          _lastUploadPercent[pendingId] = percent;
          _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();
        },
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name ?? 'User',
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'pdf',
        mediaMetadata: metadata,
      );

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send PDF: $e')));
      }
    }
  }

  Future<void> _pickAndSendAudioFile() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final ext = result.files.single.extension?.toLowerCase();
      final mime = _inferAudioMime(ext);

      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/$fileName',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: fileSize,
        mimeType: mime,
        originalFileName: fileName,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name ?? 'User',
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'audio',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0);
        _lastUploadPercent[pendingId] = -1;
      });

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          if (!mounted) return;
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;
          _lastUploadPercent[pendingId] = percent;
          _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();
        },
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name ?? 'User',
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'audio',
        mediaMetadata: metadata,
      );

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send audio: $e')));
      }
    }
  }

  Future<void> _startRecording() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    if (!await _audioRecorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission needed')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ptg_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacHe, bitRate: 128000),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingPath = path;
      _recordingDuration.value = 0;
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _recordingDuration.value++,
    );
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();

    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);

    if (path == null) return;
    final file = File(path);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isUploading = true);
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name ?? 'User',
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'audio',
        mediaMetadata: metadata,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send recording: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
      try {
        if (_recordingPath != null) File(_recordingPath!).deleteSync();
      } catch (_) {}
    }
  }

  String _inferAudioMime(String? ext) {
    switch (ext) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'flac':
        return 'audio/flac';
      default:
        return 'audio/mpeg';
    }
  }
}
