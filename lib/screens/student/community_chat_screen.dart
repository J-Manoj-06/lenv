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
import '../../providers/student_provider.dart';
import '../../services/community_service.dart';
import '../common/announcement_pageview_screen.dart';
import '../../services/media_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import 'package:path_provider/path_provider.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../../models/media_metadata.dart';
import '../../widgets/media_preview_card.dart';
import 'package:mime/mime.dart';

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
  bool _showEmojiPicker = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  late Timer _recordingTimer;
  double _slideOffsetX = 0;
  bool _isCancelled = false;
  final Set<String> _selectedMessages = {};
  bool _isSelectionMode = false;
  // Optimistic pending messages and per-upload progress
  final List<CommunityMessageModel> _pendingMessages = [];
  final Map<String, double> _pendingUploadProgress = {};
  // Sender-only local paths to avoid re-downloading our own uploads
  final Map<String, String> _localSenderMediaPaths = {};

  // Theme helpers
  Color get _primary => const Color(0xFFF2800D);
  Color _surface(BuildContext context) => Theme.of(context).cardColor;
  Color _onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  Color _muted(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.65) ??
      Colors.grey;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));

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
    if (_scrollController.hasClients) {
      // Only auto-scroll if user is at bottom (within 100 pixels) or force is true
      if (force || _scrollController.offset < 100) {
        _scrollController.jumpTo(0);
      }
    }
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

  void _showCommunityInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface(context),
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
                        style: TextStyle(
                          color: _onSurface(context),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.community.memberCount} members',
                        style: TextStyle(color: _muted(context), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (widget.community.description.isNotEmpty) ...[
              Text(
                'Description',
                style: TextStyle(
                  color: _primary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.community.description,
                style: TextStyle(color: _muted(context), fontSize: 14),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'Community Rules',
              style: TextStyle(
                color: _primary,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isAllowed
            ? _surface(context).withOpacity(0.5)
            : Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAllowed
              ? Theme.of(context).dividerColor.withOpacity(0.3)
              : Colors.red.withOpacity(0.2),
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
              color: isAllowed ? _onSurface(context) : Colors.red.shade400,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
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

      if (!mounted) return;
      setState(() => _isUploading = true);
      // WhatsApp-style upload with optimistic pending
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      // Pending metadata for immediate render
      final pendingMetadata = MediaMetadata(
        messageId: messageId,
        r2Key: 'pending/$messageId',
        publicUrl: '',
        localPath: image.path,
        thumbnail: '',
        deletedLocally: false,
        serverStatus: ServerStatus.available,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await File(image.path).length(),
        // We compress to JPEG in the worker upload flow
        mimeType: 'image/jpeg',
        originalFileName:
            image.name.isNotEmpty ? image.name : image.path.split('/').last,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: 'pending:$messageId',
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
        senderAvatar: '',
        type: 'image',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: '',
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        updatedAt: null,
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
        deletedFor: const [],
      );

      if (mounted) {
        setState(() {
          _pendingMessages.insert(0, pendingMessage);
          _pendingUploadProgress[messageId] = 0.0;
        });
        _scrollToBottom(force: true);
      }

      final result = await _whatsappMediaUpload.uploadImage(
        imageFile: File(image.path),
        messageId: messageId,
        conversationId: widget.community.id,
        senderId: student.uid,
        aggressiveCompression: true, // Use aggressive mode for community chat
        onProgress: (progress) {
          if (!mounted) return;
          final doubleVal = (progress as num).toDouble();
          final normalized = doubleVal > 1 ? (doubleVal / 100.0) : doubleVal;
          setState(() {
            _pendingUploadProgress[messageId] = normalized;
          });
        },
      );

      if (mounted) {
        setState(() => _isUploading = false);
      }

      if (result.success && result.metadata != null) {
        // Keep sender-local path to avoid re-download
        _localSenderMediaPaths[result.metadata!.messageId] = image.path;
        debugPrint('📌 Cached sender local path: ${image.path} for messageId: ${result.metadata!.messageId}');

        await _communityService.sendMessage(
          communityId: widget.community.id,
          senderId: student.uid,
          senderName: student.name,
          senderRole: 'Student',
          content: '',
          imageUrl: '',
          mediaType: 'image',
          mediaMetadata: result.metadata,
        );

        if (mounted) {
          setState(() {
            _pendingMessages.removeWhere(
              (m) => m.mediaMetadata?.messageId == messageId,
            );
            _pendingUploadProgress.remove(messageId);
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image sent successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        debugPrint('❌ UploadResult failure: error=${result.error} message=${result.errorMessage}');
        throw Exception(result.errorMessage ?? result.error?.message ?? 'Upload failed');
      }
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _pendingMessages.removeWhere((m) => m.messageId.startsWith('pending:'));
          _pendingUploadProgress.clear();
        });
      }
      debugPrint('❌ CommunityChat image send failed: $e');
      debugPrint('📄 Stacktrace: $st');
      
      // User-friendly error message
      String userMessage = 'Failed to send image';
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('network') || errorStr.contains('connection')) {
        userMessage = 'Network error. Please check your connection and try again.';
      } else if (errorStr.contains('timeout')) {
        userMessage = 'Upload timeout. Please check your connection.';
      } else if (errorStr.contains('invalid')) {
        userMessage = 'Invalid image file. Please try another image.';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () => _pickAndSendImage(),
            ),
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
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      // Pending metadata for immediate render from local disk
      final pendingMetadata = MediaMetadata(
        messageId: messageId,
        r2Key: 'pending/$messageId',
        publicUrl: '',
        localPath: file.path,
        thumbnail: '',
        deletedLocally: false,
        serverStatus: ServerStatus.available,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await file.length(),
        mimeType: 'application/pdf',
        originalFileName: fileName,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: 'pending:$messageId',
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
        senderAvatar: '',
        type: 'pdf',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        updatedAt: null,
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
        deletedFor: const [],
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadProgress[messageId] = 0.0;
      });
      _scrollToBottom(force: true);

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.community.id,
        senderId: student.uid,
        senderRole: 'Student',
        mediaType: 'community',
        onProgress: (progress) {
          final doubleVal = (progress as num).toDouble();
          final normalized = doubleVal > 1 ? (doubleVal / 100.0) : doubleVal;
          setState(() {
            _pendingUploadProgress[messageId] = normalized;
          });
        },
      );

      setState(() => _isUploading = false);

      debugPrint('📦 PDF Upload complete:');
      debugPrint('   File size: ${mediaMessage.fileSize} bytes');
      debugPrint('   File type: ${mediaMessage.fileType}');
      debugPrint('   R2 URL: ${mediaMessage.r2Url}');

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

      // Keep sender-local path to avoid re-download
      _localSenderMediaPaths[mediaMessage.id] = file.path;

      await _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
        content: '',
        mediaType: 'pdf',
        mediaMetadata: metadata,
      );

      setState(() {
        _pendingMessages.removeWhere(
          (m) => m.mediaMetadata?.messageId == messageId,
        );
        _pendingUploadProgress.remove(messageId);
      });

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
      setState(() {
        _pendingMessages.removeWhere((m) => m.messageId.startsWith('pending:'));
        _pendingUploadProgress.clear();
      });
      if (mounted) {
        final errorMessage = e.toString();
        final isTimeSyncError = errorMessage.contains('RequestTimeTooSkewed');
        final isSignatureError = errorMessage.contains('SignatureDoesNotMatch');

        String message;
        if (isTimeSyncError) {
          message =
              'Upload failed: Please check your device date & time settings';
        } else if (isSignatureError) {
          message =
              'Upload failed: File name contains special characters. Please rename the file and try again.';
        } else {
          message = 'Failed to send PDF: $e';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: Duration(
              seconds: isTimeSyncError || isSignatureError ? 5 : 3,
            ),
          ),
        );
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
      final fileName = result.files.single.name;

      final student = Provider.of<StudentProvider>(
        context,
        listen: false,
      ).currentStudent;
      if (student == null) return;

      setState(() => _isUploading = true);
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      final pendingMetadata = MediaMetadata(
        messageId: messageId,
        r2Key: 'pending/$messageId',
        publicUrl: '',
        localPath: file.path,
        thumbnail: '',
        deletedLocally: false,
        serverStatus: ServerStatus.available,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await file.length(),
        mimeType: _guessMimeType(fileName),
        originalFileName: fileName,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: 'pending:$messageId',
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
        senderAvatar: '',
        type: 'audio',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        updatedAt: null,
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
        deletedFor: const [],
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadProgress[messageId] = 0.0;
      });
      _scrollToBottom(force: true);

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.community.id,
        senderId: student.uid,
        senderRole: 'Student',
        mediaType: 'community',
        onProgress: (progress) {
          final doubleVal = (progress as num).toDouble();
          final normalized = doubleVal > 1 ? (doubleVal / 100.0) : doubleVal;
          setState(() {
            _pendingUploadProgress[messageId] = normalized;
          });
        },
      );

      setState(() => _isUploading = false);

      debugPrint('🎵 Audio Upload complete:');
      debugPrint('   File size: ${mediaMessage.fileSize} bytes');
      debugPrint('   R2 URL: ${mediaMessage.r2Url}');

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

      // Keep sender-local path so playback is instant without download
      _localSenderMediaPaths[mediaMessage.id] = file.path;

      await _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
        content: '',
        mediaType: 'audio',
        mediaMetadata: metadata,
      );

      setState(() {
        _pendingMessages.removeWhere(
          (m) => m.mediaMetadata?.messageId == messageId,
        );
        _pendingUploadProgress.remove(messageId);
      });

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
      setState(() {
        _pendingMessages.removeWhere((m) => m.messageId.startsWith('pending:'));
        _pendingUploadProgress.clear();
      });
      if (mounted) {
        final errorMessage = e.toString();
        final isTimeSyncError = errorMessage.contains('RequestTimeTooSkewed');
        final isSignatureError = errorMessage.contains('SignatureDoesNotMatch');

        String message;
        if (isTimeSyncError) {
          message =
              'Upload failed: Please check your device date & time settings';
        } else if (isSignatureError) {
          message =
              'Upload failed: File name contains special characters. Please rename the file and try again.';
        } else {
          message = 'Failed to send audio: $e';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: Duration(
              seconds: isTimeSyncError || isSignatureError ? 5 : 3,
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteRecording() async {
    // Stop recording if active
    if (_isRecording) {
      await _audioRecorder.stop();
      try {
        _recordingTimer.cancel();
      } catch (e) {
        // Timer might not be initialized
        print('Timer cancel error: $e');
      }
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

  Future<void> _sendRecording() async {
    if (_recordingPath == null) return;

    final student = Provider.of<StudentProvider>(
      context,
      listen: false,
    ).currentStudent;
    if (student == null) return;

    // Stop recording FIRST - this is critical
    if (_isRecording) {
      try {
        await _audioRecorder.stop();
      } catch (e) {
        print('Error stopping recorder: $e');
      }

      try {
        _recordingTimer.cancel();
      } catch (e) {
        print('Timer cancel error: $e');
      }
    }

    // IMMEDIATELY update UI to show we're not recording anymore
    setState(() {
      _isRecording = false;
      _isUploading = true;
    });

    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // Pending metadata/message for optimistic render
    final pendingMetadata = MediaMetadata(
      messageId: messageId,
      r2Key: 'pending/$messageId',
      publicUrl: '',
      localPath: _recordingPath,
      thumbnail: '',
      deletedLocally: false,
      serverStatus: ServerStatus.available,
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      uploadedAt: DateTime.now(),
      fileSize:
          _recordingPath != null ? await File(_recordingPath!).length() : null,
      mimeType: 'audio/aac',
      originalFileName: _recordingPath != null
          ? Uri.file(_recordingPath!).pathSegments.last
          : null,
    );

    final pendingMessage = CommunityMessageModel(
      messageId: 'pending:$messageId',
      communityId: widget.community.id,
      senderId: student.uid,
      senderName: student.name,
      senderRole: 'Student',
      senderAvatar: '',
      type: 'audio',
      content: '',
      imageUrl: '',
      fileUrl: '',
      fileName: pendingMetadata.originalFileName ?? '',
      mediaMetadata: pendingMetadata,
      createdAt: DateTime.now(),
      updatedAt: null,
      isEdited: false,
      isDeleted: false,
      isPinned: false,
      reactions: {},
      replyTo: '',
      replyCount: 0,
      isReported: false,
      reportCount: 0,
      deletedFor: const [],
    );

    setState(() {
      _pendingMessages.insert(0, pendingMessage);
      _pendingUploadProgress[messageId] = 0.0;
    });
    _scrollToBottom(force: true);

    try {
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: File(_recordingPath!),
        conversationId: widget.community.id,
        senderId: student.uid,
        senderRole: 'Student',
        mediaType: 'community',
        onProgress: (progress) {
          final doubleVal = (progress as num).toDouble();
          final normalized = doubleVal > 1 ? (doubleVal / 100.0) : doubleVal;
          setState(() {
            _pendingUploadProgress[messageId] = normalized;
          });
        },
      );

      debugPrint('🎵 Recording Upload complete:');
      debugPrint('   File size: ${mediaMessage.fileSize} bytes');
      debugPrint('   R2 URL: ${mediaMessage.r2Url}');

      // Copy recorded audio to cache for local playback before deleting temp
      String? cachedPath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final cacheDir = Directory('${appDir.path}/audio_cache');
        if (!await cacheDir.exists()) {
          await cacheDir.create(recursive: true);
        }
        final fileName = mediaMessage.r2Url.split('/').last;
        final cachedFile = File('${cacheDir.path}/$fileName');
        await File(_recordingPath!).copy(cachedFile.path);
        cachedPath = cachedFile.path;
        print('✅ Cached recorded audio locally at: $cachedPath');
      } catch (e) {
        print('⚠️ Failed to cache audio: $e');
      }

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
        localPath: cachedPath,
        originalFileName: mediaMessage.fileName,
      );

      await _communityService.sendMessage(
        communityId: widget.community.id,
        senderId: student.uid,
        senderName: student.name,
        senderRole: 'Student',
        content: '',
        mediaType: 'audio',
        mediaMetadata: metadata,
      );

      // Remove pending and progress
      setState(() {
        _pendingMessages.removeWhere(
          (m) => m.mediaMetadata?.messageId == messageId,
        );
        _pendingUploadProgress.remove(messageId);
      });

      // Store sender-local path for playback
      if (cachedPath != null) {
        _localSenderMediaPaths[mediaMessage.id] = cachedPath;
      }

      // Delete the temporary recording file
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
            backgroundColor: Colors.green,
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
          _pendingMessages.removeWhere((m) => m.messageId.startsWith('pending:'));
          _pendingUploadProgress.clear();
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

  bool _containsUrl(String text) {
    final urlPattern = RegExp(
      r'(https?:\/\/)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text);
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

  String _getFileNameFromMetadata(MediaMetadata metadata) {
    // Prefer exact original filename if present
    final orig = metadata.originalFileName;
    if (orig != null && orig.isNotEmpty) return orig;
    final parts = metadata.r2Key.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.last;
    return _getFileNameFromUrl(metadata.publicUrl);
  }

  String _getFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return 'file';
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    return 'application/octet-stream';
  }

  PreferredSizeWidget _buildAppBar() {
    final theme = Theme.of(context);
    return AppBar(
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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.primaryColor.withOpacity(0.15),
                    border: Border.all(
                      color: theme.primaryColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.community.getCategoryIcon(),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.community.name,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                onPressed: _selectedMessages.isEmpty ? null : _showDeleteDialog,
              ),
            ]
          : null,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: theme.dividerColor.withOpacity(0.1)),
      ),
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? theme.cardColor.withOpacity(0.4) : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.dividerColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Text(
            _formatDate(date),
            style: TextStyle(
              color: _muted(context),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
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
    bool isUploading,
    double? uploadProgress,
    Map<String, String> localSenderMediaPaths,
  ) {
    final isSelected = _selectedMessages.contains(message.messageId);
    return GestureDetector(
      onLongPress: () {
        setState(() {
          _isSelectionMode = true;
          _selectedMessages.add(message.messageId);
        });
      },
      onTap: _isSelectionMode
          ? () {
              setState(() {
                if (isSelected) {
                  _selectedMessages.remove(message.messageId);
                  if (_selectedMessages.isEmpty) {
                    _isSelectionMode = false;
                  }
                } else {
                  _selectedMessages.add(message.messageId);
                }
              });
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: isCurrentUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
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
          if (!isCurrentUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFFA726).withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFA726).withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  message.senderName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFFFA726),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isCurrentUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5, left: 4),
                    child: Text(
                      message.senderName,
                      style: const TextStyle(
                        color: Color(0xFF6B7075),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrentUser
                            ? const Color(0xFFFFE8D1)
                            : const Color(0xFF1A1D21),
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
                          // Media with metadata (images, PDFs, audio)
                          if (message.mediaMetadata != null) ...[
                            MediaPreviewCard(
                              r2Key: message.mediaMetadata!.r2Key,
                              fileName: _getFileNameFromMetadata(
                                message.mediaMetadata!,
                              ),
                              mimeType:
                                  message.mediaMetadata!.mimeType ??
                                  'application/octet-stream',
                              fileSize: message.mediaMetadata!.fileSize ?? 0,
                              thumbnailBase64: message.mediaMetadata!.thumbnail,
                              localPath: message.mediaMetadata!.localPath ??
                                  localSenderMediaPaths[
                                    message.mediaMetadata!.messageId
                                  ],
                              isMe: isCurrentUser,
                              uploading: isUploading,
                              uploadProgress: uploadProgress,
                            ),
                            if (message.content.isNotEmpty)
                              const SizedBox(height: 8),
                          ],
                          // Text content
                          if (message.content.isNotEmpty)
                            Text(
                              message.content,
                              style: TextStyle(
                                color: isCurrentUser
                                    ? const Color(0xFF1A1D21)
                                    : const Color(0xFFE8E8E8),
                                fontSize: 15,
                                height: 1.45,
                                letterSpacing: 0.15,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!isCurrentUser && message.senderRole == 'Teacher')
                      Positioned(
                        left: -4,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF64B5F6).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF64B5F6).withOpacity(0.4),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.school_outlined,
                                size: 10,
                                color: Color(0xFF64B5F6),
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Teacher',
                                style: TextStyle(
                                  color: Color(0xFF64B5F6),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 4, right: 4),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF6B7075),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
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
              .collection('communities')
              .doc(widget.community.id)
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
                  await CloudflareR2Service(
                    accountId: CloudflareConfig.accountId,
                    bucketName: CloudflareConfig.bucketName,
                    accessKeyId: CloudflareConfig.accessKeyId,
                    secretAccessKey: CloudflareConfig.secretAccessKey,
                    r2Domain: CloudflareConfig.r2Domain,
                  ).deleteFile(key: r2Key);
                  print('🗑️ Deleted media from Cloudflare: $r2Key');
                } catch (e) {
                  print('⚠️ Failed to delete media from Cloudflare: $e');
                }
              }
            }
          }

          // Delete message from Firestore for everyone
          await FirebaseFirestore.instance
              .collection('communities')
              .doc(widget.community.id)
              .collection('messages')
              .doc(messageId)
              .delete();
        } else {
          // Delete for me only - mark as deleted for this user
          final student = Provider.of<StudentProvider>(
              context,
              listen: false,
            ).currentStudent;
          final currentUserId = student?.uid;
          if (currentUserId != null) {
            await FirebaseFirestore.instance
                .collection('communities')
                .doc(widget.community.id)
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

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inputBg = _surface(context);
    final borderColor = theme.dividerColor;

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor.withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  _showEmojiPicker
                      ? Icons.keyboard
                      : Icons.emoji_emotions_outlined,
                  color: _muted(context),
                ),
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
                  style: TextStyle(
                    color: _onSurface(context),
                    fontSize: 15,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: _muted(context)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
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
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.attach_file, color: _muted(context), size: 22),
                padding: const EdgeInsets.all(8),
                onPressed: _isUploading ? null : _showMediaOptions,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  if (_messageController.text.trim().isNotEmpty &&
                      !_isUploading) {
                    _sendMessage();
                  } else if (!_isRecording &&
                      _messageController.text.trim().isEmpty &&
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? const Color(0xFFE57373)
                        : (_messageController.text.trim().isNotEmpty
                              ? const Color(0xFFFFA726)
                              : const Color(0xFFFFA929)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isRecording
                        ? Icons.mic
                        : (_messageController.text.trim().isNotEmpty
                              ? Icons.send_rounded
                              : Icons.mic_none),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
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
                    const Text(
                      'Sending audio...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                )
              : Row(
                  children: [
                    // Delete button
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: _isRecording ? _deleteRecording : null,
                    ),
                    // Recording duration
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
                    // Send button
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF00A884)),
                      onPressed: _sendRecording,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final student = Provider.of<StudentProvider>(context).currentStudent;
    if (student == null) {
      return const Scaffold(body: Center(child: Text('No student data')));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<CommunityMessageModel>>(
                  stream: _communityService.getMessagesStream(
                    widget.community.id,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_primary),
                        ),
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

                    // Filter out expired announcements (24h visibility) and deleted messages
                    final now = DateTime.now();
                    final messagesFromServer = (snapshot.data ?? [])
                        .where(
                          (m) =>
                              (m.type != 'announcement' ||
                                  now.difference(m.createdAt) <
                                      const Duration(hours: 24)) &&
                              !(m.deletedFor?.contains(student.uid) ?? false),
                        )
                        .toList();

                    // Merge pending optimistic messages
                    final combined = <CommunityMessageModel>[];
                    combined.addAll(messagesFromServer);
                    final seenIds = messagesFromServer
                        .map((m) => m.mediaMetadata?.messageId ?? m.messageId)
                        .toSet();
                    for (final pending in _pendingMessages) {
                      final key =
                          pending.mediaMetadata?.messageId ?? pending.messageId;
                      if (!seenIds.contains(key)) {
                        combined.add(pending);
                      }
                    }

                    combined.sort(
                      (a, b) => b.createdAt.compareTo(a.createdAt),
                    );

                    if (combined.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: _muted(context).withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                color: _muted(context).withOpacity(0.6),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Be the first to say hello!',
                              style: TextStyle(
                                color: _muted(context).withOpacity(0.4),
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
                      itemCount: combined.length,
                      itemBuilder: (context, index) {
                        final message = combined[index];
                        final isCurrentUser = message.senderId == student.uid;
                        final metaId =
                            message.mediaMetadata?.messageId ?? message.messageId;
                        final isPending = message.messageId.startsWith('pending:') ||
                            (message.mediaMetadata?.r2Key
                                    .startsWith('pending/') ??
                                false);
                        final uploadProgress =
                            isPending ? _pendingUploadProgress[metaId] : null;
                        final showDateDivider =
                            index == combined.length - 1 ||
                            _formatDate(message.createdAt) !=
                                _formatDate(combined[index + 1].createdAt);

                        return Column(
                          children: [
                            if (message.type == 'announcement')
                              _buildAnnouncement(message)
                            else
                              _buildMessageBubble(
                                message,
                                isCurrentUser,
                                student.name,
                                isPending,
                                uploadProgress,
                                _localSenderMediaPaths,
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
                      backgroundColor: _surface(context),
                      columns: 7,
                      emojiSizeMax: 28,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: const Color(0xFF1A1C20),
                      iconColorSelected: const Color(0xFFFFA929),
                      indicatorColor: const Color(0xFFFFA929),
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: const Color(0xFF1A1C20),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_recordingPath != null) _buildRecordingOverlay(),
      ],
    );
  }
}
