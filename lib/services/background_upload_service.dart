import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'media_upload_service.dart';
import 'chat_service.dart';
import 'cloudflare_r2_service.dart';
import 'local_cache_service.dart';
import 'group_messaging_service.dart';
import 'community_service.dart';
import '../models/group_chat_message.dart';
import '../models/media_metadata.dart';
import '../config/cloudflare_config.dart';

class PendingUpload {
  final String id;
  final String filePath;
  final String conversationId;
  final String senderId;
  final String senderRole;
  final String chatType; // direct | group | community
  final String? senderName; // needed for group/community
  final String mediaType;
  final String fileName;
  final String mimeType;
  UploadStatus status;
  double progress;
  String? r2Url;
  String? error;

  PendingUpload({
    required this.id,
    required this.filePath,
    required this.conversationId,
    required this.senderId,
    required this.senderRole,
    required this.chatType,
    this.senderName,
    required this.mediaType,
    required this.fileName,
    required this.mimeType,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'conversationId': conversationId,
    'senderId': senderId,
    'senderRole': senderRole,
    'chatType': chatType,
    'senderName': senderName,
    'mediaType': mediaType,
    'fileName': fileName,
    'mimeType': mimeType,
    'status': status.toString(),
    'progress': progress,
    'r2Url': r2Url,
    'error': error,
  };

  static PendingUpload fromJson(Map<String, dynamic> json) =>
      PendingUpload(
          id: json['id'],
          filePath: json['filePath'],
          conversationId: json['conversationId'],
          senderId: json['senderId'],
          senderRole: json['senderRole'],
          chatType: json['chatType'] ?? 'direct',
          senderName: json['senderName'],
          mediaType: json['mediaType'],
          fileName: json['fileName'],
          mimeType: json['mimeType'],
          status: UploadStatus.values.firstWhere(
            (s) => s.toString() == json['status'],
            orElse: () => UploadStatus.pending,
          ),
          progress: (json['progress'] as num).toDouble(),
        )
        ..r2Url = json['r2Url']
        ..error = json['error'];
}

enum UploadStatus { pending, uploading, completed, failed, cancelled }

class BackgroundUploadService extends ChangeNotifier {
  static final BackgroundUploadService _instance = BackgroundUploadService._();

  factory BackgroundUploadService() => _instance;

  BackgroundUploadService._();

  late final MediaUploadService _mediaUploadService;
  final ChatService _chatService = ChatService();
  final GroupMessagingService _groupService = GroupMessagingService();
  final CommunityService _communityService = CommunityService();
  final List<PendingUpload> _uploads = [];
  Timer? _processingTimer;
  bool _isProcessing = false;
  bool _initialized = false;

  // Callback for UI to track uploading messages
  Function(String messageId, bool isUploading, double progress)?
  onUploadProgress;

  List<PendingUpload> get uploads => _uploads;

  Future<void> initialize() async {
    if (_initialized) return;

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

    _initialized = true;

    // Start processing queue
    _startProcessing();
  }

