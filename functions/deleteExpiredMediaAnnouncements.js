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
 * COST OPTIMIZATION: Auto-delete announcement media after 24 hours
 * 
 * This function:
 * 1. Finds MediaMessage documents where mediaType='announcement' and createdAt < 24 hours ago
 * 2. Deletes the file from Cloudflare R2
 * 3. Deletes the thumbnail from R2 (if exists)
 * 4. Soft-deletes the Firestore document (sets deletedAt timestamp)
 * 
 * Scheduled to run every hour for timely cleanup
 * 
 * Cost Impact:
 * - Reduces R2 storage costs by removing ephemeral media
 * - Marks Firestore documents as deleted (soft delete for audit trail)
 * - WhatsApp-style 24-hour auto-deletion for announcements
 * 
 * Runs: Every 1 hour
 * Batch size: 50 documents per run
 */
exports.deleteExpiredMediaAnnouncements = functions
  .region(REGION)
  .pubsub.schedule('every 1 hours')
  .onRun(async (context) => {
    try {
      const twentyFourHoursAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 24 * 60 * 60 * 1000)
      );
      const batchSize = 50;
      let deletedCount = 0;

      console.log('🗑️ [MEDIA] Starting cleanup of 24h+ announcement media...');

      // Query for announcement media older than 24 hours that haven't been deleted yet
      const expiredMedia = await db
        .collection('media_messages')
        .where('mediaType', '==', 'announcement')
        .where('createdAt', '<', twentyFourHoursAgo)
        .where('deletedAt', '==', null)
        .limit(batchSize)
        .get();

      if (expiredMedia.empty) {
        console.log('✨ [MEDIA] No expired announcement media found');
        return { success: true, deletedCount: 0 };
      }

      console.log(`📂 [MEDIA] Found ${expiredMedia.size} expired announcement media to delete`);

      const batch = db.batch();

      for (const doc of expiredMedia.docs) {
        const mediaData = doc.data();
        const mediaId = doc.id;

        try {
          // Delete main media file from R2
          if (mediaData.r2Url) {
            await deleteFromR2(mediaData.r2Url);
            console.log(`  🗑️  Deleted R2 file: ${mediaData.fileName}`);
          }

          // Delete thumbnail from R2 if exists
          if (mediaData.thumbnailUrl && mediaData.thumbnailUrl.startsWith('http')) {
            await deleteFromR2(mediaData.thumbnailUrl);
            console.log(`  🗑️  Deleted R2 thumbnail: ${mediaData.fileName}`);
          }

          // Soft delete in Firestore (set deletedAt timestamp)
          batch.update(doc.ref, {
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          deletedCount++;
        } catch (error) {
          console.error(`  ❌ Failed to delete media ${mediaId}:`, error.message);
          // Continue with next document
        }
      }

      await batch.commit();
      console.log('✅ [MEDIA] Batch commit completed');

      console.log('✨ [MEDIA] Cleanup completed!');
      console.log(`   📊 Deleted announcement media: ${deletedCount}`);

      return {
        success: true,
        deletedCount,
      };
    } catch (error) {
      console.error('❌ [MEDIA] Error during cleanup:', error);
      return {
        success: false,
        error: error.message,
      };
    }
  });

/**
 * Delete file from Cloudflare R2
 * @param {string} r2Url - Worker URL (e.g., https://files.lenv1.tech/media/file.jpg)
 */
async function deleteFromR2(r2Url) {
  try {
    // Extract object key from URL
    // URL format: https://files.lenv1.tech/media/file.jpg -> media/file.jpg
    const url = new URL(r2Url);
    const objectKey = url.pathname.substring(1); // Remove leading /

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
      throw error;
    }
  }
}

/**
 * Optional: Hard delete old soft-deleted media (after 30 days)
 * This removes the Firestore document completely for cost optimization
 */
exports.hardDeleteOldMediaMessages = functions
  .region(REGION)
  .pubsub.schedule('every 24 hours')
  .onRun(async (context) => {
    try {
      const thirtyDaysAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
      );
      const batchSize = 100;

      console.log('🗑️ [MEDIA] Hard deleting 30+ day old soft-deleted media...');

      const oldDeletedMedia = await db
        .collection('media_messages')
        .where('deletedAt', '<', thirtyDaysAgo)
        .limit(batchSize)
        .get();

      if (oldDeletedMedia.empty) {
        console.log('✨ [MEDIA] No old deleted media found');
        return { success: true, hardDeletedCount: 0 };
      }

      const batch = db.batch();
      oldDeletedMedia.docs.forEach(doc => {
        batch.delete(doc.ref);
      });

      await batch.commit();
      console.log(`✅ [MEDIA] Hard deleted ${oldDeletedMedia.size} old media documents`);

      return {
        success: true,
        hardDeletedCount: oldDeletedMedia.size,
      };
    } catch (error) {
      console.error('❌ [MEDIA] Error during hard delete:', error);
      return {
        success: false,
        error: error.message,
      };
    }
  });
