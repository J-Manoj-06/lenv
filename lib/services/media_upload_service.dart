import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'cloudflare_r2_service.dart';
import 'local_cache_service.dart';
import '../models/media_message.dart';

/// Service to handle media uploads to Cloudflare R2 + Firebase Firestore
///
/// Features:
/// - Client-side image compression for thumbnails
/// - Signed URL upload to R2 (no server needed)
/// - Metadata stored in Firestore (cost-optimized)
/// - Local caching
/// - Progress tracking
class MediaUploadService {
  final CloudflareR2Service _r2Service;
  final FirebaseFirestore _firestore;
  final LocalCacheService _cacheService;

  // Image compression settings
  static const int MAX_IMAGE_WIDTH = 1920;
  static const int MAX_IMAGE_HEIGHT = 1080;
  static const int THUMBNAIL_SIZE = 200;
  static const int THUMBNAIL_QUALITY = 70;

  // File size limits
  static const int MAX_IMAGE_SIZE = 50 * 1024 * 1024; // 50MB
  static const int MAX_PDF_SIZE = 100 * 1024 * 1024; // 100MB
  static const int MAX_AUDIO_SIZE = 50 * 1024 * 1024; // 50MB

  MediaUploadService({
    required CloudflareR2Service r2Service,
    required FirebaseFirestore firestore,
    required LocalCacheService cacheService,
  }) : _r2Service = r2Service,
       _firestore = firestore,
       _cacheService = cacheService;