  void _startProcessing() {
    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isProcessing) {
        _processQueue();
      }
    });
  }

  Future<String> queueUpload({
    required File file,
    required String conversationId,
    required String senderId,
    required String senderRole,
    required String mediaType,
    String chatType = 'direct', // 'direct' | 'group' | 'community'
    String? senderName,
    String?
    messageId, // Optional: use client-generated pending messageId for progress mapping
  }) async {
    // Ensure service is initialized
    if (!_initialized) {
      await initialize();
    }

    // Use provided messageId so UI can map progress to the same pending message
    final uploadId =
        messageId ?? DateTime.now().millisecondsSinceEpoch.toString();

    final upload = PendingUpload(
      id: uploadId,
      filePath: file.path,
      conversationId: conversationId,
      senderId: senderId,
      senderRole: senderRole,
      chatType: chatType,
      senderName: senderName,
      mediaType: mediaType,
      fileName: file.path.split('/').last,
      mimeType: _getMimeType(file.path),
    );

    _uploads.add(upload);
    notifyListeners();

    // Start processing immediately if not already processing
    _processQueue();

    return uploadId;
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      final pendingUploads = _uploads
          .where((u) => u.status == UploadStatus.pending)
          .toList();

      for (final upload in pendingUploads) {
        if (!File(upload.filePath).existsSync()) {
          upload.status = UploadStatus.failed;
          upload.error = 'File not found: ${upload.filePath}';
          notifyListeners();
          continue;
        }

        try {
          upload.status = UploadStatus.uploading;
          notifyListeners();
          onUploadProgress?.call(upload.id, true, 0.0);

          final file = File(upload.filePath);

          // Upload the media
          final mediaMessage = await _mediaUploadService.uploadMedia(
            file: file,
            conversationId: upload.conversationId,
            senderId: upload.senderId,
            senderRole: upload.senderRole,
            mediaType: upload.mediaType,
            onProgress: (p) {
              // p is 0-100 (int). Normalize to 0.0-1.0
              final normalized = p.toDouble() > 1
                  ? p.toDouble() / 100.0
                  : p.toDouble();
              upload.progress = normalized;
              notifyListeners();
              onUploadProgress?.call(upload.id, true, normalized);
            },
          );

          upload.r2Url = mediaMessage.r2Url;
          upload.status = UploadStatus.completed;
          upload.progress = 1.0;
          onUploadProgress?.call(upload.id, false, 1.0);

          // Build media metadata from upload result
          final r2Key = _extractR2Key(mediaMessage.r2Url);

          // Store thumbnail URL directly (MediaPreviewCard now handles both base64 and URLs)
          final thumbnailStr = mediaMessage.thumbnailUrl ?? '';

          final metadata = MediaMetadata(
            messageId: mediaMessage.id,
            r2Key: r2Key,
            publicUrl: mediaMessage.r2Url,
            thumbnail: thumbnailStr, // This is a URL string, not base64
            expiresAt: DateTime.now().add(const Duration(days: 365)),
            uploadedAt: DateTime.now(),
            fileSize: mediaMessage.fileSize,
            mimeType: mediaMessage.fileType,
            originalFileName: mediaMessage.fileName,
          );

          // Route to the correct messaging service based on chatType
          if (upload.chatType == 'group' || upload.senderRole == 'group') {
            // conversationId expected as "{classId}_{subjectId}"
            final parts = upload.conversationId.split('_');
            if (parts.length >= 2) {
              final classId = parts.first;
              final subjectId = parts.sublist(1).join('_');
              final message = GroupChatMessage(
                id: '',
                senderId: upload.senderId,
                senderName: upload.senderName ?? 'Teacher',
                message: '',
                imageUrl: null,
                mediaMetadata: metadata,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              );
              await _groupService.sendGroupMessage(classId, subjectId, message);
            } else {
              debugPrint(
                '⚠️ Invalid group conversationId: ${upload.conversationId}',
              );
            }
          } else if (upload.chatType == 'community') {
            // conversationId is communityId here
            String inferredType = 'file';
            final mt = (metadata.mimeType ?? '').toLowerCase();
            if (mt.startsWith('image/')) inferredType = 'image';
            if (mt.startsWith('audio/')) inferredType = 'audio';
            if (mt.contains('pdf')) inferredType = 'pdf';
            await _communityService.sendMessage(
              communityId: upload.conversationId,
              senderId: upload.senderId,
              senderName: upload.senderName ?? 'Teacher',
              senderRole: 'Teacher',
              content: '',
              mediaType: inferredType,
              mediaMetadata: metadata,
            );
          } else {
            // Default: direct teacher-parent conversation
            await _chatService.sendMessage(
              conversationId: upload.conversationId,
              senderRole: upload.senderRole,
              text: 'Sent a file: ${upload.fileName}',
              mediaMetadata: metadata.toFirestore(),
            );
          }

          debugPrint('✅ Upload completed: ${upload.fileName}');
        } catch (e) {
          upload.status = UploadStatus.failed;
          upload.error = e.toString();
          debugPrint('❌ Upload failed for ${upload.fileName}: $e');
        }

        notifyListeners();
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> retryUpload(String uploadId) async {
    final upload = _uploads.firstWhere(
      (u) => u.id == uploadId,
      orElse: () => throw Exception('Upload not found'),
    );

    if (upload.status == UploadStatus.failed) {
      upload.status = UploadStatus.pending;
      upload.error = null;
      notifyListeners();
      await _processQueue();
    }
  }

  Future<void> cancelUpload(String uploadId) async {
    final upload = _uploads.firstWhere(
      (u) => u.id == uploadId,
      orElse: () => throw Exception('Upload not found'),
    );

    upload.status = UploadStatus.cancelled;
    notifyListeners();
  }

  void removeUpload(String uploadId) {
    _uploads.removeWhere((u) => u.id == uploadId);
    notifyListeners();
  }

  PendingUpload? getUpload(String uploadId) {
    try {
      return _uploads.firstWhere((u) => u.id == uploadId);
    } catch (e) {
      return null;
    }
  }

  String _getMimeType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    const mimeTypes = {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'wav': 'audio/wav',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    return mimeTypes[extension] ?? 'application/octet-stream';
  }

  String _extractR2Key(String r2Url) {
    final uri = Uri.parse(r2Url);
    // Path segments include 'media', 'timestamp', 'filename'
    // Join all without skipping to get: media/timestamp/filename
    return uri.pathSegments.join('/');
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    super.dispose();
  }
}
