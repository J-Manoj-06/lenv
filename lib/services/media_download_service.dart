import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/media_metadata.dart';
import 'local_media_storage_service.dart';

/// WhatsApp-style media download manager
/// Handles download with retry, exponential backoff, and error handling
class MediaDownloadService {
  final LocalMediaStorageService _storageService;
  static const int maxRetries = 3;
  static const int initialRetryDelayMs = 1000;

  MediaDownloadService({LocalMediaStorageService? storageService})
    : _storageService = storageService ?? LocalMediaStorageService();

  /// Download image from R2 with full WhatsApp-style logic
  /// Returns updated MediaMetadata with local path or error status
  Future<DownloadResult> downloadImage({
    required MediaMetadata metadata,
    Function(double progress)? onProgress,
  }) async {
    try {
      // Check if already deleted locally
      if (metadata.deletedLocally) {
        return DownloadResult(
          success: false,
          error: DownloadError.deletedLocally,
          metadata: metadata,
        );
      }

      // Check if already exists locally
      if (metadata.hasLocalFile) {
        final exists = await _storageService.imageExists(metadata.messageId);
        if (exists) {
          return DownloadResult(
            success: true,
            metadata: metadata,
            fromCache: true,
          );
        }
      }

      // Check server status
      if (metadata.serverStatus == ServerStatus.expired) {
        return DownloadResult(
          success: false,
          error: DownloadError.expired,
          metadata: metadata,
        );
      }

      if (metadata.serverStatus == ServerStatus.missing ||
          metadata.serverStatus == ServerStatus.deleted) {
        return DownloadResult(
          success: false,
          error: DownloadError.missing,
          metadata: metadata,
        );
      }

      // Check storage availability
      final estimatedSize =
          metadata.fileSize ?? 5 * 1024 * 1024; // 5 MB default
      final hasSpace = await _storageService.hasEnoughStorage(estimatedSize);
      if (!hasSpace) {
        return DownloadResult(
          success: false,
          error: DownloadError.storageFull,
          metadata: metadata,
        );
      }

      // Attempt download with retry
      return await _downloadWithRetry(
        url: metadata.publicUrl,
        metadata: metadata,
        onProgress: onProgress,
      );
    } catch (e) {
      return DownloadResult(
        success: false,
        error: DownloadError.unknown,
        metadata: metadata,
        errorMessage: e.toString(),
      );
    }
  }

