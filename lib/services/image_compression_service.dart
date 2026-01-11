import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';

/// WhatsApp-style image compression service
/// Compresses images to reduce storage and bandwidth costs
class ImageCompressionService {
  static const int maxWidth = 1080;
  static const int maxHeight = 1920;
  static const int quality = 65; // Optimized for speed and size
  // Aggressive mode for community chat
  static const int aggressiveMaxWidth = 720;
  static const int aggressiveMaxHeight = 1280;
  static const int aggressiveQuality = 55;
  static const int thumbnailSize = 200;
  static const int thumbnailQuality = 60;
  static const int maxThumbnailSizeBytes = 20 * 1024; // 20 KB

  /// Compress full-resolution image for upload
  /// Returns compressed JPEG bytes
  Future<Uint8List> compressImage(
    File imageFile, {
    int? customQuality,
    int? customMaxWidth,
    bool aggressive = false,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return await compute(_compressImageIsolate, {
        'bytes': bytes,
        'quality': customQuality ?? (aggressive ? aggressiveQuality : quality),
        'maxWidth': customMaxWidth ?? (aggressive ? aggressiveMaxWidth : maxWidth),
        'maxHeight': aggressive ? aggressiveMaxHeight : maxHeight,
      });
    } catch (e) {
      // Fallback: return original bytes without compression
      try {
        final bytes = await imageFile.readAsBytes();
        return bytes;
      } catch (readErr) {
        rethrow;
      }
    }
  }

  /// Generate small thumbnail for chat preview
  /// Returns base64-encoded thumbnail or compressed bytes
  Future<String> generateThumbnail(
    File imageFile, {
    bool returnBase64 = true,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final thumbnailBytes = await compute(_generateThumbnailIsolate, {
        'bytes': bytes,
        'size': thumbnailSize,
        'quality': thumbnailQuality,
        'maxSizeBytes': maxThumbnailSizeBytes,
      });

      if (returnBase64) {
        return base64Encode(thumbnailBytes);
      } else {
        // Return as data URL for direct use
        return 'data:image/jpeg;base64,${base64Encode(thumbnailBytes)}';
      }
    } catch (e) {
      // Fallback: return a tiny 1x1 PNG base64
      const tinyPngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+JYQUAAAAASUVORK5CYII=';
      return tinyPngBase64;
    }
  }

  /// Compress image in isolate to avoid blocking UI
  static Uint8List _compressImageIsolate(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final int quality = params['quality'];
    final int maxWidth = params['maxWidth'];
    final int maxHeight = params['maxHeight'];

    // Decode image
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Resize if needed
    if (image.width > maxWidth || image.height > maxHeight) {
      image = img.copyResize(
        image,
        width: image.width > maxWidth ? maxWidth : null,
        height: image.height > maxHeight ? maxHeight : null,
        maintainAspect: true,
        interpolation: img.Interpolation.linear,
      );
    }

    // Encode as JPEG with quality setting
    final compressed = img.encodeJpg(image, quality: quality);
    return Uint8List.fromList(compressed);
  }

  /// Generate thumbnail in isolate
  static Uint8List _generateThumbnailIsolate(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'];
    final int size = params['size'];
    int quality = params['quality'];
    final int maxSizeBytes = params['maxSizeBytes'];

    // Decode image
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image for thumbnail');
    }

    // Resize to thumbnail size (square crop from center)
    final thumbnailImage = img.copyResizeCropSquare(
      image,
      size: size,
      interpolation: img.Interpolation.average,
    );

    // Compress until under max size
    Uint8List compressed;
    do {
      compressed = Uint8List.fromList(
        img.encodeJpg(thumbnailImage, quality: quality),
      );
      if (compressed.length <= maxSizeBytes) break;
      quality -= 5;
    } while (quality > 10);

    return compressed;
  }

  /// Get image dimensions without full decode
  Future<Map<String, int>> getImageDimensions(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      return {'width': image.width, 'height': image.height};
    } catch (e) {
      rethrow;
    }
  }

  /// Validate image file
  Future<bool> isValidImage(File imageFile) async {
    try {
      // Be tolerant: use MIME type check first
      final mime = lookupMimeType(imageFile.path) ?? '';
      if (mime.startsWith('image/')) {
        return true;
      }
      // As a secondary check, attempt decode
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      return image != null;
    } catch (e) {
      return false;
    }
  }

  /// Estimate compressed size without full compression
  Future<int> estimateCompressedSize(File imageFile) async {
    try {
      final stat = await imageFile.stat();
      final originalSize = stat.size;

      // Rough estimate: compressed size is typically 10-30% of original
      // depending on image content
      return (originalSize * 0.2).round();
    } catch (e) {
      return 0;
    }
  }
}
