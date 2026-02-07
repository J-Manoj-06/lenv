import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import '../../utils/link_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import '../../models/community_model.dart';
import '../../models/community_message_model.dart';
import '../../providers/auth_provider.dart';
import '../create_poll_screen.dart';
import '../../widgets/poll_message_widget.dart';
import '../../models/poll_model.dart';
import '../../services/community_service.dart';
import '../common/announcement_pageview_screen.dart';
import '../../services/media_upload_service.dart';
import '../../services/media_repository.dart';
import '../../services/background_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../../models/media_metadata.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/multi_image_message_bubble.dart';
import '../../core/constants/app_colors.dart';

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
  final MediaRepository _mediaRepository = MediaRepository();
  late final WhatsAppMediaUploadService _whatsappMediaUpload;
  final ValueNotifier<String> _messageText = ValueNotifier<String>('');
  String? _teacherName;
  String? _teacherId;
  bool _showEmojiPicker = false;
  bool _isUploading = false;

  // Multi-select functionality
  bool _selectionMode = false;
  final ValueNotifier<Set<String>> _selectedMessages =
      ValueNotifier<Set<String>>({});

  // Optimistic pending messages and per-upload progress
  final List<CommunityMessageModel> _pendingMessages = [];
  final Map<String, double> _pendingUploadProgress = {};
  final Map<String, String> _localSenderMediaPaths = {};

  // Tracking for message location and highlight
  final Map<String, GlobalKey> _messageKeys = {};
  Set<String> _visibleMessageIds = {};
  String? _highlightMessageId;
  Timer? _highlightResetTimer;

  // Audio recording
  bool _isRecording = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  late Timer _recordingTimer;
  double _slideOffsetX = 0;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
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

    // Bridge background upload progress to UI (optimistic pending messages)
    BackgroundUploadService()
        .onUploadProgress = (String messageId, bool isUploading, double progress) {
      if (!mounted) return;
      setState(() {
        if (isUploading) {
          _pendingUploadProgress[messageId] = progress;
        } else {
          // Upload complete - remove from progress tracking
          _pendingUploadProgress.remove(messageId);

          // For multi-image messages: remove completed image from pending immediately
          _removeCompletedImageFromPending(messageId);
        }
      });
    };

    // Sync existing upload progress when screen initializes
    _syncUploadProgress();

    _loadTeacherData();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(force: true),
    );

    // Load persisted pending messages on init
    _loadPendingMessages();
  }

  // Sync upload progress from BackgroundUploadService
  void _syncUploadProgress() {
    final uploadService = BackgroundUploadService();
    final uploads = uploadService.uploads;

    if (uploads.isEmpty) return;

    setState(() {
      for (final item in uploads) {
        // Only sync progress for items in this community
        if (_pendingUploadProgress.containsKey(item.id)) {
          _pendingUploadProgress[item.id] = item.progress;
        }
      }
    });
  }

  Future<void> _loadPendingMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'pending_messages_teacher_${widget.community.id}';
      final data = prefs.getStringList(key) ?? [];

      if (data.isEmpty) return;

      if (_teacherId == null || _teacherName == null) {
        await _loadTeacherData();
      }
      if (_teacherId == null || _teacherName == null) return;

      debugPrint('📂 Loading ${data.length} pending messages from cache');

      for (final json in data) {
        try {
          final map = jsonDecode(json) as Map<String, dynamic>;
          final mid = map['messageId'] as String?;
          if (mid == null || !mid.startsWith('pending:')) continue;

          // Reconstruct multipleMedia if present
          List<MediaMetadata>? multipleMedia;
          if (map['multipleMedia'] is List) {
            multipleMedia = (map['multipleMedia'] as List)
                .map((m) => _mediaFromJsonSafe(m))
                .toList();
          }

          final msg = CommunityMessageModel(
            messageId: mid,
            communityId: widget.community.id,
            senderId: _teacherId!,
            senderName: map['senderName'] as String? ?? _teacherName!,
            senderRole: 'Teacher',
            senderAvatar: '',
            type: 'image',
            content: map['content'] as String? ?? '',
            imageUrl: '',
            fileUrl: '',
            fileName: '',
            mediaMetadata: map['mediaMetadata'] != null
                ? _mediaFromJsonSafe(map['mediaMetadata'])
                : null,
            multipleMedia: multipleMedia,
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
            documentSnapshot: null,
          );

          setState(() {
            _pendingMessages.add(msg);
            // Track progress only if not already tracked
            if (msg.multipleMedia != null) {
              for (final mm in msg.multipleMedia!) {
                if (!_pendingUploadProgress.containsKey(mm.messageId)) {
                  _pendingUploadProgress[mm.messageId] = 0.0;
                }
              }
            }
            if (msg.mediaMetadata != null) {
              if (!_pendingUploadProgress.containsKey(
                msg.mediaMetadata!.messageId,
              )) {
                _pendingUploadProgress[msg.mediaMetadata!.messageId] = 0.0;
              }
            }
          });

          debugPrint('📥 Restored: $mid');
        } catch (e) {
          debugPrint('⚠️ Failed to restore pending message: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load pending messages: $e');
    }
  }

  Future<void> _cachePendingMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'pending_messages_teacher_${widget.community.id}';

      if (_pendingMessages.isEmpty) {
        await prefs.remove(key);
        debugPrint('🗑️ Cleared cache (no pending messages)');
        return;
      }

      final data = _pendingMessages
          .where((m) => m.messageId.startsWith('pending:'))
          .map(
            (m) => jsonEncode({
              'messageId': m.messageId,
              'senderName': m.senderName,
              'content': m.content,
              'mediaMetadata': m.mediaMetadata != null
                  ? _mediaToJsonSafe(m.mediaMetadata!)
                  : null,
              'multipleMedia': m.multipleMedia
                  ?.map((mm) => _mediaToJsonSafe(mm))
                  .toList(),
            }),
          )
          .toList();

      await prefs.setStringList(key, data);
      debugPrint('💾 Cached ${data.length} pending messages');
    } catch (e) {
      debugPrint('⚠️ Failed to cache pending messages: $e');
    }
  }

  Map<String, dynamic> _mediaToJsonSafe(MediaMetadata media) {
    return {
      'messageId': media.messageId,
      'r2Key': media.r2Key,
      'publicUrl': media.publicUrl,
      'localPath': media.localPath,
      'thumbnail': media.thumbnail,
      'deletedLocally': media.deletedLocally,
      'serverStatus': media.serverStatus.toString(),
      'expiresAt': media.expiresAt.millisecondsSinceEpoch,
      'uploadedAt': media.uploadedAt.millisecondsSinceEpoch,
      'fileSize': media.fileSize,
      'mimeType': media.mimeType,
      'originalFileName': media.originalFileName,
    };
  }

  MediaMetadata _mediaFromJsonSafe(Map<String, dynamic> json) {
    return MediaMetadata(
      messageId: json['messageId'] as String,
      r2Key: json['r2Key'] as String,
      publicUrl: json['publicUrl'] as String? ?? '',
      localPath: json['localPath'] as String?,
      thumbnail: json['thumbnail'] as String? ?? '',
      deletedLocally: json['deletedLocally'] as bool? ?? false,
      serverStatus: ServerStatus.values.firstWhere(
        (e) => e.toString() == json['serverStatus'],
        orElse: () => ServerStatus.available,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
      uploadedAt: DateTime.fromMillisecondsSinceEpoch(
        json['uploadedAt'] as int,
      ),
      fileSize: json['fileSize'] as int?,
      mimeType: json['mimeType'] as String?,
      originalFileName: json['originalFileName'] as String?,
    );
  }

  void _removeCompletedImageFromPending(String completedMessageId) {
    // Find pending message containing this media ID
    for (int i = 0; i < _pendingMessages.length; i++) {
      final pending = _pendingMessages[i];

      // Check if this pending has multiple media
      if (pending.multipleMedia != null && pending.multipleMedia!.length > 1) {
        // Check if completed image is in this pending
        final hasCompleted = pending.multipleMedia!.any(
          (m) => m.messageId == completedMessageId,
        );

        if (hasCompleted) {
          // Remove the completed image
          final remainingMedia = pending.multipleMedia!
              .where((m) => m.messageId != completedMessageId)
              .toList();

          debugPrint(
            '🗑️ Removed completed image from pending: $completedMessageId (${remainingMedia.length} remaining)',
          );

          if (remainingMedia.isEmpty) {
            // All images uploaded - remove entire pending
            _pendingMessages.removeAt(i);
            debugPrint(
              '✅ All images uploaded - removed pending: ${pending.messageId}',
            );
          } else {
            // Update pending with remaining images
            _pendingMessages[i] = CommunityMessageModel(
              messageId: pending.messageId,
              communityId: pending.communityId,
              senderId: pending.senderId,
              senderName: pending.senderName,
              senderRole: pending.senderRole,
              senderAvatar: pending.senderAvatar,
              type: pending.type,
              content: pending.content,
              imageUrl: pending.imageUrl,
              fileUrl: pending.fileUrl,
              fileName: pending.fileName,
              mediaMetadata: remainingMedia.first,
              multipleMedia: remainingMedia.length > 1 ? remainingMedia : null,
              createdAt: pending.createdAt,
              updatedAt: pending.updatedAt,
              isEdited: pending.isEdited,
              isDeleted: pending.isDeleted,
              isPinned: pending.isPinned,
              reactions: pending.reactions,
              replyTo: pending.replyTo,
              replyCount: pending.replyCount,
              isReported: pending.isReported,
              reportCount: pending.reportCount,
              deletedFor: pending.deletedFor,
              documentSnapshot: pending.documentSnapshot,
            );
          }

          // Update cache
          _cachePendingMessages();
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioRecorder.dispose();
    _messageText.dispose();
    _selectedMessages.dispose();
    _highlightResetTimer?.cancel();
    _recordingTimer.cancel();
    _recordingDuration.dispose();
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

  Future<void> _loadTeacherData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    final String fallbackEmailName = (currentUser.email ?? '')
        .split('@')
        .first
        .trim();

    // Get teacher data from Firestore
    final teacherDoc = await FirebaseFirestore.instance
        .collection('teachers')
        .where('email', isEqualTo: currentUser.email)
        .limit(1)
        .get();

    String? resolvedName;
    if (teacherDoc.docs.isNotEmpty) {
      final data = teacherDoc.docs.first.data();
      resolvedName =
          (data['name'] ??
                  data['teacherName'] ??
                  data['fullName'] ??
                  data['displayName'])
              ?.toString()
              .trim();
    }

    resolvedName = (resolvedName != null && resolvedName.isNotEmpty)
        ? resolvedName
        : (currentUser.name.trim().isNotEmpty == true
              ? currentUser.name.trim()
              : (fallbackEmailName.isNotEmpty ? fallbackEmailName : 'Teacher'));

    if (mounted) {
      setState(() {
        _teacherId = currentUser.uid;
        _teacherName = resolvedName;
      });
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

    if (_teacherId == null || _teacherName == null) return;

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
      senderId: _teacherId!,
      senderName: _teacherName!,
      senderRole: 'Teacher',
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
        senderId: _teacherId!,
        senderRole: 'Teacher',
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
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
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

  void _showMediaOptions() {
    showModernAttachmentSheet(
      context,
      onCameraTap: _pickAndSendCamera,
      onImageTap: _pickAndSendImages,
      onDocumentTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudio,
      onPollTap: _navigateToPollScreen,
      cameraEnabled: widget.community.allowImages,
      imageEnabled: widget.community.allowImages,
      color: AppColors.teacherColor,
    );
  }

  void _navigateToPollScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/create_poll'),
        builder: (context) => CreatePollScreen(
          chatId: widget.community.id,
          chatType: 'community',
        ),
      ),
    );
  }

  Future<void> _pickAndSendCamera() async {
    if (_teacherId == null || _teacherName == null) return;

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
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      final file = File(image.path);
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: widget.community.id,
        senderId: _teacherId!,
        senderRole: 'teacher',
        mediaType: 'message',
        chatType: 'community',
        senderName: _teacherName!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image queued for upload')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  Future<void> _pickAndSendImages() async {
    if (_teacherId == null || _teacherName == null) return;

    try {
      debugPrint('🖼️ Starting image picker (multi)...');
      List<XFile> images = [];
      try {
        images = await _imagePicker.pickMultiImage(
          limit: 5,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        debugPrint('📸 Picked ${images.length} images via pickMultiImage');
      } catch (e) {
        debugPrint('⚠️ pickMultiImage failed: $e');
      }

      if (images.isEmpty) {
        debugPrint('↪️ Fallback to single pickImage');
        final XFile? single = await _imagePicker.pickImage(
          source: ImageSource.gallery,
        );
        if (single != null) {
          images = [single];
          debugPrint('📸 Picked 1 image via pickImage');
        }
      }

      if (images.isEmpty) {
        debugPrint('⚠️ No images selected');
        return;
      }

      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final groupMessageId = 'upload_${baseTimestamp}_${_teacherId.hashCode}';
      final List<MediaMetadata> mediaList = [];
      final List<String> localPaths = [];

      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        final file = File(image.path);
        if (!file.existsSync()) {
          debugPrint('⚠️ File does not exist: ${image.path}');
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No valid images found')));
        return;
      }

      final pendingMessage = CommunityMessageModel(
        messageId: 'pending:$groupMessageId',
        communityId: widget.community.id,
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
        senderAvatar: '',
        type: 'image',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: '',
        mediaMetadata: mediaList.first,
        multipleMedia: mediaList.length > 1 ? mediaList : null,
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
        documentSnapshot: null,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        for (int i = 0; i < mediaList.length; i++) {
          final mid = mediaList[i].messageId;
          _pendingUploadProgress[mid] = 0.0;
          _localSenderMediaPaths[mid] = localPaths[i];
        }
      });

      // Persist pending state immediately so uploads survive screen dismissal
      await _cachePendingMessages();

      // Queue uploads in background (worker will create server messages)
      for (int i = 0; i < images.length; i++) {
        final file = File(images[i].path);
        if (!file.existsSync()) continue;
        final messageId = '${groupMessageId}_$i';

        await BackgroundUploadService().queueUpload(
          file: file,
          conversationId: widget.community.id,
          senderId: _teacherId!,
          senderRole: 'teacher',
          mediaType: 'message',
          chatType: 'community',
          senderName: _teacherName,
          messageId: messageId,
          groupId: groupMessageId,
        );
      }

      _scrollToBottom(force: true);
    } catch (e) {
      debugPrint('❌ Error in _pickAndSendImages: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send images: $e')));
    }
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
      if (!file.existsSync()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image file not found')));
        return;
      }

      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${_teacherId.hashCode}';

      // Create optimistic pending message
      final pendingMeta = MediaMetadata(
        messageId: messageId,
        r2Key: 'pending/$messageId',
        publicUrl: '',
        localPath: file.path,
        thumbnail: file.path, // show immediate local preview
        deletedLocally: false,
        serverStatus: ServerStatus.available,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await file.length(),
        mimeType: 'image/jpeg',
        originalFileName: file.path.split('/').last,
      );

      final pending = CommunityMessageModel(
        messageId: 'pending:$messageId',
        communityId: widget.community.id,
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
        senderAvatar: '',
        type: 'image',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: pendingMeta.originalFileName ?? 'image.jpg',
        mediaMetadata: pendingMeta,
        createdAt: DateTime.now(),
        updatedAt: null,
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: const {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
        deletedFor: const [],
      );

      if (mounted) {
        setState(() {
          _pendingMessages.insert(0, pending);
          _pendingUploadProgress[messageId] = 0.0;
        });
      }

      // Queue upload with background service
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: widget.community.id,
        senderId: _teacherId!,
        senderRole: 'teacher',
        mediaType: 'message',
        chatType: 'community',
        senderName: _teacherName,
        messageId: messageId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to queue image: $e'),
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
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
          'rtf',
          'odt',
          'ods',
          'odp',
        ],
        withReadStream: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final platformFile = result.files.single;
      // Ensure we have a readable local File even if path is null
      final file = await _ensureLocalPickedFile(platformFile);
      final fileName = platformFile.name;

      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${_teacherId.hashCode}';

      // Create optimistic pending
      final pendingMeta = MediaMetadata(
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

      final pending = CommunityMessageModel(
        messageId: 'pending:$messageId',
        communityId: widget.community.id,
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
        senderAvatar: '',
        type: 'pdf',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMeta,
        createdAt: DateTime.now(),
        updatedAt: null,
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: const {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
        deletedFor: const [],
      );

      if (mounted) {
        setState(() {
          _pendingMessages.insert(0, pending);
          _pendingUploadProgress[messageId] = 0.0;
        });
      }

      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: widget.community.id,
        senderId: _teacherId!,
        senderRole: 'teacher',
        mediaType: 'message',
        chatType: 'community',
        senderName: _teacherName,
        messageId: messageId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to queue PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendAudio() async {
    if (_teacherId == null || _teacherName == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
        withReadStream: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final platformFile = result.files.single;
      final file = await _ensureLocalPickedFile(platformFile);
      final fileName = platformFile.name;

      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${_teacherId.hashCode}';

      final pendingMeta = MediaMetadata(
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

      final pending = CommunityMessageModel(
        messageId: 'pending:$messageId',
        communityId: widget.community.id,
        senderId: _teacherId!,
        senderName: _teacherName!,
        senderRole: 'Teacher',
        senderAvatar: '',
        type: 'audio',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMeta,
        createdAt: DateTime.now(),
        updatedAt: null,
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: const {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
        deletedFor: const [],
      );

      if (mounted) {
        setState(() {
          _pendingMessages.insert(0, pending);
          _pendingUploadProgress[messageId] = 0.0;
        });
      }

      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: widget.community.id,
        senderId: _teacherId!,
        senderRole: 'teacher',
        mediaType: 'message',
        chatType: 'community',
        senderName: _teacherName,
        messageId: messageId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to queue audio: $e'),
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
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'audio/mpeg';
    }
  }

  Future<File> _ensureLocalPickedFile(PlatformFile platformFile) async {
    if (platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) return f;
    }
    if (platformFile.readStream == null) {
      throw Exception('Selected file is not accessible');
    }
    final tmpDir = await Directory.systemTemp.createTemp('lenv_attach_');
    final dest = File('${tmpDir.path}/${platformFile.name}');
    final sink = dest.openWrite();
    await platformFile.readStream!.pipe(sink);
    await sink.close();
    return dest;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;
    if (_teacherId == null || _teacherName == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: StreamBuilder<List<CommunityMessageModel>>(
                  stream: _communityService.getMessagesStream(
                    widget.community.id,
                  ),
                  builder: (context, snapshot) {
                    // Render pending optimistic messages immediately; avoid blocking on stream connect.

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading messages',
                          style: TextStyle(color: Colors.red[300]),
                        ),
                      );
                    }

                    // Merge server messages with optimistic pending ones
                    final messagesFromServer = List<CommunityMessageModel>.from(
                      snapshot.data ?? <CommunityMessageModel>[],
                    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    // Build set of seen media IDs from server messages
                    final seenMediaIds = <String>{};
                    for (final m in messagesFromServer) {
                      if (m.multipleMedia != null) {
                        seenMediaIds.addAll(
                          m.multipleMedia!.map((mm) => mm.messageId),
                        );
                      }
                      final singleId = m.mediaMetadata?.messageId;
                      if (singleId != null) seenMediaIds.add(singleId);
                    }

                    final combined = <CommunityMessageModel>[];
                    combined.addAll(messagesFromServer);

                    final confirmedPendingIds = <String>[];
                    final pendingsToUpdate = <String, List<MediaMetadata>>{};

                    for (final pending in _pendingMessages) {
                      final pendingIds = <String>{};
                      if (pending.multipleMedia != null) {
                        pendingIds.addAll(
                          pending.multipleMedia!.map((mm) => mm.messageId),
                        );
                      }
                      final singleId = pending.mediaMetadata?.messageId;
                      if (singleId != null) pendingIds.add(singleId);

                      // Check for partial completion (multi-image messages)
                      if (pending.multipleMedia != null &&
                          pending.multipleMedia!.length > 1) {
                        // Filter out completed media items
                        final remainingMedia = pending.multipleMedia!
                            .where((mm) => !seenMediaIds.contains(mm.messageId))
                            .toList();

                        if (remainingMedia.isEmpty) {
                          // All media uploaded - remove entire pending
                          confirmedPendingIds.add(pending.messageId);
                          debugPrint(
                            '✅ All media confirmed: ${pending.messageId}',
                          );
                        } else if (remainingMedia.length <
                            pending.multipleMedia!.length) {
                          // Partial completion - update the pending
                          pendingsToUpdate[pending.messageId] = remainingMedia;
                          combined.add(pending);
                          debugPrint(
                            '⏳ Partial upload: ${remainingMedia.length}/${pending.multipleMedia!.length} remaining',
                          );
                        } else {
                          // No uploads completed yet
                          combined.add(pending);
                        }
                      } else {
                        // Single image or no media - old logic
                        final shouldAdd =
                            pendingIds.isEmpty ||
                            !pendingIds.any(seenMediaIds.contains);
                        if (shouldAdd) {
                          combined.add(pending);
                        } else {
                          confirmedPendingIds.add(pending.messageId);
                          debugPrint(
                            '✅ Pending confirmed: ${pending.messageId}',
                          );
                        }
                      }
                    }

                    // Update pendings and remove confirmed ones in post-frame callback
                    if (confirmedPendingIds.isNotEmpty ||
                        pendingsToUpdate.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          // Remove fully completed pendings
                          _pendingMessages.removeWhere(
                            (m) => confirmedPendingIds.contains(m.messageId),
                          );

                          // Update partially completed pendings
                          for (final entry in pendingsToUpdate.entries) {
                            final idx = _pendingMessages.indexWhere(
                              (m) => m.messageId == entry.key,
                            );
                            if (idx != -1) {
                              final old = _pendingMessages[idx];
                              _pendingMessages[idx] = CommunityMessageModel(
                                messageId: old.messageId,
                                communityId: old.communityId,
                                senderId: old.senderId,
                                senderName: old.senderName,
                                senderRole: old.senderRole,
                                senderAvatar: old.senderAvatar,
                                type: old.type,
                                content: old.content,
                                imageUrl: old.imageUrl,
                                fileUrl: old.fileUrl,
                                fileName: old.fileName,
                                mediaMetadata: old.mediaMetadata,
                                multipleMedia: entry.value, // Updated list
                                createdAt: old.createdAt,
                                updatedAt: old.updatedAt,
                                isEdited: old.isEdited,
                                isDeleted: old.isDeleted,
                                isPinned: old.isPinned,
                                reactions: old.reactions,
                                replyTo: old.replyTo,
                                replyCount: old.replyCount,
                                isReported: old.isReported,
                                reportCount: old.reportCount,
                                deletedFor: old.deletedFor,
                                documentSnapshot: old.documentSnapshot,
                              );
                            }
                          }
                        });
                        _cachePendingMessages();
                      });
                    }

                    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    if (combined.isEmpty) {
                      // Show loader only if still connecting and nothing to render.
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF6A4FF7),
                          ),
                        );
                      }

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

                        if (message.isDeleted) {
                          return const SizedBox.shrink();
                        }

                        final isCurrentUser = message.senderId == _teacherId;
                        final isPending =
                            message.messageId.startsWith('pending:') ||
                            (message.mediaMetadata?.r2Key.startsWith(
                                  'pending/',
                                ) ??
                                false);
                        final metaId =
                            message.mediaMetadata?.messageId ??
                            message.messageId;
                        final uploadProgress = isPending
                            ? _pendingUploadProgress[metaId]
                            : null;

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
                                _teacherName!,
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
          if (_isRecording) _buildRecordingOverlay(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: theme.brightness == Brightness.dark
          ? Colors.black
          : theme.scaffoldBackgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          _selectionMode ? Icons.close : Icons.arrow_back_ios_new,
          color: theme.iconTheme.color,
          size: 20,
        ),
        onPressed: () {
          if (_selectionMode) {
            setState(() => _selectionMode = false);
            _selectedMessages.value = {};
          } else {
            Navigator.pop(context);
          }
        },
      ),
      title: _selectionMode
          ? ValueListenableBuilder<Set<String>>(
              valueListenable: _selectedMessages,
              builder: (context, selectedSet, _) {
                return Text(
                  '${selectedSet.length} selected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
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
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.community.memberCount} members',
                        style: TextStyle(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.6,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      actions: [
        if (_selectionMode)
          ValueListenableBuilder<Set<String>>(
            valueListenable: _selectedMessages,
            builder: (context, selectedSet, _) {
              return IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: selectedSet.isEmpty
                    ? null
                    : () => _deleteSelectedMessages(),
              );
            },
          )
        else ...[
          IconButton(
            icon: Icon(Icons.search, color: theme.iconTheme.color),
            onPressed: _openSearch,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
            onSelected: (value) {
              if (value == 'leave') {
                _showLeaveCommunityDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'Leave Community',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF262A30) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
            border: isDark
                ? null
                : Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Text(
            _formatDate(date),
            style: TextStyle(
              color: isDark ? const Color(0xFF9E9E9E) : Colors.grey.shade700,
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
    bool isUploading,
    double? uploadProgress,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder<Set<String>>(
      valueListenable: _selectedMessages,
      builder: (context, selectedSet, _) {
        final isSelected = selectedSet.contains(message.messageId);

        return GestureDetector(
          onLongPress: isCurrentUser
              ? () {
                  if (!_selectionMode) {
                    setState(() => _selectionMode = true);
                    _selectedMessages.value = {message.messageId};
                  }
                }
              : null,
          onTap: _selectionMode && isCurrentUser
              ? () {
                  if (isSelected) {
                    final updated = {...selectedSet};
                    updated.remove(message.messageId);
                    _selectedMessages.value = updated;
                  } else {
                    _selectedMessages.value = {
                      ...selectedSet,
                      message.messageId,
                    };
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: isCurrentUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: isCurrentUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 4,
                          left: 4,
                          right: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: isCurrentUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            Text(
                              isCurrentUser
                                  ? currentUserName
                                  : message.senderName,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!isCurrentUser) ...[
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
                          ],
                        ),
                      ),
                      // Check if this is a poll message - render it outside the bubble
                      if (message.type == 'poll')
                        SizedBox(
                          width: double.infinity,
                          child: Align(
                            alignment: isCurrentUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: PollMessageWidget(
                              poll: PollModel.fromMap(
                                message.toMap(),
                                message.messageId,
                              ),
                              chatId: widget.community.id,
                              chatType: 'community',
                              isOwnMessage: isCurrentUser,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal:
                                message.multipleMedia != null &&
                                    message.multipleMedia!.isNotEmpty
                                ? 0
                                : 5,
                            vertical:
                                message.multipleMedia != null &&
                                    message.multipleMedia!.isNotEmpty
                                ? 0
                                : 5,
                          ),
                          decoration: BoxDecoration(
                            color:
                                message.multipleMedia != null &&
                                    message.multipleMedia!.isNotEmpty
                                ? Colors.transparent
                                : (isCurrentUser
                                      ? (isDark
                                            ? const Color(0xFF1A1C20)
                                            : theme
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withOpacity(0.6))
                                      : (isDark
                                            ? const Color(0xFF14171B)
                                            : theme.cardColor)),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(
                                isCurrentUser ? 12 : 6,
                              ),
                              bottomRight: Radius.circular(
                                isCurrentUser ? 6 : 12,
                              ),
                            ),
                            border:
                                message.multipleMedia != null &&
                                    message.multipleMedia!.isNotEmpty
                                ? null
                                : Border.all(
                                    color: theme.dividerColor.withOpacity(0.4),
                                    width: 0.1,
                                  ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Multi-image bubble (new WhatsApp-style)
                              if (message.multipleMedia != null &&
                                  message.multipleMedia!.isNotEmpty) ...[
                                IgnorePointer(
                                  ignoring: _selectionMode,
                                  child: Opacity(
                                    opacity: _selectionMode ? 0.6 : 1.0,
                                    child: MultiImageMessageBubble(
                                      imageUrls: message.multipleMedia!.map((
                                        m,
                                      ) {
                                        // Prefer local path for sender's own images
                                        final localPath =
                                            m.localPath ??
                                            _localSenderMediaPaths[m.messageId];
                                        if (localPath != null &&
                                            localPath.isNotEmpty &&
                                            File(localPath).existsSync()) {
                                          return localPath;
                                        }
                                        // Fallback to public URL
                                        return m.publicUrl.isNotEmpty
                                            ? m.publicUrl
                                            : m.thumbnail;
                                      }).toList(),
                                      isMe: isCurrentUser,
                                      uploadProgress: message.multipleMedia!
                                          .map(
                                            (m) =>
                                                _pendingUploadProgress[m
                                                    .messageId],
                                          )
                                          .toList(),
                                      onImageTap: (index) {
                                        if (_selectionMode) return;
                                        _showImageGalleryViewer(
                                          message.multipleMedia!,
                                          index,
                                          isCurrentUser,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                if (message.content.isNotEmpty)
                                  const SizedBox(height: 8),
                              ]
                              // Single media with metadata (images, PDFs, audio)
                              else if (message.mediaMetadata != null) ...[
                                IgnorePointer(
                                  ignoring: _selectionMode,
                                  child: Opacity(
                                    opacity: _selectionMode ? 0.6 : 1.0,
                                    child: MediaPreviewCard(
                                      r2Key: message.mediaMetadata!.r2Key,
                                      fileName: _getFileNameFromMetadata(
                                        message.mediaMetadata!,
                                      ),
                                      mimeType:
                                          message.mediaMetadata!.mimeType ??
                                          'application/octet-stream',
                                      fileSize:
                                          message.mediaMetadata!.fileSize ?? 0,
                                      thumbnailBase64:
                                          message.mediaMetadata!.thumbnail,
                                      localPath:
                                          message.mediaMetadata!.localPath,
                                      isMe: isCurrentUser,
                                      uploading: isUploading,
                                      uploadProgress: uploadProgress,
                                      selectionMode: _selectionMode,
                                    ),
                                  ),
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
                                    color: theme.textTheme.bodyLarge?.color,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                  linkStyle: TextStyle(
                                    color: const Color(0xFF6A4FF7),
                                    fontSize: 14,
                                    height: 1.5,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _formatTime(message.createdAt),
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.7),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectionMode && isCurrentUser)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 12),
                    child: GestureDetector(
                      onTap: () {
                        if (isSelected) {
                          final updated = {...selectedSet};
                          updated.remove(message.messageId);
                          _selectedMessages.value = updated;
                        } else {
                          _selectedMessages.value = {
                            ...selectedSet,
                            message.messageId,
                          };
                        }
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6A4FF7)
                                : Colors.grey[400]!,
                            width: isSelected ? 2 : 1.5,
                          ),
                          color: isSelected
                              ? const Color(0xFF6A4FF7)
                              : Colors.transparent,
                        ),
                        child: isSelected
                            ? const Center(
                                child: Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Premium dark theme palette - integrated with chat screen
    final backgroundColor = isDark
        ? const Color(0xFF0D0E10) // Near-black, blends with chat
        : const Color(0xFFF5F5F5);
    final inputFieldColor = isDark
        ? const Color(0xFF1E2024) // Slightly lighter for depth
        : Colors.white;
    final textColor = isDark
        ? const Color(0xFFE8E8E8) // Bright, readable
        : const Color(0xFF000000);
    final hintColor = isDark
        ? const Color(0xFF6B6B6B) // Subdued gray
        : const Color(0xFF999999);
    final iconColor = isDark
        ? const Color(0xFF9A95CC) // Soft muted violet
        : const Color(0xFF6C63FF);
    final iconDisabledColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFBBBBBB);
    final accentColor = const Color(
      0xFF7C3AED,
    ); // Cool violet - matches existing buttons

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isDark
            ? Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<String>(
          valueListenable: _messageText,
          builder: (context, text, _) {
            final hasText = text.trim().isNotEmpty;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Input container - pill-shaped with subtle depth
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: inputFieldColor,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: isDark
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Emoji toggle - inside input, left side
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showEmojiPicker = !_showEmojiPicker;
                              });
                              if (!_showEmojiPicker) {
                                _focusNode.requestFocus();
                              } else {
                                _focusNode.unfocus();
                              }
                            },
                            child: Icon(
                              _showEmojiPicker
                                  ? Icons.keyboard_outlined
                                  : Icons.emoji_emotions_outlined,
                              color: iconColor,
                              size: 23,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Text input - primary focus
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            focusNode: _focusNode,
                            cursorColor: accentColor,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(
                                color: hintColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendMessage(),
                            onChanged: (value) => _messageText.value = value,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Attachment - inside input, right side
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: _isUploading ? null : _showMediaOptions,
                            child: Icon(
                              Icons.attach_file_rounded,
                              color: _isUploading
                                  ? iconDisabledColor
                                  : iconColor,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Mic/Send button - balanced size, outside input
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isRecording
                              ? theme.colorScheme.error
                              : accentColor,
                          shape: BoxShape.circle,
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color:
                                        (_isRecording
                                                ? theme.colorScheme.error
                                                : accentColor)
                                            .withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color:
                                        (_isRecording
                                                ? theme.colorScheme.error
                                                : accentColor)
                                            .withOpacity(0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    if (!_isRecording) return const SizedBox();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: const Color(0xFF2A2A2A),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // Delete button
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
                          // Red pulse indicator
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Recording duration
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
                icon: const Icon(Icons.send, color: Color(0xFF00BFA5)),
                onPressed: _sendRecording,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _openSearch() {
    if (_teacherId == null) return;
    Navigator.of(context)
        .push<CommunityMessageModel?>(
          MaterialPageRoute(
            builder: (_) => MessageSearchScreen(
              communityId: widget.community.id,
              communityService: _communityService,
              currentUserId: _teacherId!,
            ),
          ),
        )
        .then((selected) {
          if (selected != null) {
            _locateMessage(selected);
          }
        });
  }

  void _showLeaveCommunityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave Community',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to leave this community? You can rejoin later from the explore page.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _leaveCommunity();
            },
            child: const Text(
              'Leave',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveCommunity() async {
    try {
      if (_teacherId == null) return;

      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leaving community...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Leave community
      final success = await _communityService.leaveCommunity(
        widget.community.id,
        _teacherId!,
      );

      if (success) {
        if (mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You have left the community'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );

          // Navigate back to communities list
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to leave community'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showImageGalleryViewer(
    List<MediaMetadata> mediaList,
    int initialIndex,
    bool isMe,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImageGalleryViewer(
          mediaList: mediaList,
          initialIndex: initialIndex,
          localSenderMediaPaths: _localSenderMediaPaths,
          isMe: isMe,
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

  void _showMessageOptions(CommunityMessageModel message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete for Everyone',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessageForEveryone(message);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessageForEveryone(CommunityMessageModel message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Delete Message?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This message will be deleted for everyone in this community.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.community.id)
          .collection('messages')
          .doc(message.messageId)
          .update({'isDeleted': true, 'content': ''});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted for everyone'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedMessages() async {
    final selectedSet = _selectedMessages.value;
    if (selectedSet.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'Delete Messages?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Delete ${selectedSet.length} selected message${selectedSet.length != 1 ? 's' : ''} for everyone in this community?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final communityRef = FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.community.id);

      for (final messageId in selectedSet) {
        batch.update(communityRef.collection('messages').doc(messageId), {
          'isDeleted': true,
          'content': '',
        });
      }

      await batch.commit();

      if (mounted) {
        setState(() {
          _selectionMode = false;
          _selectedMessages.value = {};
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selectedSet.length} message${selectedSet.length != 1 ? 's' : ''} deleted for everyone',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class MessageSearchScreen extends StatefulWidget {
  final String communityId;
  final CommunityService communityService;
  final String currentUserId;

  const MessageSearchScreen({
    super.key,
    required this.communityId,
    required this.communityService,
    required this.currentUserId,
  });

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
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
        // Just text - show in snackbar or toast
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message.content)));
      }
      return;
    }

    final meta = message.mediaMetadata!;
    final mime = meta.mimeType ?? '';
    final publicUrl = meta.publicUrl;

    // Image preview - show in dialog
    if (mime.startsWith('image/')) {
      _showImagePreview(publicUrl, meta);
      return;
    }

    // PDF - open with external apps immediately
    if (mime == 'application/pdf') {
      _openPDFWithExternalApp(
        publicUrl,
        meta.originalFileName ?? 'Document.pdf',
      );
      return;
    }

    // Audio player - show in bottom sheet
    if (mime.startsWith('audio/')) {
      _showAudioPlayer(publicUrl, meta);
      return;
    }

    // Generic file
    _handleFileDownload(publicUrl, meta.originalFileName ?? 'File');
  }

  void _handleFileDownload(String url, String fileName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $fileName...'),
        action: SnackBarAction(
          label: 'Copy URL',
          onPressed: () {
            // Copy URL to clipboard for manual download
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
      // Check if file exists in local cache
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
      // Fallback to network image
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
      // Check if file exists in local cache
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
      // Fallback to network audio
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
      // Show loading message
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

      // Download to temporary directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');

      // Ensure .pdf extension
      final finalFileName = cleanFileName.endsWith('.pdf')
          ? cleanFileName
          : '$cleanFileName.pdf';

      final filePath = '${tempDir.path}/${timestamp}_$finalFileName';

      // Download using Dio
      final dio = Dio();
      await dio.download(url, filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      // Open with OpenFilex - this triggers Android app chooser
      final result = await OpenFilex.open(filePath, type: 'application/pdf');

      // Check result
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

  Future<void> _showPDFOptions(String url, String fileName) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Open PDF', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadPDFToDevice(url, fileName);
            },
            child: const Text('Save to Device'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Download to temp and open with system app picker
              try {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Preparing PDF...'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }

                final tempDir = await getTemporaryDirectory();
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final filePath = '${tempDir.path}/${timestamp}_$fileName';

                final dio = Dio();
                await dio.download(url, filePath);

                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                }

                await OpenFilex.open(filePath, type: 'application/pdf');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPDFToDevice(String url, String fileName) async {
    try {
      // Show loading
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
                Text('Downloading PDF...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      // Get downloads directory
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('Cannot access storage');
      }

      // Save to Downloads folder
      final downloadsPath =
          '${externalDir.path.split('/Android').first}/Download';
      final downloadsDir = Directory(downloadsPath);

      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '');
      final filePath = '${downloadsDir.path}/LENV_${timestamp}_$cleanFileName';

      // Download using Dio
      final dio = Dio();
      await dio.download(url, filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved to Downloads folder'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
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
                        onTap: () => _openMedia(message),
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// Image Gallery Viewer with swipe navigation
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
