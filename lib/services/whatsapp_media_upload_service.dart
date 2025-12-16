import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/media_metadata.dart';
import 'image_compression_service.dart';
import 'local_media_storage_service.dart';

/// WhatsApp-style media upload service
/// Compresses and uploads images to Cloudflare Worker
class WhatsAppMediaUploadService {
  final String workerBaseUrl;
  final ImageCompressionService _compressionService;
  final LocalMediaStorageService _storageService;

  WhatsAppMediaUploadService({
    required this.workerBaseUrl,
    ImageCompressionService? compressionService,
    LocalMediaStorageService? storageService,
  }) : _compressionService = compressionService ?? ImageCompressionService(),
       _storageService = storageService ?? LocalMediaStorageService();

  /// Upload image with WhatsApp-style compression
  /// Returns MediaMetadata with R2 details
  Future<UploadResult> uploadImage({
    required File imageFile,
    required String messageId,
    required String conversationId,
    required String senderId,
    Function(double progress)? onProgress,
  }) async {
    try {
      // Step 1: Validate image
      final isValid = await _compressionService.isValidImage(imageFile);
      if (!isValid) {
        return UploadResult(
          success: false,
          error: UploadError.invalidImage,
          errorMessage: 'Invalid image file',
        );
      }

      // Step 2: Generate thumbnail
      onProgress?.call(0.1);
      debugPrint('📸 Generating thumbnail...');
      final thumbnail = await _compressionService.generateThumbnail(
        imageFile,
        returnBase64: true,
      );

      // Step 3: Compress full image
      onProgress?.call(0.3);
      debugPrint('🗜️ Compressing image...');
      final compressedBytes = await _compressionService.compressImage(
        imageFile,
      );

      debugPrint('✅ Compressed: ${compressedBytes.length} bytes');

      // Step 4: Upload to Cloudflare Worker
      onProgress?.call(0.5);
      debugPrint('☁️ Uploading to R2...');

      final uploadResponse = await _uploadToWorker(
        imageBytes: compressedBytes,
        messageId: messageId,
        conversationId: conversationId,
        senderId: senderId,
      );

      if (!uploadResponse.success) {
        return uploadResponse;
      }

      onProgress?.call(0.9);

      // Step 5: Save locally
      debugPrint('💾 Saving locally...');
      final localPath = await _storageService.saveImage(
        messageId: messageId,
        imageBytes: compressedBytes,
      );

      // Step 6: Create metadata
      final metadata = MediaMetadata(
        messageId: messageId,
        r2Key: uploadResponse.r2Key!,
        publicUrl: uploadResponse.publicUrl!,
        localPath: localPath,
        thumbnail: thumbnail,
        deletedLocally: false,
        serverStatus: ServerStatus.available,
        expiresAt: uploadResponse.expiresAt!,
        uploadedAt: DateTime.now(),
        fileSize: compressedBytes.length,
        mimeType: 'image/jpeg',
      );

      onProgress?.call(1.0);
      debugPrint('✅ Upload complete!');

      return UploadResult(success: true, metadata: metadata);
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      return UploadResult(
        success: false,
        error: UploadError.unknown,
        errorMessage: e.toString(),
      );
    }
  }

  /// Upload compressed bytes to Cloudflare Worker
  Future<UploadResult> _uploadToWorker({
    required Uint8List imageBytes,
    required String messageId,
    required String conversationId,
    required String senderId,
  }) async {
    try {
      final url = Uri.parse('$workerBaseUrl/upload');

      final request = http.MultipartRequest('POST', url);

      // Add metadata
      request.fields['messageId'] = messageId;
      request.fields['conversationId'] = conversationId;
      request.fields['senderId'] = senderId;
      request.fields['expiryDays'] = '30';

      // Add image file
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: '$messageId.jpg',
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Upload timeout'),
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          return UploadResult(
            success: true,
            r2Key: data['key'] as String,
            publicUrl: data['publicUrl'] as String,
            expiresAt: DateTime.parse(data['expiresAt'] as String),
          );
        } else {
          return UploadResult(
            success: false,
            error: UploadError.workerError,
            errorMessage: data['message'] ?? 'Upload failed',
          );
        }
      } else if (response.statusCode == 413) {
        return UploadResult(
          success: false,
          error: UploadError.fileTooLarge,
          errorMessage: 'File too large',
        );
      } else if (response.statusCode >= 500) {
        return UploadResult(
          success: false,
          error: UploadError.serverError,
          errorMessage: 'Server error: ${response.statusCode}',
        );
      } else {
        return UploadResult(
          success: false,
          error: UploadError.httpError,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }
    } on SocketException {
      return UploadResult(
        success: false,
        error: UploadError.networkError,
        errorMessage: 'No internet connection',
      );
    } on TimeoutException {
      return UploadResult(
        success: false,
        error: UploadError.timeout,
        errorMessage: 'Upload timeout',
      );
    } catch (e) {
      return UploadResult(
        success: false,
        error: UploadError.unknown,
        errorMessage: e.toString(),
      );
    }
  }
}

/// Upload result wrapper
class UploadResult {
  final bool success;
  final MediaMetadata? metadata;
  final String? r2Key;
  final String? publicUrl;
  final DateTime? expiresAt;
  final UploadError? error;
  final String? errorMessage;

  UploadResult({
    required this.success,
    this.metadata,
    this.r2Key,
    this.publicUrl,
    this.expiresAt,
    this.error,
    this.errorMessage,
  });
}

/// Upload error types
enum UploadError {
  invalidImage,
  compressionFailed,
  workerError,
  fileTooLarge,
  serverError,
  httpError,
  networkError,
  timeout,
  unknown;

  String get message {
    switch (this) {
      case UploadError.invalidImage:
        return 'Invalid image file';
      case UploadError.compressionFailed:
        return 'Failed to compress image';
      case UploadError.workerError:
        return 'Upload failed';
      case UploadError.fileTooLarge:
        return 'File too large';
      case UploadError.serverError:
        return 'Server error';
      case UploadError.httpError:
        return 'Upload failed';
      case UploadError.networkError:
        return 'No internet connection';
      case UploadError.timeout:
        return 'Upload timeout';
      case UploadError.unknown:
        return 'Unknown error';
    }
  }
}
