import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
    bool aggressiveCompression = false,
  }) async {
    try {
      // Step 1: Validate image (tolerant)
      final isValid = await _compressionService.isValidImage(imageFile);
      if (!isValid) {
        return UploadResult(
          success: false,
          error: UploadError.invalidImage,
          errorMessage: 'Invalid image file',
        );
      }

      // Step 2 & 3: Generate thumbnail and compress in parallel
      onProgress?.call(0.1);
      final results = await Future.wait([
        _compressionService.generateThumbnail(imageFile, returnBase64: true),
        _compressionService.compressImage(imageFile),
      ]);
      final thumbnail = results[0] as String;
      final compressedBytes = results[1] as Uint8List;

      // Step 4: Upload to Cloudflare Worker with retry
      onProgress?.call(0.5);
      final uploadStartTime = DateTime.now();

      // We encode to JPEG in compression, so use consistent JPEG MIME
      final mimeType = 'image/jpeg';
      final fileExt = 'jpg';

      final uploadResponse = await _uploadToWorkerWithRetry(
        imageBytes: compressedBytes,
        messageId: messageId,
        conversationId: conversationId,
        senderId: senderId,
        mimeType: mimeType,
        fileExt: fileExt,
        onProgress: onProgress,
      );

      if (!uploadResponse.success) {
        return uploadResponse;
      }

      final uploadDuration = DateTime.now().difference(uploadStartTime);
      final speedKBps =
          (compressedBytes.length / 1024) / uploadDuration.inSeconds;

      onProgress?.call(0.9);

      // Step 5: Create metadata with sender's local path

      // Save to local storage for consistency across app restarts
      final localPath = await _storageService.saveImage(
        messageId: messageId,
        imageBytes: compressedBytes,
      );

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
        mimeType: mimeType,
      );

      onProgress?.call(1.0);

      return UploadResult(success: true, metadata: metadata);
    } catch (e) {
      return UploadResult(
        success: false,
        error: UploadError.unknown,
        errorMessage: e.toString(),
      );
    }
  }

  /// Upload with retry logic for network failures
  Future<UploadResult> _uploadToWorkerWithRetry({
    required Uint8List imageBytes,
    required String messageId,
    required String conversationId,
    required String senderId,
    required String mimeType,
    required String fileExt,
    Function(double progress)? onProgress,
  }) async {
    const maxRetries = 3;
    const initialDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final result = await _uploadToWorker(
        imageBytes: imageBytes,
        messageId: messageId,
        conversationId: conversationId,
        senderId: senderId,
        mimeType: mimeType,
        fileExt: fileExt,
      );

      if (result.success) {
        return result;
      }

      // Retry on network errors or server errors
      final shouldRetry =
          result.error == UploadError.networkError ||
          result.error == UploadError.timeout ||
          result.error == UploadError.serverError ||
          result.error == UploadError.unknown;

      if (!shouldRetry || attempt == maxRetries) {
        return result;
      }

      // Exponential backoff
      final delay = initialDelay * attempt;
      await Future.delayed(delay);
    }

    return UploadResult(
      success: false,
      error: UploadError.unknown,
      errorMessage: 'Upload failed after $maxRetries attempts',
    );
  }

  /// Upload compressed bytes to Cloudflare Worker
  Future<UploadResult> _uploadToWorker({
    required Uint8List imageBytes,
    required String messageId,
    required String conversationId,
    required String senderId,
    required String mimeType,
    required String fileExt,
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
          filename: '$messageId.$fileExt',
          contentType: MediaType.parse(mimeType),
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Upload timeout after 60s'),
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
          errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } on SocketException {
      return UploadResult(
        success: false,
        error: UploadError.networkError,
        errorMessage: 'Network connection failed',
      );
    } on TimeoutException {
      return UploadResult(
        success: false,
        error: UploadError.timeout,
        errorMessage: 'Upload timeout - please check your connection',
      );
    } on http.ClientException {
      return UploadResult(
        success: false,
        error: UploadError.networkError,
        errorMessage: 'Connection reset - network unstable',
      );
    } catch (e) {
      return UploadResult(
        success: false,
        error: UploadError.unknown,
        errorMessage: e.toString(),
      );
    }
  }

  /// Note: This method is kept for future implementation but currently unused
  /// To use: uncomment and call from mime type handling code
  /*
  String _extFromMime(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/heic':
        return 'heic';
      default:
        return 'jpg';
    }
  }
  */
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
