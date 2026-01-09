/// Media Upload Type Configuration
///
/// This file documents the mediaType parameter usage for the MediaUploadService.
///
/// IMPORTANT: mediaType determines the deletion policy:
/// - 'announcement': Auto-deleted after 24 hours (WhatsApp-style ephemeral media)
/// - 'message': Permanent storage (never auto-deleted)
/// - 'community': Permanent storage (never auto-deleted)
///
/// Usage Examples:
///
/// 1. For Announcements (24-hour auto-delete):
/// ```dart
/// final media = await mediaUploadService.uploadMedia(
///   file: file,
///   conversationId: announcementId,
///   senderId: currentUser.uid,
///   senderRole: userRole,
///   mediaType: 'announcement', // ← Auto-deleted after 24 hours
/// );
/// ```
///
/// 2. For Messages (permanent):
/// ```dart
/// final media = await mediaUploadService.uploadMedia(
///   file: file,
///   conversationId: conversationId,
///   senderId: currentUser.uid,
///   senderRole: userRole,
///   mediaType: 'message', // ← Permanent (default)
/// );
/// ```
///
/// 3. For Community Posts (permanent):
/// ```dart
/// final media = await mediaUploadService.uploadMedia(
///   file: file,
///   conversationId: communityId,
///   senderId: currentUser.uid,
///   senderRole: userRole,
///   mediaType: 'community', // ← Permanent
/// );
/// ```
///
/// Cloud Function:
/// The `deleteExpiredMediaAnnouncements` Cloud Function runs every hour to:
/// 1. Find MediaMessage documents where mediaType='announcement' and createdAt < 24 hours ago
/// 2. Delete the file from Cloudflare R2
/// 3. Delete the thumbnail from R2 (if exists)
/// 4. Soft-delete the Firestore document (sets deletedAt timestamp)
///
/// Cost Optimization:
/// - Announcement media is automatically cleaned up after 24 hours
/// - Message and community media remains permanently for user access
/// - Reduces R2 storage costs while maintaining important user content
/// - Firestore soft-delete allows audit trail and recovery if needed
library;

// This file is documentation only - no code implementation needed
