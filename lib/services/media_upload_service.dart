import 'dart:async';
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

      onProgress?.call(15);

      // Upload to R2 using signed URL with smooth progress
      final r2Url = await _r2Service.uploadFileWithSignedUrl(
        fileBytes: uploadBytes,
        signedUrl: signedUrlResponse['url'],
        contentType: mimeType,
        onProgress: (progress) {
          // Scale progress from 20-80 range and emit smoothly
          // progress comes as 0-100, we scale to 20-80
          final scaledProgress = 20 + ((progress / 100) * 60).toInt();
          onProgress?.call(scaledProgress);
        },
      );

      // Generate thumbnail URL if image (upload separately)
      String? thumbnailUrl;
      if (compressedThumbnail != null && mimeType.startsWith('image/')) {
        // Smooth progress from 80 to 85 for thumbnail upload
        for (int i = 80; i <= 85; i++) {
          onProgress?.call(i);
          await Future.delayed(Duration(milliseconds: 50));
        }
        thumbnailUrl = await _uploadThumbnail(
          thumbnailBytes: compressedThumbnail,
          mediaId: DateTime.now().millisecondsSinceEpoch.toString(),
        );
      }

      // Smooth progress from 85 to 95 for metadata save
      for (int i = 85; i <= 95; i++) {
        onProgress?.call(i);
        await Future.delayed(Duration(milliseconds: 30));
      }

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

      // Smooth progress from 95 to 100 for completion
      for (int i = 95; i <= 100; i++) {
        onProgress?.call(i);
        await Future.delayed(Duration(milliseconds: 20));
      }

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

    // Check file type (images, documents, or audio)
    final isImage = mimeType.startsWith('image/');
    final isAudio = mimeType.startsWith('audio/');

    // Document types: Word, Excel, PowerPoint, etc.
    final isDocument =
        mimeType == 'application/pdf' ||
        mimeType == 'application/msword' || // .doc
        mimeType ==
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document' || // .docx
        mimeType == 'application/vnd.ms-excel' || // .xls
        mimeType ==
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' || // .xlsx
        mimeType == 'application/vnd.ms-powerpoint' || // .ppt
        mimeType ==
            'application/vnd.openxmlformats-officedocument.presentationml.presentation' || // .pptx
        mimeType == 'text/plain' || // .txt
        mimeType == 'text/csv' || // .csv
        mimeType == 'application/rtf' || // .rtf
        mimeType == 'application/vnd.oasis.opendocument.text' || // .odt
        mimeType == 'application/vnd.oasis.opendocument.spreadsheet' || // .ods
        mimeType == 'application/vnd.oasis.opendocument.presentation'; // .odp

    if (!isImage && !isDocument && !isAudio) {
      throw Exception('Only images, documents, and audio files are supported');
    }

    // Check size for all other document types (not PDF, already checked)
    if (isDocument &&
        mimeType != 'application/pdf' &&
        fileBytes.length > MAX_PDF_SIZE) {
      throw Exception(
        'Document too large. Max: ${MAX_PDF_SIZE ~/ (1024 * 1024)}MB',
      );
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

      // Return original image without resizing to preserve quality
      return {
        'bytes': imageBytes,
        'width': originalImage.width,
        'height': originalImage.height,
      };
    } catch (e) {
      return {'bytes': imageBytes, 'width': null, 'height': null};
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
