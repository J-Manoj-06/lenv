import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'media_storage_helper.dart';

class ImageViewerActionService {
  ImageViewerActionService._();

  static final Set<String> _allowedHosts = {'files.lenv1.tech'};
  static final Map<String, String> _savedPathBySource = {};
  static final Map<String, String> _sessionCacheByUrl = {};
  static final MediaStorageHelper _storageHelper = MediaStorageHelper();

  static bool isAllowedImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (!(uri.isScheme('http') || uri.isScheme('https'))) return false;
    return _allowedHosts.contains(uri.host.toLowerCase());
  }

  static Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final photosStatus = await Permission.photos.status;
    if (photosStatus.isGranted || photosStatus.isLimited) {
      return true;
    }

    final photosResult = await Permission.photos.request();
    if (photosResult.isGranted || photosResult.isLimited) {
      return true;
    }

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    final storageResult = await Permission.storage.request();
    return storageResult.isGranted;
  }

  static Future<String?> ensureImageFile({
    String? localPath,
    String? publicUrl,
  }) async {
    if (localPath != null && localPath.isNotEmpty) {
      final localFile = File(localPath);
      if (await localFile.exists()) {
        return localFile.path;
      }
    }

    if (!isAllowedImageUrl(publicUrl)) {
      return null;
    }

    if (_sessionCacheByUrl.containsKey(publicUrl)) {
      final path = _sessionCacheByUrl[publicUrl]!;
      if (await File(path).exists()) return path;
    }

    final file = await DefaultCacheManager().getSingleFile(publicUrl!);
    _sessionCacheByUrl[publicUrl] = file.path;
    return file.path;
  }

  static Future<String?> saveImageToGallery({
    String? localPath,
    String? publicUrl,
    String? sourceKey,
    String? fileNameHint,
  }) async {
    final key = sourceKey ?? publicUrl ?? localPath ?? '';
    if (key.isNotEmpty && _savedPathBySource.containsKey(key)) {
      final previous = _savedPathBySource[key]!;
      if (await File(previous).exists()) {
        return previous;
      }
      _savedPathBySource.remove(key);
    }

    final hasPermission = await ensureStoragePermission();
    if (!hasPermission) {
      return null;
    }

    final imagePath = await ensureImageFile(
      localPath: localPath,
      publicUrl: publicUrl,
    );
    if (imagePath == null) return null;

    final file = File(imagePath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final extension = _resolveExtension(file.path, fileNameHint);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final outputName = 'lenv_image_$timestamp.$extension';

    final savedPath = await _storageHelper.saveToPublicStorage(
      bytes: bytes,
      fileName: outputName,
      mimeType: lookupMimeType(outputName) ?? 'image/jpeg',
    );

    if (key.isNotEmpty) {
      _savedPathBySource[key] = savedPath;
    }

    return savedPath;
  }

  static Future<bool> shareImage({
    String? localPath,
    String? publicUrl,
    String? fileNameHint,
  }) async {
    try {
      final imagePath = await ensureImageFile(
        localPath: localPath,
        publicUrl: publicUrl,
      );

      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          final mimeType = lookupMimeType(imagePath) ?? 'image/jpeg';
          final fileName =
              (fileNameHint != null && fileNameHint.trim().isNotEmpty)
              ? fileNameHint.trim()
              : p.basename(imagePath);

          try {
            await Share.shareXFiles([
              XFile(imagePath, mimeType: mimeType, name: fileName),
            ], text: fileNameHint ?? 'Image');
            return true;
          } catch (_) {
            final bytes = await file.readAsBytes();
            await Share.shareXFiles([
              XFile.fromData(bytes, mimeType: mimeType, name: fileName),
            ], text: fileNameHint ?? 'Image');
            return true;
          }
        }
      }

      if (publicUrl != null && publicUrl.isNotEmpty) {
        await Share.share(publicUrl, subject: fileNameHint ?? 'Image');
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  static String _resolveExtension(String path, String? fileNameHint) {
    final fromPath = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (fromPath.isNotEmpty) return fromPath;

    if (fileNameHint != null && fileNameHint.isNotEmpty) {
      final fromHint = p
          .extension(fileNameHint)
          .toLowerCase()
          .replaceFirst('.', '');
      if (fromHint.isNotEmpty) return fromHint;
    }

    return 'jpg';
  }
}
