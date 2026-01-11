import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// WhatsApp-style local media storage manager
/// Manages saving, loading, and deleting images locally
class LocalMediaStorageService {
  static const String mediaDir = 'media';
  static const String chatImagesDir = 'chat_images';
  static const String thumbnailsDir = 'thumbnails';

  /// Get the app's media directory
  /// Structure: app_directory/media/chat_images/{messageId}.jpg
  Future<Directory> getMediaDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDirPath = path.join(appDir.path, mediaDir, chatImagesDir);
    final dir = Directory(mediaDirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// Get thumbnails directory
  Future<Directory> getThumbnailsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final thumbnailDirPath = path.join(appDir.path, mediaDir, thumbnailsDir);
    final dir = Directory(thumbnailDirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// Save image file to local storage
  /// Returns the local file path
  Future<String> saveImage({
    required String messageId,
    required Uint8List imageBytes,
  }) async {
    try {
      final dir = await getMediaDirectory();
      final filePath = path.join(dir.path, '$messageId.jpg');
      final file = File(filePath);

      await file.writeAsBytes(imageBytes);

      return filePath;
    } catch (e) {
      rethrow;
    }
  }

  /// Save thumbnail separately
  Future<String> saveThumbnail({
    required String messageId,
    required Uint8List thumbnailBytes,
  }) async {
    try {
      final dir = await getThumbnailsDirectory();
      final filePath = path.join(dir.path, '$messageId.jpg');
      final file = File(filePath);

      await file.writeAsBytes(thumbnailBytes);

      return filePath;
    } catch (e) {
      rethrow;
    }
  }

  /// Load image from local storage
  /// Returns null if file doesn't exist
  Future<File?> loadImage(String messageId) async {
    try {
      final dir = await getMediaDirectory();
      final filePath = path.join(dir.path, '$messageId.jpg');
      final file = File(filePath);

      if (await file.exists()) {
        return file;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Check if image exists locally
  Future<bool> imageExists(String messageId) async {
    try {
      final dir = await getMediaDirectory();
      final filePath = path.join(dir.path, '$messageId.jpg');
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get local file path for message ID
  Future<String> getLocalPath(String messageId) async {
    final dir = await getMediaDirectory();
    return path.join(dir.path, '$messageId.jpg');
  }

  /// Delete image from local storage
  /// Used when user deletes image locally
  Future<bool> deleteImage(String messageId) async {
    try {
      final dir = await getMediaDirectory();
      final filePath = path.join(dir.path, '$messageId.jpg');
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Delete thumbnail
  Future<bool> deleteThumbnail(String messageId) async {
    try {
      final dir = await getThumbnailsDirectory();
      final filePath = path.join(dir.path, '$messageId.jpg');
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Clear all chat media (for "clear chat media" feature)
  /// Keeps thumbnails but removes full images
  Future<int> clearAllChatMedia() async {
    try {
      final dir = await getMediaDirectory();
      int deletedCount = 0;

      if (await dir.exists()) {
        final files = dir.listSync();
        for (final file in files) {
          if (file is File) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      return deletedCount;
    } catch (e) {
      return 0;
    }
  }

  /// Get available storage space
  /// Returns available bytes
  Future<int> getAvailableStorage() async {
    try {
      // On mobile, we can check disk space
      // This is a simplified check - actual implementation depends on platform
      if (Platform.isAndroid || Platform.isIOS) {
        // Use device_info_plus or other package for accurate storage info
        // For now, return a large number
        return 1000000000; // 1 GB placeholder
      }

      return 1000000000; // Default 1 GB
    } catch (e) {
      return 0;
    }
  }

  /// Check if there's enough storage for download
  Future<bool> hasEnoughStorage(int requiredBytes) async {
    try {
      final available = await getAvailableStorage();
      // Require at least 50 MB buffer
      const buffer = 50 * 1024 * 1024;
      return available > (requiredBytes + buffer);
    } catch (e) {
      return false;
    }
  }

  /// Get file size
  Future<int> getFileSize(String messageId) async {
    try {
      final file = await loadImage(messageId);
      if (file != null) {
        final stat = await file.stat();
        return stat.size;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get total media storage used
  Future<int> getTotalStorageUsed() async {
    try {
      final dir = await getMediaDirectory();
      int totalSize = 0;

      if (await dir.exists()) {
        final files = dir.listSync();
        for (final file in files) {
          if (file is File) {
            final stat = await file.stat();
            totalSize += stat.size;
          }
        }
      }

      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}
