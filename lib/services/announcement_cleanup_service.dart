import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client-side cleanup service for expired announcements
/// Runs when principal/admin opens the app
/// FREE alternative to Firebase scheduled Cloud Functions
class AnnouncementCleanupService {
  static const String _lastCleanupKey = 'last_announcement_cleanup';
  
  /// Clean up expired institute announcements
  /// Runs once per day maximum
  static Future<void> cleanupExpiredAnnouncements({
    bool force = false,
  }) async {
    try {
      // Check if already cleaned today (unless forced)
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final lastCleanup = prefs.getString(_lastCleanupKey);
        final today = DateTime.now().toIso8601String().split('T')[0];
        
        if (lastCleanup == today) {
          print('ℹ️ Announcements already cleaned today');
          return;
        }
      }
      
      final now = Timestamp.now();
      
      // Query expired announcements (limit to prevent long operations)
      final expired = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .where('expiresAt', isLessThan: now)
          .limit(50) // Clean 50 at a time to avoid timeout
          .get();
      
      if (expired.docs.isEmpty) {
        print('ℹ️ No expired announcements found');
        return;
      }
      
      // Delete in batch
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in expired.docs) {
        batch.delete(doc.reference);
        
        // Also delete views subcollection (optional - for thorough cleanup)
        // Note: Subcollection deletion requires additional queries
      }
      
      await batch.commit();
      print('🗑️ Cleaned up ${expired.docs.length} expired announcements');
      
      // Mark cleanup as done today
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      await prefs.setString(_lastCleanupKey, today);
    } catch (e) {
      print('⚠️ Announcement cleanup error: $e');
      // Silent fail - cleanup is not critical for app functionality
    }
  }
  
  /// Clean up expired teacher status posts
  static Future<void> cleanupExpiredStatus({
    bool force = false,
  }) async {
    try {
      // Check if already cleaned today
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final lastCleanup = prefs.getString('last_status_cleanup');
        final today = DateTime.now().toIso8601String().split('T')[0];
        
        if (lastCleanup == today) {
          print('ℹ️ Status posts already cleaned today');
          return;
        }
      }
      
      final now = Timestamp.now();
      
      final expired = await FirebaseFirestore.instance
          .collection('class_highlights')
          .where('expiresAt', isLessThan: now)
          .limit(50)
          .get();
      
      if (expired.docs.isEmpty) {
        print('ℹ️ No expired status posts found');
        return;
      }
      
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in expired.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('🗑️ Cleaned up ${expired.docs.length} expired status posts');
      
      // Mark cleanup as done today
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      await prefs.setString('last_status_cleanup', today);
    } catch (e) {
      print('⚠️ Status cleanup error: $e');
      // Silent fail
    }
  }
  
  /// Run all cleanup tasks
  /// Call this once per day when principal/admin logs in
  static Future<void> runAllCleanup({bool force = false}) async {
    print('🧹 Starting cleanup tasks...');
    
    await Future.wait([
      cleanupExpiredAnnouncements(force: force),
      cleanupExpiredStatus(force: force),
    ]);
    
    print('✅ Cleanup tasks completed');
  }
  
  /// Force cleanup (ignores daily limit)
  /// Useful for manual trigger or testing
  static Future<void> forceCleanup() async {
    await runAllCleanup(force: true);
  }
  
  /// Check if cleanup is needed today
  static Future<bool> needsCleanup() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCleanup = prefs.getString(_lastCleanupKey);
    final today = DateTime.now().toIso8601String().split('T')[0];
    return lastCleanup != today;
  }
}
