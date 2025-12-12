import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/downloaded_media.dart';

/// Helper class for managing local media file storage
/// Handles file paths, directories, and metadata persistence
class MediaStorageHelper {
  static const String _storageKey = 'downloaded_media_v1';
  static const String _mediaFolderName = 'media';

  /// Get the base directory for storing media files
  /// Creates /storage/emulated/0/Android/data/com.lenv.reward/files/media/ folder structure
  /// This ensures files are actually saved to device storage
  Future<Directory> getMediaDirectory() async {
    // Use external storage so files are actually saved to device
    Directory? appDocDir;
    try {
      appDocDir = await getExternalStorageDirectory();
    } catch (e) {
      print('⚠️ External storage not available, using internal: $e');
      appDocDir = await getApplicationDocumentsDirectory();
    }

    if (appDocDir == null) {
      throw Exception('Unable to get storage directory');
    }

    final Directory mediaDir = Directory('${appDocDir.path}/$_mediaFolderName');

    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
      print('📁 Created media directory: ${mediaDir.path}');
    }

    return mediaDir;
  }

  /// Generate local file path for a given R2 key
  /// Example: "media/1234567/file.pdf" -> "/app_documents/media/1234567_file.pdf"
  Future<String> getLocalFilePath(String r2Key) async {
    final mediaDir = await getMediaDirectory();

    // Sanitize the key to create a safe filename
    // Replace slashes with underscores to flatten the structure
    final sanitizedKey = r2Key.replaceAll('/', '_').replaceAll(' ', '_');

    return '${mediaDir.path}/$sanitizedKey';
  }

  /// Check if a file exists locally
  Future<bool> fileExists(String localPath) async {
    final file = File(localPath);
    return await file.exists();
  }

  /// Delete a local file
  Future<bool> deleteFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error deleting file: $e');
      return false;
    }
  }

  /// Get file size
  Future<int> getFileSize(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      print('❌ Error getting file size: $e');
      return 0;
    }
  }

  /// Save downloaded media metadata
  Future<void> saveMediaMetadata(DownloadedMedia media) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getAllMediaMetadata();
      existing[media.key] = media;

      final jsonMap = existing.map(
        (key, value) => MapEntry(key, value.toJson()),
      );

      await prefs.setString(_storageKey, json.encode(jsonMap));
      print('✅ Saved metadata for: ${media.key}');
    } catch (e) {
      print('❌ Error saving media metadata: $e');
    }
  }

  /// Get metadata for a specific media key
  Future<DownloadedMedia?> getMediaMetadata(String key) async {
    try {
      final all = await getAllMediaMetadata();
      return all[key];
    } catch (e) {
      print('❌ Error getting media metadata: $e');
      return null;
    }
  }

  /// Get all downloaded media metadata
  Future<Map<String, DownloadedMedia>> getAllMediaMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        return {};
      }

      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      return jsonMap.map(
        (key, value) => MapEntry(
          key,
          DownloadedMedia.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (e) {
      print('❌ Error loading media metadata: $e');
      return {};
    }
  }

  /// Remove metadata for a specific key
  Future<void> removeMediaMetadata(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getAllMediaMetadata();
      existing.remove(key);

      final jsonMap = existing.map(
        (key, value) => MapEntry(key, value.toJson()),
      );

      await prefs.setString(_storageKey, json.encode(jsonMap));
      print('✅ Removed metadata for: $key');
    } catch (e) {
      print('❌ Error removing media metadata: $e');
    }
  }

  /// Clear all downloaded media (files + metadata)
  Future<void> clearAllMedia() async {
    try {
      // Delete all files
      final mediaDir = await getMediaDirectory();
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }

      // Clear metadata
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);

      print('✅ Cleared all media');
    } catch (e) {
      print('❌ Error clearing all media: $e');
    }
  }

  /// Get total storage used by downloaded media
  Future<int> getTotalStorageUsed() async {
    try {
      final all = await getAllMediaMetadata();
      return all.values.fold<int>(0, (sum, media) => sum + media.fileSize);
    } catch (e) {
      print('❌ Error calculating storage: $e');
      return 0;
    }
  }

  /// Get count of downloaded files
  Future<int> getDownloadedCount() async {
    final all = await getAllMediaMetadata();
    return all.length;
  }

  /// Format storage size for display
  String formatStorageSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
