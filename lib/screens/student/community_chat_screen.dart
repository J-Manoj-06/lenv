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
import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/link_utils.dart';
import '../../models/community_model.dart';
import '../../models/community_message_model.dart';
import '../../providers/student_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../services/community_service.dart';
import '../common/announcement_pageview_screen.dart';
import '../../services/media_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../services/media_repository.dart';
import '../../services/background_upload_service.dart';
import '../../config/cloudflare_config.dart';
import 'package:path_provider/path_provider.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../../models/media_metadata.dart';
import '../../widgets/media_preview_card.dart';

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
  final MediaRepository _mediaRepository = MediaRepository();
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
  // Tracking for message location and highlight
  final Map<String, GlobalKey> _messageKeys = {};
  Set<String> _visibleMessageIds = {};
  String? _highlightMessageId;
  Timer? _highlightResetTimer;

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
    // Avoid full-screen rebuild on each keystroke; use local ValueListenableBuilder instead
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

    // Bridge background upload progress to UI (pending optimistic messages)
    BackgroundUploadService().onUploadProgress =
        (String messageId, bool isUploading, double progress) {
          if (!mounted) return;
          setState(() {
            if (isUploading) {
              _pendingUploadProgress[messageId] = progress;
            } else {
              // Upload complete - only remove progress, keep pending visible
              // Dedup logic will remove pending when server message arrives
              _pendingUploadProgress.remove(messageId);
            }
          });
        };

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(force: true),
    );
  }

  @override
  void dispose() {
    // Mark chat as read when leaving to prevent self-unread badges
    try {
      final unread = Provider.of<UnreadCountProvider>(context, listen: false);
      unread.markChatAsRead(widget.community.id);
    } catch (_) {}

    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _audioRecorder.dispose();
    _highlightResetTimer?.cancel();
    _messageKeys.clear();
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

  Future<void> _locateMessage(CommunityMessageModel message) async {
    final targetId = message.messageId;
    if (targetId.isEmpty) return;

    if (!_visibleMessageIds.contains(targetId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message is outside the currently loaded window'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _highlightMessageId = targetId;
    });

    await Future.delayed(const Duration(milliseconds: 30));

    final contextForTarget = _messageKeys[targetId]?.currentContext;
    if (contextForTarget != null && mounted) {
      await Scrollable.ensureVisible(
        contextForTarget,
        alignment: 0.5,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }

    _highlightResetTimer?.cancel();
    _highlightResetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _highlightMessageId == targetId) {
        setState(() => _highlightMessageId = null);
      }
    });
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

  // ignore: unused_element
  void _showCommunityInfo() {
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
        thumbnail: image.path, // show immediate local preview
        deletedLocally: false,
        serverStatus: ServerStatus.available,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await File(image.path).length(),
        // We compress to JPEG in the worker upload flow
        mimeType: 'image/jpeg',
        originalFileName: image.name.isNotEmpty
            ? image.name
            : image.path.split('/').last,
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
        // Cache the uploaded image to local storage
        final r2Key = result.metadata!.r2Key;
        await _mediaRepository.cacheUploadedMedia(
          r2Key: r2Key,
          localPath: image.path,
          fileName: result.metadata!.originalFileName ?? 'image.jpg',
          mimeType: result.metadata!.mimeType ?? 'image/jpeg',
          fileSize: result.metadata!.fileSize ?? 0,
          thumbnailBase64: result.metadata!.thumbnail,
        );

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
        throw Exception(
          result.errorMessage ?? result.error?.message ?? 'Upload failed',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _pendingMessages.removeWhere(
            (m) => m.messageId.startsWith('pending:'),
          );
          _pendingUploadProgress.clear();
        });
      }

      // User-friendly error message
      String userMessage = 'Failed to send image';
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('network') || errorStr.contains('connection')) {
        userMessage =
            'Network error. Please check your connection and try again.';
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

      // Do not block input; overlay is per-message
      if (mounted) setState(() => _isUploading = false);

      // Queue upload in background service; UI shows overlay via pending
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: widget.community.id,
        senderId: student.uid,
        senderRole: 'student',
        mediaType: 'message',
        chatType: 'community',
        senderName: student.name,
        messageId: messageId,
      );
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

      // Do not block input; overlay is per-message
      if (mounted) setState(() => _isUploading = false);

      // Queue upload in background service; UI shows overlay via pending
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: widget.community.id,
        senderId: student.uid,
        senderRole: 'student',
        mediaType: 'message',
        chatType: 'community',
        senderName: student.name,
        messageId: messageId,
      );
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
      }
    }

    // Delete the file
    if (_recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {}
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
      } catch (e) {}

      try {
        _recordingTimer.cancel();
      } catch (e) {}
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
      fileSize: _recordingPath != null
          ? await File(_recordingPath!).length()
          : null,
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
      } catch (e) {}

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

      // Cache the uploaded audio using MediaRepository for proper download management
      if (cachedPath != null) {
        await _mediaRepository.cacheUploadedMedia(
          r2Key: r2Key,
          localPath: cachedPath,
          fileName: mediaMessage.fileName,
          mimeType: mediaMessage.fileType,
          fileSize: mediaMessage.fileSize,
        );
      }

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

      // Delete the temporary recording file
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {}

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
          _pendingMessages.removeWhere(
            (m) => m.messageId.startsWith('pending:'),
          );
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
          : [
              IconButton(
                icon: Icon(Icons.search, color: theme.iconTheme.color),
                onPressed: _openSearch,
              ),
            ],
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
                        padding: EdgeInsets.symmetric(
                          horizontal:
                              message.mediaMetadata != null &&
                                  message.content.isEmpty
                              ? 4
                              : 14,
                          vertical:
                              message.mediaMetadata != null &&
                                  message.content.isEmpty
                              ? 4
                              : 11,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrentUser
                              ? const Color(0xFFFFE8D1)
                              : const Color(0xFF1A1D21),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isCurrentUser ? 16 : 4),
                            bottomRight: Radius.circular(
                              isCurrentUser ? 4 : 16,
                            ),
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
                                thumbnailBase64:
                                    message.mediaMetadata!.thumbnail,
                                isMe: isCurrentUser,
                                uploading: isUploading,
                                uploadProgress: uploadProgress,
                                selectionMode: _isSelectionMode,
                              ),
                              if (message.content.isNotEmpty)
                                const SizedBox(height: 8),
                            ],
                            // Text content
                            if (message.content.isNotEmpty)
                              Linkify(
                                onOpen: (link) async {
                                  final uri = Uri.parse(link.url);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                text: LinkUtils.addProtocolToBareUrls(
                                  message.content,
                                ),
                                options: const LinkifyOptions(
                                  defaultToHttps: true,
                                ),
                                style: TextStyle(
                                  color: isCurrentUser
                                      ? const Color(0xFF1A1D21)
                                      : const Color(0xFFE8E8E8),
                                  fontSize: 15,
                                  height: 1.45,
                                  letterSpacing: 0.15,
                                ),
                                linkStyle: TextStyle(
                                  color: isCurrentUser
                                      ? const Color(0xFF0066CC)
                                      : const Color(0xFFFFA726),
                                  fontSize: 15,
                                  height: 1.45,
                                  letterSpacing: 0.15,
                                  decoration: TextDecoration.underline,
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
            if (_isSelectionMode && isCurrentUser)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected ? const Color(0xFFFFA929) : Colors.grey,
                  size: 24,
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
      final currentUserId = Provider.of<StudentProvider>(
        context,
        listen: false,
      ).currentStudent?.uid;

      if (currentUserId == null) {
        throw Exception('User not found');
      }

      for (final messageId in messagesToDelete) {
        final messageRef = FirebaseFirestore.instance
            .collection('communities')
            .doc(widget.community.id)
            .collection('messages')
            .doc(messageId);

        // Get message to check sender and media
        final docSnapshot = await messageRef.get();

        if (!docSnapshot.exists) {
          continue;
        }

        final data = docSnapshot.data();
        final senderId = data?['senderId'] as String?;
        if (senderId == null || senderId != currentUserId) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can only delete your own messages'),
                backgroundColor: Colors.red,
              ),
            );
          }
          continue;
        }

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
            } catch (e) {}
          }
        }

        // ✅ FIXED: Mark message as deleted instead of completely deleting
        // This preserves chat history and allows proper filtering
        await messageRef.update({
          'isDeleted': true,
          'content': '', // Clear content
          'mediaMetadata': null, // Clear media metadata
        });
      }

      setState(() {
        _selectedMessages.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Messages',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Delete message for everyone?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessages(true);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _openSearch() {
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    final student = studentProvider.currentStudent;
    if (student == null) return;

    Navigator.of(context)
        .push<CommunityMessageModel?>(
          MaterialPageRoute(
            builder: (_) => StudentCommunityMessageSearchScreen(
              communityId: widget.community.id,
              communityService: _communityService,
              currentUserId: student.uid,
            ),
          ),
        )
        .then((selected) {
          if (selected != null) {
            _locateMessage(selected);
          }
        });
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // WhatsApp-like color palette
    final backgroundColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF5F5F5);
    final inputFieldColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark
        ? const Color(0xFFE5E5EA)
        : const Color(0xFF000000);
    final hintColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF999999);
    final iconColor = isDark
        ? const Color(0xFFFF9F0A)
        : const Color(0xFFFF8F00);
    final iconDisabledColor = isDark
        ? const Color(0xFF48484A)
        : const Color(0xFFBBBBBB);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: backgroundColor),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Input container with emoji, text field, and attachment
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 42),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: inputFieldColor,
                  borderRadius: BorderRadius.circular(21),
                  border: isDark
                      ? Border.all(color: const Color(0xFF3A3A3C), width: 0.5)
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Emoji toggle - inside input field
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _showEmojiPicker = !_showEmojiPicker;
                          });
                          if (!_showEmojiPicker) {
                            _messageFocusNode.requestFocus();
                          } else {
                            _messageFocusNode.unfocus();
                          }
                        },
                        child: Icon(
                          _showEmojiPicker
                              ? Icons.keyboard_outlined
                              : Icons.emoji_emotions_outlined,
                          color: iconColor,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Text input - visual focus
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        cursorColor: iconColor,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: hintColor, fontSize: 16),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) {
                          _sendMessage();
                          Future.delayed(const Duration(milliseconds: 50), () {
                            _messageFocusNode.requestFocus();
                          });
                        },
                      ),
                    ),
                    // Attachment - inside input field
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 8),
                      child: GestureDetector(
                        onTap: _isUploading ? null : _showMediaOptions,
                        child: Icon(
                          Icons.attach_file_rounded,
                          color: _isUploading ? iconDisabledColor : iconColor,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Mic/Send button - outside, visually lighter
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _messageController,
              builder: (context, value, child) {
                final hasText = value.text.trim().isNotEmpty;
                return GestureDetector(
                  onTap: () async {
                    if (hasText && !_isUploading) {
                      _sendMessage();
                    } else if (!_isRecording && !hasText && !_isUploading) {
                      // Single tap to start recording
                      final hasPermission = await _audioRecorder
                          .hasPermission();
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
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _isRecording ? theme.colorScheme.error : iconColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRecording
                          ? Icons.mic
                          : (hasText ? Icons.send_rounded : Icons.mic),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
          ],
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
                    // Do not block UI with a spinner while the stream connects.
                    // We want pending optimistic messages to render instantly.

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

                    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    if (combined.isEmpty) {
                      // If we're still connecting and have no messages, show a subtle loader.
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(_primary),
                          ),
                        );
                      }

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

                    final theme = Theme.of(context);
                    final isDark = theme.brightness == Brightness.dark;

                    final currentIds = combined.map((m) => m.messageId).toSet();
                    _visibleMessageIds = currentIds;
                    _messageKeys.removeWhere(
                      (key, _) => !currentIds.contains(key),
                    );

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: combined.length,
                      itemBuilder: (context, index) {
                        final message = combined[index];
                        final isCurrentUser = message.senderId == student.uid;
                        final metaId =
                            message.mediaMetadata?.messageId ??
                            message.messageId;
                        final isPending =
                            message.messageId.startsWith('pending:') ||
                            (message.mediaMetadata?.r2Key.startsWith(
                                  'pending/',
                                ) ??
                                false);
                        final uploadProgress = isPending
                            ? _pendingUploadProgress[metaId]
                            : null;
                        // Messages sorted desc; ListView reversed. The visually previous item is index+1 (older).
                        // Show divider above the oldest message of each day (day boundary with older item),
                        // and always above the global oldest.
                        final isOldest = index == combined.length - 1;
                        final older = isOldest ? null : combined[index + 1];
                        final showDateDivider =
                            isOldest ||
                            _formatDate(message.createdAt) !=
                                _formatDate(older!.createdAt);

                        final msgKey = _messageKeys.putIfAbsent(
                          message.messageId,
                          () => GlobalKey(),
                        );
                        final isHighlighted =
                            _highlightMessageId == message.messageId;
                        final highlightColor = isDark
                            ? theme.colorScheme.primary.withOpacity(0.16)
                            : theme.colorScheme.primary.withOpacity(0.12);

                        final content = message.type == 'announcement'
                            ? _buildAnnouncement(message)
                            : _buildMessageBubble(
                                message,
                                isCurrentUser,
                                student.name,
                                isPending,
                                uploadProgress,
                              );

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showDateDivider)
                              _buildDateDivider(message.createdAt),
                            TweenAnimationBuilder<double>(
                              key: msgKey,
                              tween: Tween<double>(
                                begin: 0,
                                end: isHighlighted ? 1 : 0,
                              ),
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeInOut,
                              builder: (context, value, child) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                  decoration: BoxDecoration(
                                    color: Color.lerp(
                                      Colors.transparent,
                                      highlightColor,
                                      value,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: child,
                                );
                              },
                              child: content,
                            ),
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

// Student Community Message Search Screen
class StudentCommunityMessageSearchScreen extends StatefulWidget {
  final String communityId;
  final CommunityService communityService;
  final String currentUserId;

  const StudentCommunityMessageSearchScreen({
    super.key,
    required this.communityId,
    required this.communityService,
    required this.currentUserId,
  });

  @override
  State<StudentCommunityMessageSearchScreen> createState() =>
      _StudentCommunityMessageSearchScreenState();
}

class _StudentCommunityMessageSearchScreenState
    extends State<StudentCommunityMessageSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CommunityMessageModel> _results = [];
  DocumentSnapshot? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _runSearch();
    }
  }

  Future<void> _runSearch({bool reset = false}) async {
    final q = _queryController.text.trim();

    if (q.length < 2) {
      setState(() {
        _results = [];
        _cursor = null;
        _hasMore = true;
        _lastQuery = q;
      });
      return;
    }

    if (reset || q != _lastQuery) {
      setState(() {
        _loading = true;
        _hasMore = true;
        _cursor = null;
        _results = [];
        _lastQuery = q;
      });
    } else if (!_hasMore || _loading) {
      return;
    } else {
      setState(() => _loading = true);
    }

    final page = await widget.communityService.searchMessages(
      communityId: widget.communityId,
      query: q,
      lastDoc: reset ? null : _cursor,
      limit: 25,
    );

    setState(() {
      _results.addAll(page.messages);
      _cursor = page.lastDoc;
      _hasMore = page.hasMore;
      _loading = false;
    });
  }

  String _formatTimestamp(DateTime dt) {
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  IconData _iconFor(CommunityMessageModel m) {
    final mime = m.mediaMetadata?.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime.isNotEmpty) return Icons.insert_drive_file_outlined;
    if (m.type == 'audio') return Icons.audiotrack;
    if (m.type == 'image') return Icons.image_outlined;
    if (m.type == 'pdf' || m.type == 'file') {
      return Icons.insert_drive_file_outlined;
    }
    return Icons.chat_bubble_outline;
  }

  String _primaryText(CommunityMessageModel m) {
    if (m.content.isNotEmpty) return m.content;
    if (m.mediaMetadata?.originalFileName?.isNotEmpty == true) {
      return m.mediaMetadata!.originalFileName!;
    }
    if (m.fileName.isNotEmpty) return m.fileName;
    return 'Media message';
  }

  String _secondaryText(CommunityMessageModel m) {
    final sender = m.senderName.isNotEmpty ? m.senderName : 'Unknown';
    return '${_formatTimestamp(m.createdAt)} • $sender';
  }

  void _openMedia(CommunityMessageModel message) {
    if (message.mediaMetadata == null) {
      if (message.content.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message.content)));
      }
      return;
    }

    final meta = message.mediaMetadata!;
    final mime = meta.mimeType ?? '';
    final publicUrl = meta.publicUrl;

    if (mime.startsWith('image/')) {
      _showImagePreview(publicUrl, meta);
      return;
    }

    if (mime == 'application/pdf') {
      _openPDFWithExternalApp(
        publicUrl,
        meta.originalFileName ?? 'Document.pdf',
      );
      return;
    }

    if (mime.startsWith('audio/')) {
      _showAudioPlayer(publicUrl, meta);
      return;
    }

    _handleFileDownload(publicUrl, meta.originalFileName ?? 'File');
  }

  void _handleFileDownload(String url, String fileName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $fileName...'),
        action: SnackBarAction(
          label: 'Copy URL',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('URL copied to clipboard')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showImagePreview(String publicUrl, dynamic meta) async {
    try {
      String? localPath;
      try {
        final mediaId = meta.mediaId ?? '';
        if (mediaId.isNotEmpty) {
          final cachedMedia = LocalCacheService().getCachedMediaMetadata(
            mediaId,
          );
          if (cachedMedia != null && cachedMedia['localPath'] != null) {
            final localFile = File(cachedMedia['localPath']);
            if (await localFile.exists()) {
              localPath = cachedMedia['localPath'];
            }
          }
        }
      } catch (e) {}

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: InteractiveViewer(
                  child: localPath != null
                      ? Image.file(
                          File(localPath),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              Image.network(publicUrl, fit: BoxFit.contain),
                        )
                      : Image.network(
                          publicUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text(
                              'Failed to load image',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: InteractiveViewer(
                    child: Image.network(publicUrl, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _showAudioPlayer(String publicUrl, dynamic meta) async {
    try {
      String audioUrl = publicUrl;
      try {
        final mediaId = meta.mediaId ?? '';
        if (mediaId.isNotEmpty) {
          final cachedMedia = LocalCacheService().getCachedMediaMetadata(
            mediaId,
          );
          if (cachedMedia != null && cachedMedia['localPath'] != null) {
            final localFile = File(cachedMedia['localPath']);
            if (await localFile.exists()) {
              audioUrl = cachedMedia['localPath'];
            }
          }
        }
      } catch (e) {}

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        builder: (ctx) => AudioPlayerModal(
          audioUrl: audioUrl,
          fileName: meta.originalFileName ?? 'Audio',
        ),
      );
    } catch (e) {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          builder: (ctx) => AudioPlayerModal(
            audioUrl: publicUrl,
            fileName: meta.originalFileName ?? 'Audio',
          ),
        );
      }
    }
  }

  Future<void> _openPDFWithExternalApp(String url, String fileName) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Preparing PDF...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final finalFileName = cleanFileName.endsWith('.pdf')
          ? cleanFileName
          : '$cleanFileName.pdf';
      final filePath = '${tempDir.path}/${timestamp}_$finalFileName';

      final dio = Dio();
      await dio.download(url, filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      final result = await OpenFilex.open(filePath, type: 'application/pdf');

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status: ${result.message}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: theme.iconTheme.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Search',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F1419)
                    : theme.colorScheme.surfaceContainerHighest.withOpacity(
                        0.8,
                      ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.primaryColor.withOpacity(0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      autofocus: true,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Messages, files, audio...',
                        hintStyle: TextStyle(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.4,
                          ),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        suffixIcon: _queryController.text.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withOpacity(0.6),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  splashRadius: 16,
                                  onPressed: () {
                                    _queryController.clear();
                                    _runSearch(reset: true);
                                  },
                                ),
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(reset: true),
                      onChanged: (_) => _runSearch(reset: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_queryController.text.trim().length < 2)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.primaryColor.withOpacity(0.1),
                      ),
                      child: Icon(
                        Icons.search_rounded,
                        size: 50,
                        color: theme.primaryColor.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Search Messages',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Find messages, PDFs, images, or audio files',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.6,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.primaryColor.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Type at least 2 characters',
                        style: TextStyle(
                          color: theme.primaryColor.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _results.length + (_loading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _results.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final message = _results[index];
                  final isMe = message.senderId == widget.currentUserId;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, message),
                        onLongPress: () => _openMedia(message),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : theme.dividerColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: theme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _iconFor(message),
                                  color: theme.primaryColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _primaryText(message),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.textTheme.bodyLarge?.color,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _secondaryText(message),
                                      style: TextStyle(
                                        color: theme.textTheme.bodySmall?.color
                                            ?.withOpacity(0.6),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isMe)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    size: 14,
                                    color: theme.primaryColor.withOpacity(0.7),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_results.isEmpty &&
              !_loading &&
              _queryController.text.trim().length >= 2)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.1),
                      ),
                      child: Icon(
                        Icons.search_off_rounded,
                        size: 40,
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No matches found',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching with different keywords',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.6,
                        ),
                        fontSize: 13,
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
}

// Audio Player Modal (Bottom Sheet)
class AudioPlayerModal extends StatefulWidget {
  final String audioUrl;
  final String fileName;

  const AudioPlayerModal({
    super.key,
    required this.audioUrl,
    required this.fileName,
  });

  @override
  State<AudioPlayerModal> createState() => _AudioPlayerModalState();
}

class _AudioPlayerModalState extends State<AudioPlayerModal> {
  bool _isPlaying = false;
  final Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          Text(
            widget.fileName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 48,
                icon: Icon(
                  _isPlaying ? Icons.pause_circle : Icons.play_circle,
                  color: Colors.blue,
                ),
                onPressed: () {
                  setState(() => _isPlaying = !_isPlaying);
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          Slider(
            value: _position.inSeconds.toDouble(),
            max: _duration.inSeconds.toDouble() + 1,
            onChanged: (value) {
              setState(() => _position = Duration(seconds: value.toInt()));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