  /// Upload media file (image or PDF)
  ///
  /// Returns: MediaMessage with R2 URL and metadata
  Future<MediaMessage> uploadMedia({
    required File file,
    required String conversationId,
    required String senderId,
    required String senderRole,
    String mediaType =
        'message', // 'announcement' = 24h auto-delete, 'message'/'community' = permanent
    Function(int)? onProgress, // 0-100
  }) async {
    try {
      // Validate file
      final fileBytes = await file.readAsBytes();
      final fileName = file.path.split('/').last;
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

      _validateFile(fileName, fileBytes, mimeType);

      // Compress if image
      List<int> uploadBytes = fileBytes;
      List<int>? compressedThumbnail;
      int? imageWidth, imageHeight;

      if (mimeType.startsWith('image/')) {
        final compressed = _compressImage(fileBytes);
        uploadBytes = compressed['bytes'] as List<int>;
        imageWidth = compressed['width'] as int;
        imageHeight = compressed['height'] as int;

        // Generate thumbnail
        compressedThumbnail = _generateThumbnail(fileBytes);
      }
      // Audio files are uploaded as-is without compression

      onProgress?.call(10);

      // Generate signed URL from R2
      final signedUrlResponse = await _r2Service.generateSignedUploadUrl(
        fileName: fileName,
        fileType: mimeType,
      );

      onProgress?.call(20);

      // Upload to R2 using signed URL
      final r2Url = await _r2Service.uploadFileWithSignedUrl(
        fileBytes: uploadBytes,
        signedUrl: signedUrlResponse['url'],
        contentType: mimeType,
        onProgress: (progress) {
          // Scale progress to 30-80 range
          onProgress?.call(30 + ((progress / 100) * 50).toInt());
        },
      );

      onProgress?.call(80);

      // Generate thumbnail URL if image (upload separately)
      String? thumbnailUrl;
      if (compressedThumbnail != null && mimeType.startsWith('image/')) {
        thumbnailUrl = await _uploadThumbnail(
          thumbnailBytes: compressedThumbnail,
          mediaId: DateTime.now().millisecondsSinceEpoch.toString(),
        );
      }

      onProgress?.call(90);

      // Create MediaMessage object
      final mediaMessage = MediaMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: senderId,
        senderRole: senderRole,
        conversationId: conversationId,
        fileName: fileName,
        fileType: mimeType,
        fileSize: uploadBytes.length,
        r2Url: r2Url,
        thumbnailUrl: thumbnailUrl,
        mediaType: mediaType, // Pass through mediaType
        createdAt: DateTime.now(),
        width: imageWidth,
        height: imageHeight,
      );

      // Save metadata to Firestore
      await _saveMediaMetadataToFirestore(mediaMessage);

      // Note: Hive caching removed - new WhatsApp media system handles local storage
      // and Hive doesn't support Firestore Timestamp serialization

      onProgress?.call(100);

      return mediaMessage;
    } catch (e) {
      rethrow;
    }
  }

  /// Validate file before upload
  void _validateFile(String fileName, List<int> fileBytes, String mimeType) {
    // Check file size
    if (mimeType.startsWith('image/') && fileBytes.length > MAX_IMAGE_SIZE) {
      throw Exception(
        'Image too large. Max: ${MAX_IMAGE_SIZE ~/ (1024 * 1024)}MB',
      );
    }
    if (mimeType == 'application/pdf' && fileBytes.length > MAX_PDF_SIZE) {
      throw Exception('PDF too large. Max: ${MAX_PDF_SIZE ~/ (1024 * 1024)}MB');
    }
    if (mimeType.startsWith('audio/') && fileBytes.length > MAX_AUDIO_SIZE) {
      throw Exception(
        'Audio too large. Max: ${MAX_AUDIO_SIZE ~/ (1024 * 1024)}MB',
      );
    }

    // Check file type (images, PDFs, or audio)
    final isImage = mimeType.startsWith('image/');
    final isPdf = mimeType == 'application/pdf';
    final isAudio = mimeType.startsWith('audio/');

    if (!isImage && !isPdf && !isAudio) {
      throw Exception('Only images, PDFs, and audio files are supported');
    }

    // Check file name
    if (fileName.isEmpty) {
      throw Exception('Invalid file name');
    }
  }

  /// Compress image using the image package
  Map<String, dynamic> _compressImage(List<int> imageBytes) {
    try {
      final originalImage = img.decodeImage(Uint8List.fromList(imageBytes));
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }

      // Resize if needed
      img.Image compressedImage = originalImage;
      if (originalImage.width > MAX_IMAGE_WIDTH ||
          originalImage.height > MAX_IMAGE_HEIGHT) {
        compressedImage = img.copyResize(
          originalImage,
          width: MAX_IMAGE_WIDTH,
          height: MAX_IMAGE_HEIGHT,
          maintainAspect: true,
        );
      }

      // Encode as JPEG with quality setting
      final compressed = img.encodeJpg(compressedImage, quality: 85);

      return {
        'bytes': compressed,
        'width': compressedImage.width,
        'height': compressedImage.height,
      };
    } catch (e) {
      return {'bytes': imageBytes, 'width': 1920, 'height': 1080};
    }
  }

  /// Generate thumbnail for image preview (base64 encoded)
  List<int> _generateThumbnail(List<int> imageBytes) {
    try {
      final originalImage = img.decodeImage(Uint8List.fromList(imageBytes));
      if (originalImage == null) return imageBytes;

      final thumbnail = img.copyResize(
        originalImage,
        width: THUMBNAIL_SIZE,
        height: THUMBNAIL_SIZE,
        maintainAspect: true,
      );

      return img.encodeJpg(thumbnail, quality: THUMBNAIL_QUALITY);
    } catch (e) {
      return imageBytes;
    }
  }

  /// Upload thumbnail to R2 (separate file)
  Future<String> _uploadThumbnail({
    required List<int> thumbnailBytes,
    required String mediaId,
  }) async {
    try {
      final signedUrl = await _r2Service.generateSignedUploadUrl(
        fileName: 'thumb_$mediaId.jpg',
        fileType: 'image/jpeg',
      );

      final url = await _r2Service.uploadFileWithSignedUrl(
        fileBytes: thumbnailBytes,
        signedUrl: signedUrl['url'],
        contentType: 'image/jpeg',
      );

      return url;
    } catch (e) {
      return '';
    }
  }

  /// Save media metadata to Firestore (cost-optimized)
  /// Uses batch write for efficiency
  Future<void> _saveMediaMetadataToFirestore(MediaMessage media) async {
    try {
      final conversationRef = _firestore
          .collection('conversations')
          .doc(media.conversationId)
          .collection('media')
          .doc(media.id);

      await conversationRef.set(media.toFirestore());

      // Update conversation's lastMessage (for sorting)
      await _firestore
          .collection('conversations')
          .doc(media.conversationId)
          .set({
            'lastMessage': '[Media: ${media.fileName}]',
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastMediaType': media.fileType,
          }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  /// Delete media (soft delete)
  /// Only marks as deleted, actual file stays in R2 for 30 days
  Future<void> deleteMedia({
    required String conversationId,
    required String mediaId,
  }) async {
    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('media')
          .doc(mediaId)
          .update({'deletedAt': FieldValue.serverTimestamp()});

      // Clear local cache
      await _cacheService.deleteMediaCache(mediaId);
    } catch (e) {
      rethrow;
    }
  }

  /// Mark media as read by specific user
  Future<void> markMediaAsRead({
    required String conversationId,
    required String mediaId,
    required String userRole, // 'teacher', 'parent', 'student'
  }) async {
    try {
      final readField =
          'readBy${userRole[0].toUpperCase()}${userRole.substring(1)}';

      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('media')
          .doc(mediaId)
          .update({readField: true});
    } catch (e) {
      rethrow;
    }
  }

  /// Get media stream for a conversation (cost-optimized with pagination)
  /// Limits: 20 media items per query
  Stream<List<MediaMessage>> getMediaStream({
    required String conversationId,
    int limit = 20,
  }) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('media')
        .where('deletedAt', isNull: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => MediaMessage.fromFirestore(doc))
              .toList(),
        );
  }

  /// Paginate media with cursor
  Future<List<MediaMessage>> getMediaPaginated({
    required String conversationId,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      var query = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('media')
          .where('deletedAt', isNull: true)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => MediaMessage.fromFirestore(doc))
          .toList();
    } catch (e) {
      rethrow;
    }
  }
}
