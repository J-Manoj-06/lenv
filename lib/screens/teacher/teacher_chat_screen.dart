import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:async';
import '../../services/chat_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/background_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/modern_attachment_sheet.dart';

class TeacherChatScreen extends StatefulWidget {
  final String schoolCode;
  final String teacherId;
  final String parentId;
  final String studentId;
  final String parentName;
  final String className;
  final String? section;
  final String? parentAvatarUrl;

  const TeacherChatScreen({
    super.key,
    required this.schoolCode,
    required this.teacherId,
    required this.parentId,
    required this.studentId,
    required this.parentName,
    required this.className,
    this.section,
    this.parentAvatarUrl,
  });

  @override
  State<TeacherChatScreen> createState() => _TeacherChatScreenState();
}

class _TeacherChatScreenState extends State<TeacherChatScreen> {
  final ChatService _chat = ChatService();
  final TextEditingController _controller = TextEditingController();
  String? _conversationId;
  // Track messages already scheduled for read marking to avoid re-scheduling.
  final Set<String> _scheduledReadIds = <String>{};

  // Media handling
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  final bool _isUploading = false;

  Future<void> _batchUpdateIncoming(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_conversationId == null) return;

    final deliveryBatch = FirebaseFirestore.instance.batch();
    bool deliveryUpdates = false;
    final List<DocumentReference<Map<String, dynamic>>> toMarkRead = [];

    for (final d in docs) {
      final data = d.data();
      final senderRole = (data['senderRole'] ?? '').toString();
      if (senderRole != 'teacher') {
        // Incoming from parent – mark delivered immediately.
        if (data['deliveredToTeacher'] != true) {
          deliveryBatch.update(d.reference, {'deliveredToTeacher': true});
          deliveryUpdates = true;
        }
        // Schedule read marking (delayed) if not already read/scheduled.
        final id = d.id;
        if (data['readByTeacher'] != true && !_scheduledReadIds.contains(id)) {
          _scheduledReadIds.add(id);
          toMarkRead.add(d.reference);
        }
      }
    }

    if (deliveryUpdates) {
      await deliveryBatch.commit();
    }

