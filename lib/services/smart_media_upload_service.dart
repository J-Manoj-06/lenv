import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/cached_media_message.dart';
import '../services/media_cache_service.dart';

/// Smart Media Upload Service
/// STEP 6: Implements the correct flow for sending media
/// 1. Save media locally FIRST
/// 2. Upload to Cloudflare SECOND
/// 3. Save localPath in message object
/// 4. Mark isDownloaded = true
class SmartMediaUploadService {
  final MediaCacheService _cacheService = MediaCacheService();

  /// Upload media with smart local caching
  /// This ensures immediate local availability while uploading to cloud
  Future<MediaUploadResult> uploadMedia({
    required File file,
    required String messageId,
    required String fileName,
    required String fileType,
    required String uploadUrl, // Cloudflare or other cloud storage URL
    Function(double progress)? onProgress,
  }) async {
    try {
      // STEP 1: Read file bytes
      final fileBytes = await file.readAsBytes();
      final fileSize = fileBytes.length;

      // STEP 2: Determine media type
      final mediaType = MediaTypeExtension.fromMimeType(fileType);

      // STEP 3: Save locally FIRST (critical for instant access)
      debugPrint('Saving media locally first...');
      final localPath = await _cacheService.saveMediaFile(
        messageId: messageId,
        mediaType: mediaType,
        fileBytes: fileBytes,
        extension: _getExtensionFromFileName(fileName),
      );
      debugPrint('Media saved locally at: $localPath');

      // STEP 4: Upload to cloud storage in background
      debugPrint('Uploading to cloud...');
      final cloudUrl = await _uploadToCloud(
        fileBytes: fileBytes,
        fileName: fileName,
        uploadUrl: uploadUrl,
        onProgress: onProgress,
      );
      debugPrint('Media uploaded to cloud: $cloudUrl');

      // STEP 5: Return success with both local and cloud paths
      return MediaUploadResult(
        success: true,
        localPath: localPath,
        cloudUrl: cloudUrl,
        fileName: fileName,
        fileType: fileType,
        fileSize: fileSize,
        messageId: messageId,
        mediaType: mediaType,
      );
    } catch (e) {
      debugPrint('Error uploading media: $e');
      return MediaUploadResult(success: false, errorMessage: e.toString());
    }
  }

  /// Upload media that's already been picked (for sending in chat)
  /// Returns a CachedMediaMessage ready to be sent
  Future<CachedMediaMessage?> prepareMediaForSending({
    required File file,
    required String messageId,
    required String senderId,
    required String senderRole,
    required String conversationId,
    required String uploadUrl,
    Function(double progress)? onProgress,
  }) async {
    try {
      // Get file info
      final fileName = file.path.split('/').last;
      final fileType = _getMimeType(fileName);
      final fileBytes = await file.readAsBytes();
      final fileSize = fileBytes.length;

      // Determine media type
      final mediaType = MediaTypeExtension.fromMimeType(fileType);

      // CRITICAL: Save locally FIRST
      final localPath = await _cacheService.saveMediaFile(
        messageId: messageId,
        mediaType: mediaType,
        fileBytes: fileBytes,
        extension: _getExtensionFromFileName(fileName),
      );

      // Upload to cloud (this happens in background)
      String cloudUrl;
      try {
        cloudUrl = await _uploadToCloud(
          fileBytes: fileBytes,
          fileName: fileName,
          uploadUrl: uploadUrl,
          onProgress: onProgress,
        );
      } catch (e) {
        // If upload fails, still create message with local path
        // Upload can be retried later
        cloudUrl = ''; // Empty URL indicates upload pending
      }

      // Create message with local path already set
      final mediaCategory = _mapMediaTypeToCategory(mediaType);

      return CachedMediaMessage(
        messageId: messageId,
        senderId: senderId,
        senderRole: senderRole,
        conversationId: conversationId,
        fileName: fileName,
        fileType: fileType,
        fileSize: fileSize,
        cloudUrl: cloudUrl,
        localPath: localPath,
        isDownloaded: true, // Already downloaded (saved locally)
        mediaType: mediaCategory,
        createdAt: DateTime.now(),
        downloadedAt: DateTime.now(),
        isPending: cloudUrl.isEmpty, // Pending if cloud upload failed
        uploadFailed: cloudUrl.isEmpty,
      );
    } catch (e) {
      debugPrint('Error preparing media for sending: $e');
      return null;
    }
  }

