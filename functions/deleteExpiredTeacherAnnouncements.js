'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { S3Client, DeleteObjectCommand } = require('@aws-sdk/client-s3');

// Initialize Admin SDK
try {
  admin.app();
} catch (e) {
  admin.initializeApp();
}

const db = admin.firestore();
const REGION = 'us-central1';

// Initialize R2 client
const r2Client = new S3Client({
  region: 'auto',
  endpoint: process.env.CLOUDFLARE_R2_ENDPOINT,
  credentials: {
    accessKeyId: process.env.CLOUDFLARE_R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY,
  },
});

/**
 * TEACHER ANNOUNCEMENT AUTO-DELETE: 24-hour ephemeral teacher announcements
 * 
 * This function:
 * 1. Finds teacher announcements (class_highlights) where expiresAt < now
 * 2. Deletes ALL images from imageCaptions array from Cloudflare R2
 * 3. Deletes legacy single imageUrl from R2 (if exists)
 * 4. Deletes the Firestore document and all metadata
 * 
 * Scheduled to run every hour for timely cleanup
 * 
 * Cost Impact:
 * - Reduces R2 storage costs by removing ephemeral media
 * - Reduces Firestore storage by removing expired documents
 * - Automatic cleanup = no manual intervention needed
 * 
 * Runs: Every 1 hour
 * Batch size: 50 documents per run
 */
exports.deleteExpiredTeacherAnnouncements = functions
  .region(REGION)
  .pubsub.schedule('every 1 hours')
  .onRun(async (context) => {
    try {
      const now = admin.firestore.Timestamp.now();
      const batchSize = 50;
      let deletedCount = 0;
      let imagesDeleted = 0;

      console.log('🗑️ [TEACHER-ANNOUNCEMENTS] Starting cleanup of expired teacher announcements...');

      // Process in batches to avoid memory issues
      let hasMore = true;
      while (hasMore) {
        const expiredQuery = await db
          .collection('class_highlights')
          .where('expiresAt', '<', now)
          .limit(batchSize)
          .get();

        if (expiredQuery.empty) {
          hasMore = false;
          break;
        }

        console.log(`📂 [TEACHER-ANNOUNCEMENTS] Found ${expiredQuery.size} expired announcements`);

        // Delete each expired announcement
        for (const doc of expiredQuery.docs) {
          const announcementData = doc.data();
          const announcementId = doc.id;

          try {
            // Delete all images from R2
            if (announcementData.imageCaptions && Array.isArray(announcementData.imageCaptions)) {
              for (const imageItem of announcementData.imageCaptions) {
                if (imageItem.url) {
                  await deleteFromR2(imageItem.url);
                  imagesDeleted++;
                  console.log(`  🖼️  Deleted image from R2: ${imageItem.url.split('/').pop()}`);
                }
              }
            }

            // Delete legacy single image
            if (announcementData.imageUrl && announcementData.imageUrl.trim() !== '') {
              await deleteFromR2(announcementData.imageUrl);
              imagesDeleted++;
              console.log(`  🖼️  Deleted legacy image from R2: ${announcementData.imageUrl.split('/').pop()}`);
            }

            // Delete the main announcement document
            await doc.ref.delete();
            deletedCount++;
            console.log(`  ✅ Deleted announcement: ${announcementId}`);

          } catch (error) {
            console.error(`  ❌ Failed to delete announcement ${announcementId}:`, error.message);
            // Continue with next document
          }
        }

        // If we got fewer than batchSize, we're done
        if (expiredQuery.size < batchSize) {
          hasMore = false;
        }
      }

      console.log('✨ [TEACHER-ANNOUNCEMENTS] Cleanup completed!');
      console.log(`   📊 Deleted announcements: ${deletedCount}`);
      console.log(`   🖼️  Deleted images: ${imagesDeleted}`);

      return {
        success: true,
        deletedAnnouncements: deletedCount,
        deletedImages: imagesDeleted,
      };
    } catch (error) {
      console.error('❌ [TEACHER-ANNOUNCEMENTS] Error during cleanup:', error);
      return {
        success: false,
        error: error.message,
      };
    }
  });

/**
 * Delete file from Cloudflare R2
 * @param {string} r2Url - Full URL (e.g., https://files.lenv1.tech/class_highlights/file.jpg)
 */
async function deleteFromR2(r2Url) {
  try {
    if (!r2Url || typeof r2Url !== 'string' || r2Url.trim() === '') {
      return; // Skip empty URLs
    }

    // Extract object key from URL
    // URL format: https://files.lenv1.tech/class_highlights/file.jpg -> class_highlights/file.jpg
    const url = new URL(r2Url);
    const objectKey = url.pathname.substring(1); // Remove leading /

    if (!objectKey) {
      console.warn(`    ⚠️  Invalid R2 URL (no path): ${r2Url}`);
      return;
    }

    const command = new DeleteObjectCommand({
      Bucket: process.env.CLOUDFLARE_R2_BUCKET_NAME,
      Key: objectKey,
    });

    await r2Client.send(command);
    console.log(`    ✓ Deleted from R2: ${objectKey}`);
  } catch (error) {
    // If file doesn't exist, that's OK - might have been manually deleted
    if (error.name === 'NoSuchKey' || error.$metadata?.httpStatusCode === 404) {
      console.log(`    ⚠️  File not found in R2 (already deleted?): ${r2Url}`);
    } else {
      console.error(`    ❌ Error deleting from R2: ${error.message}`);
      // Don't throw - continue with other deletions
    }
  }
}

/**
 * MANUAL: Cleanup function (can be triggered manually via HTTP)
 * Use this for testing or manual cleanup runs
 */
exports.deleteExpiredTeacherAnnouncementsManual = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    // Verify user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    console.log('🔧 [MANUAL] Running manual teacher announcement cleanup...');

    try {
      const now = admin.firestore.Timestamp.now();
      const expiredDocs = await db
        .collection('class_highlights')
        .where('expiresAt', '<', now)
        .get();

      if (expiredDocs.empty) {
        return {
          success: true,
          message: 'No expired teacher announcements found',
          deletedCount: 0,
          deletedImages: 0,
        };
      }

      let deletedCount = 0;
      let imagesDeleted = 0;

      for (const doc of expiredDocs.docs) {
        const announcementData = doc.data();

        // Delete all images
        if (announcementData.imageCaptions && Array.isArray(announcementData.imageCaptions)) {
          for (const imageItem of announcementData.imageCaptions) {
            if (imageItem.url) {
              await deleteFromR2(imageItem.url);
              imagesDeleted++;
            }
          }
        }

        // Delete legacy image
        if (announcementData.imageUrl && announcementData.imageUrl.trim() !== '') {
          await deleteFromR2(announcementData.imageUrl);
          imagesDeleted++;
        }

        // Delete document
        await doc.ref.delete();
        deletedCount++;
      }

      console.log(`✅ [MANUAL] Cleanup completed: ${deletedCount} announcements, ${imagesDeleted} images`);

      return {
        success: true,
        deletedCount,
        deletedImages: imagesDeleted,
        message: `Successfully deleted ${deletedCount} announcements and ${imagesDeleted} images`,
      };
    } catch (error) {
      console.error('❌ [MANUAL] Error during cleanup:', error);
      throw new functions.https.HttpsError(
        'internal',
        `Error deleting teacher announcements: ${error.message}`
      );
    }
  });
