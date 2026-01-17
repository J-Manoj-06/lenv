import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// Service to handle auto-deletion of expired institute announcements
///
/// This runs CLIENT-SIDE in the Flutter app, no external workers needed!
/// When the app loads announcements, it automatically cleans up expired ones.
class InstituteAnnouncementCleanupService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check and delete expired announcements when loading
  /// Call this in your dashboard or viewer screen's initState
  static Future<void> cleanupExpiredAnnouncements() async {
    try {
      final now = DateTime.now();

      // Query announcements that have expired
      final expiredQuery = await _firestore
          .collection('institute_announcements')
          .where('expiresAt', isLessThan: Timestamp.fromDate(now))
          .limit(20) // Process 20 at a time
          .get();

      if (expiredQuery.docs.isEmpty) {
        print('✅ No expired announcements to clean up');
        return;
      }

      print(
        '🗑️ Found ${expiredQuery.docs.length} expired announcements to delete',
      );

      // Delete each expired announcement
      for (final doc in expiredQuery.docs) {
        await _deleteAnnouncement(doc.id, doc.data());
      }

      print('✅ Cleanup completed');
    } catch (e) {
      print('❌ Cleanup error: $e');
    }
  }

  /// Delete a single announcement with all its data
  static Future<void> _deleteAnnouncement(
    String announcementId,
    Map<String, dynamic> data,
  ) async {
    try {
      print('  Deleting announcement: $announcementId');

      // 1. Delete images from R2
      final imageCaptions = data['imageCaptions'] as List?;
      if (imageCaptions != null) {
        for (final item in imageCaptions) {
          final url = item['url'] as String?;
          if (url != null) {
            await _deleteImageFromR2(url);
          }
        }
      }

      // Legacy single image
      final imageUrl = data['imageUrl'] as String?;
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        await _deleteImageFromR2(imageUrl);
      }

      // 2. Delete views subcollection (batch delete)
      final viewsQuery = await _firestore
          .collection('institute_announcements')
          .doc(announcementId)
          .collection('views')
          .limit(100)
          .get();

      if (viewsQuery.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final viewDoc in viewsQuery.docs) {
          batch.delete(viewDoc.reference);
        }
        await batch.commit();
        print('    🗑️  Deleted ${viewsQuery.docs.length} view records');
      }

      // 3. Delete main announcement document
      await _firestore
          .collection('institute_announcements')
          .doc(announcementId)
          .delete();

      print('  ✅ Deleted announcement: $announcementId');
    } catch (e) {
      print('  ❌ Failed to delete announcement $announcementId: $e');
    }
  }

  /// Delete image from R2 via your Cloudflare Worker
  static Future<void> _deleteImageFromR2(String imageUrl) async {
    try {
      // Extract filename from URL
      final uri = Uri.parse(imageUrl);
      final key = uri.path.substring(1); // Remove leading /

      // Call your existing Cloudflare Worker delete endpoint
      final workerUrl =
          'https://files.lenv1.tech/delete'; // Adjust to your worker URL

      final response = await http.post(
        Uri.parse(workerUrl),
        headers: {'Content-Type': 'application/json'},
        body: '{"key": "$key"}',
      );

      if (response.statusCode == 200) {
        print('      ✓ Deleted from R2: $key');
      } else {
        print('      ⚠️  R2 delete failed: ${response.statusCode}');
      }
    } catch (e) {
      print('      ⚠️  R2 delete error: $e');
      // Don't throw - image might be already deleted
    }
  }

  /// ALTERNATIVE: Delete using R2 SDK (if you have it in Flutter)
  /// This avoids the HTTP call if you have direct R2 access
  static Future<void> _deleteImageFromR2Direct(String imageUrl) async {
    // If you implement R2 SDK in Flutter, use it here
    // For now, use the HTTP method above
  }
}