  /// Upload file bytes to cloud storage
  Future<String> _uploadToCloud({
    required Uint8List fileBytes,
    required String fileName,
    required String uploadUrl,
    Function(double progress)? onProgress,
  }) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );

      // Send request
      final streamedResponse = await request.send();

      // Get response
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse response to get cloud URL
        // This depends on your cloud storage provider's response format
        // Example for Cloudflare R2:
        final cloudUrl = _parseCloudUrl(response.body, fileName);
        return cloudUrl;
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Cloud upload error: $e');
      rethrow;
    }
  }

  /// Parse cloud URL from response
  /// Adjust this based on your cloud storage provider
  String _parseCloudUrl(String responseBody, String fileName) {
    // Example implementation - adjust based on your API
    // For Cloudflare R2 or similar services
    try {
      // If response contains JSON with URL
      // final json = jsonDecode(responseBody);
      // return json['url'] ?? json['publicUrl'] ?? '';

      // For now, return a placeholder
      // You should implement this based on your actual cloud storage API
      return 'https://your-storage-url.com/$fileName';
    } catch (e) {
      return '';
    }
  }

  /// Get file extension from filename
  String? _getExtensionFromFileName(String fileName) {
    if (fileName.contains('.')) {
      return '.${fileName.split('.').last}';
    }
    return null;
  }

  /// Get MIME type from filename
  String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    // Images
    if (['jpg', 'jpeg'].contains(extension)) return 'image/jpeg';
    if (extension == 'png') return 'image/png';
    if (extension == 'gif') return 'image/gif';
    if (extension == 'webp') return 'image/webp';

    // Audio
    if (extension == 'mp3') return 'audio/mpeg';
    if (extension == 'wav') return 'audio/wav';
    if (extension == 'aac') return 'audio/aac';
    if (extension == 'm4a') return 'audio/mp4';

    // Documents
    if (extension == 'pdf') return 'application/pdf';
    if (extension == 'doc') return 'application/msword';
    if (extension == 'docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }

    return 'application/octet-stream';
  }

  MediaTypeCategory _mapMediaTypeToCategory(MediaType mediaType) {
    switch (mediaType) {
      case MediaType.image:
        return MediaTypeCategory.image;
      case MediaType.audio:
        return MediaTypeCategory.audio;
      case MediaType.pdf:
        return MediaTypeCategory.pdf;
      case MediaType.document:
        return MediaTypeCategory.document;
    }
  }

  /// Retry upload for failed media
  Future<String?> retryUpload({
    required String localPath,
    required String fileName,
    required String uploadUrl,
    Function(double progress)? onProgress,
  }) async {
    try {
      // Load from local path
      final file = File(localPath);
      if (!await file.exists()) {
        throw Exception('Local file not found');
      }

      final fileBytes = await file.readAsBytes();

      // Upload to cloud
      final cloudUrl = await _uploadToCloud(
        fileBytes: fileBytes,
        fileName: fileName,
        uploadUrl: uploadUrl,
        onProgress: onProgress,
      );

      return cloudUrl;
    } catch (e) {
      debugPrint('Retry upload error: $e');
      return null;
    }
  }
}

/// Result of media upload operation
class MediaUploadResult {
  final bool success;
  final String? localPath;
  final String? cloudUrl;
  final String? fileName;
  final String? fileType;
  final int? fileSize;
  final String? messageId;
  final MediaType? mediaType;
  final String? errorMessage;

  MediaUploadResult({
    required this.success,
    this.localPath,
    this.cloudUrl,
    this.fileName,
    this.fileType,
    this.fileSize,
    this.messageId,
    this.mediaType,
    this.errorMessage,
  });

  /// Convert to CachedMediaMessage
  CachedMediaMessage toMessage({
    required String senderId,
    required String senderRole,
    required String conversationId,
  }) {
    final mediaCategory = _mapToMediaCategory(mediaType ?? MediaType.document);

    return CachedMediaMessage(
      messageId: messageId ?? '',
      senderId: senderId,
      senderRole: senderRole,
      conversationId: conversationId,
      fileName: fileName ?? 'unknown',
      fileType: fileType ?? 'application/octet-stream',
      fileSize: fileSize ?? 0,
      cloudUrl: cloudUrl ?? '',
      localPath: localPath,
      isDownloaded: true,
      mediaType: mediaCategory,
      createdAt: DateTime.now(),
      downloadedAt: DateTime.now(),
      isPending: cloudUrl == null || cloudUrl!.isEmpty,
      uploadFailed: !success,
      errorMessage: errorMessage,
    );
  }

  MediaTypeCategory _mapToMediaCategory(MediaType mediaType) {
    switch (mediaType) {
      case MediaType.image:
        return MediaTypeCategory.image;
      case MediaType.audio:
        return MediaTypeCategory.audio;
      case MediaType.pdf:
        return MediaTypeCategory.pdf;
      case MediaType.document:
        return MediaTypeCategory.document;
    }
  }
}
