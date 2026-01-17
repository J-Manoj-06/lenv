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
 * AUTO-DELETE INSTITUTE ANNOUNCEMENTS: Delete announcements after 24 hours
 * 
 * This function:
 * 1. Finds institute_announcements where createdAt < 24 hours ago
 * 2. Deletes all image files from Cloudflare R2 (from imageCaptions array)
 * 3. Deletes the views subcollection
 * 4. Deletes the announcement document from Firestore
 * 
 * Scheduled to run every hour for timely cleanup
 * 
 * Benefits:
 * - Keeps announcements fresh and relevant (only show latest 24h)
 * - Automatically removes old content without manual intervention
 * - Cleans up R2 storage to reduce costs
 * - Maintains clean database by removing expired data
 * 
 * Runs: Every 1 hour
 * Batch size: 50 announcements per run
 */
exports.deleteExpiredInstituteAnnouncements = functions
  .region(REGION)
  .pubsub.schedule('every 1 hours')
  .onRun(async (context) => {
    try {
      const twentyFourHoursAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 24 * 60 * 60 * 1000)
      );
      const batchSize = 50;
      let deletedCount = 0;
      let imagesDeleted = 0;

      console.log('🗑️ [INSTITUTE] Starting cleanup of 24h+ institute announcements...');

      // Query for announcements older than 24 hours
      const expiredAnnouncements = await db
        .collection('institute_announcements')
        .where('createdAt', '<', twentyFourHoursAgo)
        .limit(batchSize)
        .get();

      if (expiredAnnouncements.empty) {
        console.log('✨ [INSTITUTE] No expired announcements found');
        return { success: true, deletedCount: 0, imagesDeleted: 0 };
      }

      console.log(`📂 [INSTITUTE] Found ${expiredAnnouncements.size} expired announcements to delete`);

      for (const doc of expiredAnnouncements.docs) {
        const announcementData = doc.data();
        const announcementId = doc.id;

        try {
          console.log(`  Processing announcement: ${announcementId}`);

          // Delete all images from R2 if imageCaptions exist
          if (announcementData.imageCaptions && Array.isArray(announcementData.imageCaptions)) {
            for (const imageItem of announcementData.imageCaptions) {
              if (imageItem.url) {
                await deleteFromR2(imageItem.url);
                imagesDeleted++;
                console.log(`    🗑️  Deleted image from R2`);
              }
            }
          }

          // Also delete single imageUrl if it exists (legacy field)
          if (announcementData.imageUrl && announcementData.imageUrl.trim() !== '') {
            await deleteFromR2(announcementData.imageUrl);
            imagesDeleted++;
            console.log(`    🗑️  Deleted legacy image from R2`);
          }

          // Delete views subcollection
          const viewsSnapshot = await doc.ref.collection('views').limit(500).get();
          if (!viewsSnapshot.empty) {
            const viewsBatch = db.batch();
            viewsSnapshot.docs.forEach(viewDoc => {
              viewsBatch.delete(viewDoc.ref);
            });
            await viewsBatch.commit();
            console.log(`    🗑️  Deleted ${viewsSnapshot.size} view records`);
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

      console.log('✨ [INSTITUTE] Cleanup completed!');
      console.log(`   📊 Deleted announcements: ${deletedCount}`);
      console.log(`   📊 Deleted images: ${imagesDeleted}`);

      return {
        success: true,
        deletedCount,
        imagesDeleted,
      };
    } catch (error) {
      console.error('❌ [INSTITUTE] Error during cleanup:', error);
      return {
        success: false,
        error: error.message,
      };
    }
  });

/**
 * MANUAL TRIGGER: Delete expired institute announcements on demand
 * 
 * Callable function that can be triggered manually from admin panel or CLI
 * Useful for:
 * - Testing the cleanup logic
 * - Manual cleanup when needed
 * - Bulk deletion of old announcements
 * 
 * Usage: firebase functions:call deleteExpiredInstituteAnnouncementsManual
 */
exports.deleteExpiredInstituteAnnouncementsManual = functions
  .region(REGION)
  .https.onCall(async (data, context) => {
    // Optionally restrict to admin users only
    // if (!context.auth || !context.auth.token.admin) {
    //   throw new functions.https.HttpsError('permission-denied', 'Only admins can trigger cleanup');
    // }

    try {
      const twentyFourHoursAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 24 * 60 * 60 * 1000)
      );
      let deletedCount = 0;
      let imagesDeleted = 0;

      console.log('🗑️ [INSTITUTE MANUAL] Starting manual cleanup...');

      // Get ALL expired announcements (no limit for manual cleanup)
      const expiredAnnouncements = await db
        .collection('institute_announcements')
        .where('createdAt', '<', twentyFourHoursAgo)
        .get();

      if (expiredAnnouncements.empty) {
        console.log('✨ [INSTITUTE MANUAL] No expired announcements found');
        return { success: true, deletedCount: 0, imagesDeleted: 0 };
      }

      console.log(`📂 [INSTITUTE MANUAL] Found ${expiredAnnouncements.size} expired announcements`);

      for (const doc of expiredAnnouncements.docs) {
        const announcementData = doc.data();
        const announcementId = doc.id;

        try {
          // Delete all images from R2
          if (announcementData.imageCaptions && Array.isArray(announcementData.imageCaptions)) {
            for (const imageItem of announcementData.imageCaptions) {
              if (imageItem.url) {
                await deleteFromR2(imageItem.url);
                imagesDeleted++;
              }
            }
          }

          // Delete legacy single image
          if (announcementData.imageUrl && announcementData.imageUrl.trim() !== '') {
            await deleteFromR2(announcementData.imageUrl);
            imagesDeleted++;
          }

          // Delete views subcollection
          const viewsSnapshot = await doc.ref.collection('views').limit(500).get();
          if (!viewsSnapshot.empty) {
            const viewsBatch = db.batch();
            viewsSnapshot.docs.forEach(viewDoc => {
              viewsBatch.delete(viewDoc.ref);
            });
            await viewsBatch.commit();
          }

          // Delete the main announcement document
          await doc.ref.delete();
          deletedCount++;

        } catch (error) {
          console.error(`Failed to delete announcement ${announcementId}:`, error.message);
        }
      }

      console.log('✨ [INSTITUTE MANUAL] Cleanup completed!');
      console.log(`   📊 Deleted announcements: ${deletedCount}`);
      console.log(`   📊 Deleted images: ${imagesDeleted}`);

      return {
        success: true,
        deletedCount,
        imagesDeleted,
        message: `Successfully deleted ${deletedCount} announcements and ${imagesDeleted} images`,
      };
    } catch (error) {
      console.error('❌ [INSTITUTE MANUAL] Error:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

/**
 * Delete file from Cloudflare R2
 * @param {string} r2Url - Full URL to the file (e.g., https://files.lenv1.tech/announcements/file.jpg)
 */
async function deleteFromR2(r2Url) {
  try {
    // Extract object key from URL
    // URL format: https://files.lenv1.tech/announcements/file.jpg -> announcements/file.jpg
    const url = new URL(r2Url);
    const objectKey = url.pathname.substring(1); // Remove leading /

    const command = new DeleteObjectCommand({
      Bucket: process.env.CLOUDFLARE_R2_BUCKET_NAME,
      Key: objectKey,
    });

    await r2Client.send(command);
    console.log(`      ✓ Deleted from R2: ${objectKey}`);
  } catch (error) {
    // If file doesn't exist, that's OK - might have been manually deleted
    if (error.name === 'NoSuchKey' || error.$metadata?.httpStatusCode === 404) {
      console.log(`      ⚠️  File not found in R2 (already deleted?): ${r2Url}`);
    } else {
      throw error;
    }
  }
}