  /// Download with exponential backoff retry
  Future<DownloadResult> _downloadWithRetry({
    required String url,
    required MediaMetadata metadata,
    Function(double progress)? onProgress,
    int attempt = 1,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Download timeout'),
          );

      // Handle HTTP status codes
      if (response.statusCode == 200) {
        return await _handleSuccessfulDownload(
          response: response,
          metadata: metadata,
        );
      } else if (response.statusCode == 404) {
        return _handleHttpError(
          statusCode: 404,
          metadata: metadata,
          error: DownloadError.missing,
        );
      } else if (response.statusCode == 410) {
        return _handleHttpError(
          statusCode: 410,
          metadata: metadata,
          error: DownloadError.expired,
        );
      } else if (response.statusCode == 403) {
        return _handleHttpError(
          statusCode: 403,
          metadata: metadata,
          error: DownloadError.forbidden,
        );
      } else if (response.statusCode >= 500) {
        // Server error - retry
        if (attempt < maxRetries) {
          return await _retryDownload(
            url: url,
            metadata: metadata,
            attempt: attempt,
            onProgress: onProgress,
          );
        } else {
          return _handleHttpError(
            statusCode: response.statusCode,
            metadata: metadata,
            error: DownloadError.serverError,
          );
        }
      } else {
        return _handleHttpError(
          statusCode: response.statusCode,
          metadata: metadata,
          error: DownloadError.httpError,
        );
      }
    } on SocketException {
      // Network error - retry
      if (attempt < maxRetries) {
        return await _retryDownload(
          url: url,
          metadata: metadata,
          attempt: attempt,
          onProgress: onProgress,
        );
      } else {
        return DownloadResult(
          success: false,
          error: DownloadError.networkError,
          metadata: metadata,
          errorMessage: 'No internet connection',
        );
      }
    } on TimeoutException {
      // Timeout - retry
      if (attempt < maxRetries) {
        return await _retryDownload(
          url: url,
          metadata: metadata,
          attempt: attempt,
          onProgress: onProgress,
        );
      } else {
        return DownloadResult(
          success: false,
          error: DownloadError.timeout,
          metadata: metadata,
          errorMessage: 'Download timeout',
        );
      }
    } catch (e) {
      if (attempt < maxRetries) {
        return await _retryDownload(
          url: url,
          metadata: metadata,
          attempt: attempt,
          onProgress: onProgress,
        );
      } else {
        return DownloadResult(
          success: false,
          error: DownloadError.unknown,
          metadata: metadata,
          errorMessage: e.toString(),
        );
      }
    }
  }

  /// Retry with exponential backoff
  Future<DownloadResult> _retryDownload({
    required String url,
    required MediaMetadata metadata,
    required int attempt,
    Function(double progress)? onProgress,
  }) async {
    final delay = initialRetryDelayMs * (1 << (attempt - 1)); // 2^n
    await Future.delayed(Duration(milliseconds: delay));

    return await _downloadWithRetry(
      url: url,
      metadata: metadata,
      onProgress: onProgress,
      attempt: attempt + 1,
    );
  }

  /// Handle successful download
  Future<DownloadResult> _handleSuccessfulDownload({
    required http.Response response,
    required MediaMetadata metadata,
  }) async {
    try {
      final bytes = response.bodyBytes;

      // Validate file size
      final expectedSize = metadata.fileSize;
      if (expectedSize != null && bytes.length != expectedSize) {
        return DownloadResult(
          success: false,
          error: DownloadError.partialDownload,
          metadata: metadata,
        );
      }

      // Save to local storage
      final localPath = await _storageService.saveImage(
        messageId: metadata.messageId,
        imageBytes: bytes,
      );

      // Update metadata
      final updatedMetadata = metadata.copyWith(
        localPath: localPath,
        serverStatus: ServerStatus.available,
      );

      return DownloadResult(
        success: true,
        metadata: updatedMetadata,
        fromCache: false,
      );
    } catch (e) {
      return DownloadResult(
        success: false,
        error: DownloadError.saveFailed,
        metadata: metadata,
        errorMessage: e.toString(),
      );
    }
  }

  /// Handle HTTP error codes
  DownloadResult _handleHttpError({
    required int statusCode,
    required MediaMetadata metadata,
    required DownloadError error,
  }) {
    final serverStatus = ServerStatus.fromHttpCode(statusCode);
    final updatedMetadata = metadata.copyWith(serverStatus: serverStatus);

    return DownloadResult(
      success: false,
      error: error,
      metadata: updatedMetadata,
      errorMessage: 'HTTP $statusCode',
    );
  }
}

/// Download result wrapper
class DownloadResult {
  final bool success;
  final MediaMetadata metadata;
  final DownloadError? error;
  final String? errorMessage;
  final bool fromCache;

  DownloadResult({
    required this.success,
    required this.metadata,
    this.error,
    this.errorMessage,
    this.fromCache = false,
  });
}

/// Download error types
enum DownloadError {
  deletedLocally,
  expired,
  missing,
  forbidden,
  serverError,
  httpError,
  networkError,
  timeout,
  partialDownload,
  saveFailed,
  storageFull,
  unknown;

  String get message {
    switch (this) {
      case DownloadError.deletedLocally:
        return 'Image is no longer on your device';
      case DownloadError.expired:
        return 'Image expired on server';
      case DownloadError.missing:
        return 'Image not found on server';
      case DownloadError.forbidden:
        return 'Access denied';
      case DownloadError.serverError:
        return 'Server error, try again later';
      case DownloadError.httpError:
        return 'Failed to download';
      case DownloadError.networkError:
        return 'No internet connection';
      case DownloadError.timeout:
        return 'Download timeout';
      case DownloadError.partialDownload:
        return 'Partial download, retrying...';
      case DownloadError.saveFailed:
        return 'Failed to save image';
      case DownloadError.storageFull:
        return 'Storage full';
      case DownloadError.unknown:
        return 'Unknown error';
    }
  }
}
