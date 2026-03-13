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
    final imagePath = await ensureImageFile(
      localPath: localPath,
      publicUrl: publicUrl,
    );
    if (imagePath == null) return false;

    await Share.shareXFiles([
      XFile(imagePath, mimeType: lookupMimeType(imagePath) ?? 'image/jpeg'),
    ], text: fileNameHint ?? 'Image');
    return true;
  }

  static Future<String?> ensureMediaFile({
    String? localPath,
    String? publicUrl,
  }) async {
    if (localPath != null && localPath.isNotEmpty) {
      final localFile = File(localPath);
      if (await localFile.exists()) {
        return localFile.path;
      }
    }

    if (publicUrl == null || publicUrl.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(publicUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }

    if (_sessionCacheByUrl.containsKey(publicUrl)) {
      final path = _sessionCacheByUrl[publicUrl]!;
      if (await File(path).exists()) return path;
    }

    final file = await DefaultCacheManager().getSingleFile(publicUrl);
    _sessionCacheByUrl[publicUrl] = file.path;
    return file.path;
  }

  static Future<bool> shareMediaFiles({
    required List<ShareMediaItem> items,
    String? text,
    bool requireLocalOnly = false,
  }) async {
    if (items.isEmpty) return false;

    try {
      final files = <XFile>[];
      final fallbackUrls = <String>[];

      for (final item in items) {
        final path = requireLocalOnly
            ? await _existingLocalPath(item.localPath)
            : await ensureMediaFile(
                localPath: item.localPath,
                publicUrl: item.publicUrl,
              );

        if (path != null) {
          final mimeType =
              item.mimeType ?? lookupMimeType(path) ?? 'application/octet-stream';
          final fileName =
              (item.fileName != null && item.fileName!.trim().isNotEmpty)
              ? item.fileName!.trim()
              : p.basename(path);
          files.add(XFile(path, mimeType: mimeType, name: fileName));
        } else if (!requireLocalOnly &&
            item.publicUrl != null &&
            item.publicUrl!.isNotEmpty) {
          fallbackUrls.add(item.publicUrl!);
        }
      }

      if (files.isNotEmpty) {
        await Share.shareXFiles(files, text: text);
        return true;
      }

      if (!requireLocalOnly && fallbackUrls.isNotEmpty) {
        await Share.share(fallbackUrls.join('\n'), subject: text ?? 'Media');
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _existingLocalPath(String? localPath) async {
    if (localPath == null || localPath.isEmpty) return null;
    final file = File(localPath);
    if (await file.exists()) return file.path;
    return null;
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

class ShareMediaItem {
  final String? localPath;
  final String? publicUrl;
  final String? fileName;
  final String? mimeType;

  const ShareMediaItem({
    this.localPath,
    this.publicUrl,
    this.fileName,
    this.mimeType,
  });
}
