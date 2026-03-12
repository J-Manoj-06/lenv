import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../config/cloudflare_config.dart';
import '../services/cloudflare_r2_service.dart';
import '../services/image_compression_service.dart';

/// Service for managing profile display pictures (DP) and group images.
///
/// Handles:
/// - Uploading user/group profile images to Cloudflare R2
/// - Saving/updating metadata in Firestore
/// - Removing images (Firestore + R2)
/// - Real-time stream of DP metadata
class ProfileDPService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImageCompressionService _compressionService = ImageCompressionService();

  late final CloudflareR2Service _r2Service = CloudflareR2Service(
    accountId: CloudflareConfig.accountId,
    bucketName: CloudflareConfig.bucketName,
    accessKeyId: CloudflareConfig.accessKeyId,
    secretAccessKey: CloudflareConfig.secretAccessKey,
    r2Domain: CloudflareConfig.r2Domain,
  );

  // ──────────────────────────────────────────────────────────────────────────
  // USER PROFILE DP
  // ──────────────────────────────────────────────────────────────────────────

  /// Upload a new profile picture for [userId].
  ///
  /// Steps:
  /// 1. Compress image to max 512px
  /// 2. Upload to Cloudflare R2 at `profile_pictures/{userId}/{imageId}.jpg`
  /// 3. Save metadata in Firestore `users/{userId}`
  ///
  /// Returns the public URL of the uploaded image.
  Future<String> uploadProfileImage({
    required String userId,
    required File imageFile,
    Function(int progress)? onProgress,
  }) async {
    try {
      // 1. Compress image
      onProgress?.call(5);
      final compressedBytes = await _compressionService.compressImage(
        imageFile,
        customMaxWidth: 512,
        customQuality: 75,
      );
      onProgress?.call(20);

      // 2. Generate unique image ID
      final imageId = 'dp_${DateTime.now().millisecondsSinceEpoch}';

      // 3. Generate signed upload URL
      final signedUrlData = await _r2Service.generateSignedUploadUrl(
        fileName: '$imageId.jpg',
        fileType: 'image/jpeg',
        validFor: const Duration(hours: 1),
      );
      onProgress?.call(30);

      // 4. Upload — use the URL and key that R2 actually assigned
      final signedUrl = signedUrlData['url'] as String;
      final actualKey =
          signedUrlData['key'] as String; // e.g. media/ts/dp_123.jpg

      // uploadFileWithSignedUrl returns the real public URL built from the signed path
      final publicUrl = await _r2Service.uploadFileWithSignedUrl(
        fileBytes: compressedBytes,
        signedUrl: signedUrl,
        contentType: 'image/jpeg',
        onProgress: (p) => onProgress?.call(30 + (p * 0.5).toInt()),
      );
      onProgress?.call(80);

      // 5. Save metadata in Firestore — store the actual R2 key for future deletion
      await _firestore.collection('users').doc(userId).set({
        'profileImageUrl': publicUrl,
        'profileImageId': imageId,
        'profileImageKey': actualKey,
        'profileImageUpdatedAt': FieldValue.serverTimestamp(),
        'hasProfileImage': true,
      }, SetOptions(merge: true));

      onProgress?.call(100);
      return publicUrl;
    } catch (e) {
      debugPrint('ProfileDPService: uploadProfileImage error: $e');
      rethrow;
    }
  }

  /// Remove profile picture for [userId].
  ///
  /// Deletes from Cloudflare R2 and clears Firestore metadata.
  Future<void> removeProfileImage({required String userId}) async {
    try {
      // Get current image key from Firestore
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      final imageKey = data?['profileImageKey'] as String?;

      // Delete from R2 if key exists
      if (imageKey != null && imageKey.isNotEmpty) {
        try {
          await _r2Service.deleteFile(key: imageKey);
        } catch (e) {
          // Log but don't fail if R2 delete fails
          debugPrint('ProfileDPService: R2 delete warning: $e');
        }
      }

      // Clear Firestore metadata
      await _firestore.collection('users').doc(userId).set({
        'profileImageUrl': null,
        'profileImageId': null,
        'profileImageKey': null,
        'profileImageUpdatedAt': FieldValue.serverTimestamp(),
        'hasProfileImage': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ProfileDPService: removeProfileImage error: $e');
      rethrow;
    }
  }

  /// Get current user DP metadata as a stream (real-time updates).
  Stream<Map<String, dynamic>?> watchUserDP(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((snap) {
      if (!snap.exists) return null;
      final d = snap.data();
      if (d == null) return null;
      return {
        'profileImageUrl': d['profileImageUrl'],
        'profileImageId': d['profileImageId'],
        'profileImageUpdatedAt': d['profileImageUpdatedAt'],
        'hasProfileImage': d['hasProfileImage'] ?? false,
        'name': d['name'] ?? '',
      };
    });
  }

  /// Fetch user DP URL once (non-streaming).
  Future<String?> getUserDPUrl(String userId) async {
    final data = await getUserDPData(userId);
    return data?['url'] as String?;
  }

  /// Fetch user DP URL + updatedAt timestamp once (non-streaming).
  Future<Map<String, dynamic>?> getUserDPData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        final d = doc.data();
        final url = d?['profileImageUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          return {
            'url': url,
            'updatedAt': d?['profileImageUpdatedAt']?.toString(),
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('ProfileDPService: getUserDPData error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP DP (TEACHERS ONLY)
  // ──────────────────────────────────────────────────────────────────────────

  /// Upload a group profile picture.
  ///
  /// Only teachers (group admins) should call this.
  /// Stores at `group_images/{groupId}/{imageId}.jpg`.
  Future<String> uploadGroupImage({
    required String groupId,
    required File imageFile,
    Function(int progress)? onProgress,
  }) async {
    try {
      // 1. Compress image to max 512px
      onProgress?.call(5);
      final compressedBytes = await _compressionService.compressImage(
        imageFile,
        customMaxWidth: 512,
        customQuality: 80,
      );
      onProgress?.call(20);

      // 2. Generate unique image ID
      final imageId = 'group_dp_${DateTime.now().millisecondsSinceEpoch}';

      // 3. Generate signed upload URL
      final signedUrlData = await _r2Service.generateSignedUploadUrl(
        fileName: '$imageId.jpg',
        fileType: 'image/jpeg',
        validFor: const Duration(hours: 1),
      );
      onProgress?.call(30);

      // 4. Upload — use the URL and key that R2 actually assigned
      final actualGroupKey = signedUrlData['key'] as String;
      final publicUrl = await _r2Service.uploadFileWithSignedUrl(
        fileBytes: compressedBytes,
        signedUrl: signedUrlData['url'] as String,
        contentType: 'image/jpeg',
        onProgress: (p) => onProgress?.call(30 + (p * 0.5).toInt()),
      );
      onProgress?.call(80);

      // 5. Save metadata in Firestore groups collection — store actual R2 key
      await _firestore.collection('groups').doc(groupId).set({
        'groupImageUrl': publicUrl,
        'groupImageId': imageId,
        'groupImageKey': actualGroupKey,
        'groupImageUpdatedAt': FieldValue.serverTimestamp(),
        'hasGroupImage': true,
      }, SetOptions(merge: true));

      // Also update teacher_groups docs that reference this group
      await _updateTeacherGroupImage(groupId, publicUrl);

      onProgress?.call(100);
      return publicUrl;
    } catch (e) {
      debugPrint('ProfileDPService: uploadGroupImage error: $e');
      rethrow;
    }
  }

  /// Remove group profile picture.
  Future<void> removeGroupImage({required String groupId}) async {
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      final data = doc.data();
      final imageKey = data?['groupImageKey'] as String?;

      if (imageKey != null && imageKey.isNotEmpty) {
        try {
          await _r2Service.deleteFile(key: imageKey);
        } catch (e) {
          debugPrint('ProfileDPService: R2 group delete warning: $e');
        }
      }

      await _firestore.collection('groups').doc(groupId).set({
        'groupImageUrl': null,
        'groupImageId': null,
        'groupImageKey': null,
        'groupImageUpdatedAt': FieldValue.serverTimestamp(),
        'hasGroupImage': false,
      }, SetOptions(merge: true));

      await _updateTeacherGroupImage(groupId, null);
    } catch (e) {
      debugPrint('ProfileDPService: removeGroupImage error: $e');
      rethrow;
    }
  }

  /// Get group DP metadata as a stream.
  Stream<Map<String, dynamic>?> watchGroupDP(String groupId) {
    return _firestore.collection('groups').doc(groupId).snapshots().map((snap) {
      if (!snap.exists) return null;
      final d = snap.data();
      if (d == null) return null;
      return {
        'groupImageUrl': d['groupImageUrl'],
        'groupImageId': d['groupImageId'],
        'groupImageUpdatedAt': d['groupImageUpdatedAt'],
        'hasGroupImage': d['hasGroupImage'] ?? false,
        'groupName': d['groupName'] ?? '',
      };
    });
  }

  /// Fetch group DP URL once.
  Future<String?> getGroupDPUrl(String groupId) async {
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      if (doc.exists) {
        return doc.data()?['groupImageUrl'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('ProfileDPService: getGroupDPUrl error: $e');
      return null;
    }
  }

  /// Update teacher_groups entries when group DP changes (best-effort).
  Future<void> _updateTeacherGroupImage(
    String groupId,
    String? imageUrl,
  ) async {
    try {
      // teacher_groups is indexed by teacherId; find all that reference [groupId]
      final snapshot = await _firestore
          .collection('teacher_groups')
          .where('groups.$groupId', isNull: false)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.set({
          'groups': {
            groupId: {'groupImageUrl': imageUrl},
          },
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Best-effort
    }
  }

  // ──────────────────────────────���───────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Validate image file type and size.
  ///
  /// Returns null if valid, error message if invalid.
  static String? validateImageFile(File file) {
    final path = file.path.toLowerCase();
    final allowed = ['.jpg', '.jpeg', '.png', '.webp'];
    final isAllowed = allowed.any((ext) => path.endsWith(ext));
    if (!isAllowed) {
      return 'Only JPG, PNG, and WEBP images are allowed.';
    }

    final fileSizeBytes = file.lengthSync();
    const maxBytes = 5 * 1024 * 1024; // 5 MB
    if (fileSizeBytes > maxBytes) {
      return 'Image must be smaller than 5 MB.';
    }
    return null;
  }

  /// Get user initials from name (up to 2 characters).
  static String getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts[0];
      return p.substring(0, p.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// Derive avatar background color from name (deterministic).
  static int getAvatarColor(String name) {
    if (name.isEmpty) return 0xFF607D8B; // default blue-grey
    const colors = [
      0xFF1565C0, // Blue
      0xFF2E7D32, // Green
      0xFF6A1B9A, // Purple
      0xFFC62828, // Red
      0xFF00838F, // Cyan
      0xFFE65100, // Orange
      0xFF4527A0, // Deep Purple
      0xFF00695C, // Teal
      0xFFAD1457, // Pink
      0xFF283593, // Indigo
    ];
    final hash = name.codeUnits.fold<int>(0, (prev, c) => prev + c);
    return colors[hash % colors.length];
  }
}
