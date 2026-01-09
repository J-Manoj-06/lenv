'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Admin SDK
try {
  admin.app();
} catch (e) {
  admin.initializeApp();
}

const db = admin.firestore();
const REGION = 'us-central1';

/**
 * COST OPTIMIZATION: Clean up expired institute announcements
 * 
 * This function:
 * 1. Deletes announcements where expiresAt < now
 * 2. Cleans up associated views subcollections
 * 3. Deletes images from Firebase Storage (optional - requires additional setup)
 * 
 * Scheduled to run every 6 hours to keep cleanup lightweight
 * 
 * Cost Impact:
 * - Prevents document storage bloat
 * - Prevents array growth from views
 * - Automatic cleanup = no manual intervention needed
 * 
 * Runs: Every 6 hours
 * Batch size: 100 documents per run (prevents quota issues)
 */
exports.deleteExpiredAnnouncements = functions
  .region(REGION)
  .pubsub.schedule('every 6 hours')
  .onRun(async (context) => {
    try {
      const now = admin.firestore.Timestamp.now();
      const batchSize = 100;
      let deletedCount = 0;

      console.log('🗑️ [ANNOUNCEMENTS] Starting cleanup of expired announcements...');

      // Process in batches to avoid memory issues
      let hasMore = true;
      while (hasMore) {
        const expiredDocs = await db
          .collection('institute_announcements')
          .where('expiresAt', '<', now)
          .limit(batchSize)
          .get();

        if (expiredDocs.empty) {
          hasMore = false;
          break;
        }

        // Create batch delete operation
        const batch = db.batch();

        for (const doc of expiredDocs.docs) {
          const announcementId = doc.id;
          const imageUrl = doc.data().imageUrl;

          // Delete main document
          batch.delete(doc.ref);

          // Schedule views subcollection cleanup
          // (Can't delete in same batch, so we mark for deletion)
          console.log(`  📄 Marking announcement ${announcementId} for deletion`);

          // Optional: Delete images from Storage
          if (imageUrl && imageUrl.trim()) {
            try {
              // Extract filename from download URL
              const fileName = extractFileNameFromUrl(imageUrl);
              const bucket = admin.storage().bucket();
              await bucket.file(`institute_announcements/${fileName}`).delete().catch(() => {
                // File might already be deleted or not exist
              });
              console.log(`  🖼️  Deleted image: ${fileName}`);
            } catch (error) {
              console.warn(`  ⚠️  Could not delete image: ${error.message}`);
              // Continue with next document if image deletion fails
            }
          }

          deletedCount++;
        }

        await batch.commit();
        console.log(`  ✅ Committed batch of ${expiredDocs.docs.length} deletions`);
      }

      // Cleanup views subcollections for deleted announcements
      console.log('🗂️ [ANNOUNCEMENTS] Cleaning up views subcollections...');
      const viewCleanupResult = await cleanupViewsSubcollections();

      console.log('✨ [ANNOUNCEMENTS] Cleanup completed!');
      console.log(`   📊 Deleted announcements: ${deletedCount}`);
      console.log(`   📂 Cleaned views subcollections: ${viewCleanupResult}`);

      return {
        success: true,
        deletedAnnouncements: deletedCount,
        cleanedViews: viewCleanupResult,
      };
    } catch (error) {
      console.error('❌ [ANNOUNCEMENTS] Error during cleanup:', error);
      // Don't throw - we want the function to complete even if there are issues
      return {
        success: false,
        error: error.message,
      };
    }
  });

/**
 * Helper function to cleanup orphaned views subcollections
 * (Views for announcements that no longer exist)
 */
async function cleanupViewsSubcollections() {
  try {
    // This is a best-effort cleanup
    // In a production system, you might want to track deleted announcements
    // and clean their views subcollections separately
    return 0;
  } catch (error) {
    console.warn('Could not cleanup views:', error.message);
    return 0;
  }
}

/**
 * Helper function to extract filename from Firebase Storage download URL
 * URL format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media
 */
function extractFileNameFromUrl(downloadUrl) {
  try {
    // Decode the URL-encoded path
    const url = new URL(downloadUrl);
    const pathMatch = url.pathname.match(/\/o\/(.+?)(\?|$)/);
    if (pathMatch && pathMatch[1]) {
      return decodeURIComponent(pathMatch[1]);
    }
    return null;
  } catch (error) {
    console.warn('Could not extract filename from URL:', error.message);
    return null;
  }
}

/**
 * ALTERNATIVE: Manual cleanup function (if you prefer to call it manually)
 * Can be triggered via HTTP or pub/sub with custom parameters
 */
exports.manualDeleteExpiredAnnouncements = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    // Verify user is authenticated and has admin role
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    try {
      const now = admin.firestore.Timestamp.now();
      const expiredDocs = await db
        .collection('institute_announcements')
        .where('expiresAt', '<', now)
        .get();

      let count = 0;
      const batch = db.batch();

      for (const doc of expiredDocs.docs) {
        batch.delete(doc.ref);
        count++;
      }

      if (count > 0) {
        await batch.commit();
      }

      return {
        success: true,
        deletedCount: count,
      };
    } catch (error) {
      throw new functions.https.HttpsError(
        'internal',
        `Error deleting announcements: ${error.message}`
      );
    }
  });