    if (toMarkRead.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 1200), () async {
        if (!mounted || _conversationId == null) return;
        final readBatch = FirebaseFirestore.instance.batch();
        for (final ref in toMarkRead) {
          readBatch.update(ref, {'readByTeacher': true});
        }
        await readBatch.commit();
        await _chat.markAsRead(
          conversationId: _conversationId!,
          viewerRole: 'teacher',
        );
      });
    }
  }

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

    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureConversation());
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _ensureConversation() async {
    final id = await _chat.ensureConversation(
      schoolCode: widget.schoolCode,
      teacherId: widget.teacherId,
      parentId: widget.parentId,
      studentId: widget.studentId,
      studentName: widget.parentName, // not used by teacher, placeholder
      className: widget.className,
      section: widget.section,
    );

    setState(() => _conversationId = id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF6F7F8),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey.shade800,
              backgroundImage: widget.parentAvatarUrl != null
                  ? NetworkImage(widget.parentAvatarUrl!)
                  : null,
              child: widget.parentAvatarUrl == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.parentName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  Text(
                    '${widget.className}${widget.section != null ? ' - ${widget.section}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _conversationId == null
                ? const SizedBox()
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _chat.messagesStream(_conversationId!),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      if (_conversationId != null && docs.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _batchUpdateIncoming(docs),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final msg = docs[index].data();
                          final isTeacher = msg['senderRole'] == 'teacher';
                          final deliveredToParent =
                              (msg['deliveredToParent'] ?? false) as bool;
                          final readByParent =
                              (msg['readByParent'] ?? false) as bool;
                          return Align(
                            alignment: isTeacher
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: isTeacher
                                      ? const Color(0xFF1362EB)
                                      : (isDark
                                            ? const Color(0xFF2A2A2A)
                                            : Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(12)
                                      .copyWith(
                                        bottomRight: isTeacher
                                            ? const Radius.circular(4)
                                            : null,
                                        bottomLeft: !isTeacher
                                            ? const Radius.circular(4)
                                            : null,
                                      ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Media handling
                                      if (msg['mediaMetadata'] != null) ...[
                                        _buildMediaAttachment(
                                          msg['mediaMetadata'],
                                          isTeacher,
                                        ),
                                        if ((msg['text'] ?? '').isNotEmpty)
                                          const SizedBox(height: 8),
                                      ],
                                      if ((msg['text'] ?? '').isNotEmpty)
                                        Text(
                                          msg['text'] ?? '',
                                          style: TextStyle(
                                            color: isTeacher
                                                ? Colors.white
                                                : (isDark
                                                      ? Colors.white
                                                      : Colors.black87),
                                          ),
                                        ),
                                      if (isTeacher) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              readByParent
                                                  ? Icons.done_all
                                                  : deliveredToParent
                                                  ? Icons.done_all
                                                  : Icons.done,
                                              size: 16,
                                              color: readByParent
                                                  ? Colors.lightBlueAccent
                                                  : Colors.white70,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: docs.length,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isUploading ? null : _showMediaOptions,
                    icon: Icon(
                      Icons.attach_file,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey.shade200,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(9999),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: _isUploading
                        ? Colors.grey
                        : const Color(0xFF1362EB),
                    child: IconButton(
                      onPressed: (_isUploading || _conversationId == null)
                          ? null
                          : () => _sendMessage(),
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaAttachment(Map<String, dynamic> metadata, bool isMe) {
    // Convert map to MediaMetadata
    final r2Key = metadata['r2Key'] as String? ?? '';
    final fileName = _fileNameFromR2Key(r2Key);
    final mimeType =
        metadata['mimeType'] as String? ?? 'application/octet-stream';
    final fileSize = metadata['fileSize'] as int? ?? 0;
    final thumbnailBase64 = metadata['thumbnail'] as String?;
    final localPath = metadata['localPath'] as String?;

    return MediaPreviewCard(
      r2Key: r2Key,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      thumbnailBase64: thumbnailBase64,
      localPath: localPath,
      isMe: isMe,
    );
  }

  String _fileNameFromR2Key(String r2Key) {
    // Extract filename from R2 key (format: media/timestamp/filename.ext)
    final parts = r2Key.split('/');
    return parts.isNotEmpty ? parts.last : 'file';
  }

  String _extractR2Key(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return path;
  }

  void _showMediaOptions() {
    showModernAttachmentSheet(
      context,
      onImageTap: _pickAndSendImage,
      onPdfTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudio,
    );
  }

  Future<void> _sendMessage({Map<String, dynamic>? mediaMetadata}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && mediaMetadata == null) return;
    if (_conversationId == null) return;

    _controller.clear();

    try {
      await _chat.sendMessage(
        conversationId: _conversationId!,
        text: text,
        senderRole: 'teacher',
        mediaMetadata: mediaMetadata,
      );
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
        imageQuality: 70,
      );
      if (image == null) return;

      final file = File(image.path);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image file not found')));
        return;
      }

      if (_conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initializing conversation...')),
        );
        return;
      }

      // Queue upload in background service
      final uploadId = await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
      );

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Image queued for upload'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Could navigate to uploads page if needed
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue image: $e')));
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
      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF file not found')));
        return;
      }

      if (_conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initializing conversation...')),
        );
        return;
      }

      // Queue upload in background service
      final uploadId = await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
      );

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('PDF queued for upload'),
          action: SnackBarAction(label: 'View', onPressed: () {}),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue PDF: $e')));
    }
  }

  Future<void> _pickAndSendAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Audio file not found')));
        return;
      }

      if (_conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Initializing conversation...')),
        );
        return;
      }

      // Queue upload in background service
      final uploadId = await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: _conversationId!,
        senderId: widget.teacherId,
        senderRole: 'teacher',
        mediaType: 'message',
      );

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Audio queued for upload'),
          action: SnackBarAction(label: 'View', onPressed: () {}),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue audio: $e')));
    }
  }
}
