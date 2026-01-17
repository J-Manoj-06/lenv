/**
 * Cloudflare Worker: Institute Announcement Auto-Delete (24 Hours)
 * 
 * This worker automatically deletes institute announcements after 24 hours.
 * Includes cleanup of:
 * - Firestore documents
 * - R2 images (all images from imageCaptions array)
 * - Views subcollection
 * 
 * Cost: FREE (Cloudflare Workers free tier)
 * Schedule: Runs every 1 hour (cron: "0 * * * *")
 * 
 * Deployment:
 *   wrangler deploy --config wrangler-institute-cleanup.jsonc
 * 
 * Environment Variables Required:
 *   - FIREBASE_PROJECT_ID: Your Firebase project ID
 *   - FIREBASE_API_KEY: Firebase Web API key
 *   - R2_BUCKET: R2 bucket binding (automatic)
 */

interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_API_KEY: string;
  R2_BUCKET: R2Bucket;
}

interface AnnouncementDoc {
  name: string; // Full document path
  fields: {
    createdAt?: { timestampValue?: string };
    imageCaptions?: { arrayValue?: { values?: any[] } };
    imageUrl?: { stringValue?: string };
  };
}

export default {
  /**
   * Scheduled cleanup - runs every 1 hour
   */
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    console.log('🗑️ [INSTITUTE] Starting scheduled cleanup of 24h+ announcements...');
    
    try {
      const result = await cleanupExpiredInstituteAnnouncements(env);
      console.log('✅ [INSTITUTE] Cleanup completed:', result);
    } catch (error) {
      console.error('❌ [INSTITUTE] Cleanup failed:', error);
    }
  },

  /**
   * HTTP endpoint for manual cleanup & testing
   */
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // Manual trigger
    if (request.method === 'POST') {
      try {
        const result = await cleanupExpiredInstituteAnnouncements(env);
        return new Response(JSON.stringify({
          success: true,
          ...result,
          message: `Deleted ${result.deletedCount} announcements and ${result.imagesDeleted} images`,
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      } catch (error: any) {
        console.error('Manual cleanup error:', error);
        return new Response(JSON.stringify({
          success: false,
          error: error.message,
        }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    // Health check
    return new Response(JSON.stringify({
      status: 'healthy',
      worker: 'institute-announcement-cleanup',
      message: 'POST to trigger manual cleanup',
      schedule: 'Every 1 hour',
      retention: '24 hours',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  },
};

/**
 * Main cleanup logic
 */
async function cleanupExpiredInstituteAnnouncements(env: Env): Promise<{
  deletedCount: number;
  imagesDeleted: number;
  viewsDeleted: number;
  totalExpired: number;
}> {
  const projectId = env.FIREBASE_PROJECT_ID;
  const apiKey = env.FIREBASE_API_KEY;

  // Calculate 24 hours ago
  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  
  console.log(`📅 Searching for announcements older than: ${twentyFourHoursAgo.toISOString()}`);

  // Query expired announcements
  const expiredDocs = await queryExpiredAnnouncements(projectId, apiKey, twentyFourHoursAgo);

  if (expiredDocs.length === 0) {
    console.log('✨ No expired announcements found');
    return {
      deletedCount: 0,
      imagesDeleted: 0,
      viewsDeleted: 0,
      totalExpired: 0,
    };
  }

  console.log(`📂 Found ${expiredDocs.length} expired announcements to delete`);

  let deletedCount = 0;
  let imagesDeleted = 0;
  let viewsDeleted = 0;

  // Process each announcement (limit to 50 per run)
  for (const doc of expiredDocs.slice(0, 50)) {
    try {
      const docId = doc.name.split('/').pop()!;
      console.log(`  Processing announcement: ${docId}`);

      // Delete all images from R2
      const imageUrls = extractImageUrls(doc);
      for (const imageUrl of imageUrls) {
        try {
          await deleteFromR2(env.R2_BUCKET, imageUrl);
          imagesDeleted++;
          console.log(`    🗑️  Deleted image from R2`);
        } catch (error) {
          console.error(`    ⚠️  Failed to delete image:`, error);
        }
      }

      // Delete views subcollection
      const viewsCount = await deleteViewsSubcollection(projectId, apiKey, docId);
      viewsDeleted += viewsCount;
      if (viewsCount > 0) {
        console.log(`    🗑️  Deleted ${viewsCount} view records`);
      }

      // Delete main announcement document
      await deleteFirestoreDocument(projectId, apiKey, docId);
      deletedCount++;
      console.log(`  ✅ Deleted announcement: ${docId}`);

    } catch (error) {
      console.error(`  ❌ Failed to delete announcement:`, error);
    }
  }

  return {
    deletedCount,
    imagesDeleted,
    viewsDeleted,
    totalExpired: expiredDocs.length,
  };
}

/**
 * Extract all image URLs from announcement document
 */
function extractImageUrls(doc: AnnouncementDoc): string[] {
  const urls: string[] = [];

  // Extract from imageCaptions array
  if (doc.fields.imageCaptions?.arrayValue?.values) {
    for (const item of doc.fields.imageCaptions.arrayValue.values) {
      if (item.mapValue?.fields?.url?.stringValue) {
        urls.push(item.mapValue.fields.url.stringValue);
      }
    }
  }

  // Extract legacy single imageUrl
  if (doc.fields.imageUrl?.stringValue && doc.fields.imageUrl.stringValue.trim() !== '') {
    urls.push(doc.fields.imageUrl.stringValue);
  }

  return urls;
}

/**
 * Query Firestore for expired announcements using REST API
 */
async function queryExpiredAnnouncements(
  projectId: string,
  apiKey: string,
  cutoffDate: Date
): Promise<AnnouncementDoc[]> {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery?key=${apiKey}`;

  const query = {
    structuredQuery: {
      from: [{ collectionId: 'institute_announcements' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'createdAt' },
          op: 'LESS_THAN',
          value: { timestampValue: cutoffDate.toISOString() },
        },
      },
      limit: 50,
    },
  };

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(query),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Firestore query failed: ${response.status} ${errorText}`);
  }

  const results = await response.json() as any[];
  return results
    .filter((r: any) => r.document)
    .map((r: any) => r.document as AnnouncementDoc);
}

/**
 * Delete views subcollection
 */
async function deleteViewsSubcollection(
  projectId: string,
  apiKey: string,
  announcementId: string
): Promise<number> {
  try {
    // List all view documents
    const listUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/institute_announcements/${announcementId}/views?key=${apiKey}`;
    
    const response = await fetch(listUrl);
    if (!response.ok) {
      return 0;
    }

    const data = await response.json() as any;
    if (!data.documents || data.documents.length === 0) {
      return 0;
    }

    // Delete each view document
    let deletedCount = 0;
    for (const viewDoc of data.documents.slice(0, 100)) { // Limit to 100
      try {
        const docPath = viewDoc.name;
        await fetch(`https://firestore.googleapis.com/v1/${docPath}?key=${apiKey}`, {
          method: 'DELETE',
        });
        deletedCount++;
      } catch (error) {
        console.error('Failed to delete view doc:', error);
      }
    }

    return deletedCount;
  } catch (error) {
    console.error('Failed to delete views subcollection:', error);
    return 0;
  }
}

/**
 * Delete Firestore document using REST API
 */
async function deleteFirestoreDocument(
  projectId: string,
  apiKey: string,
  documentId: string
): Promise<void> {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/institute_announcements/${documentId}?key=${apiKey}`;

  const response = await fetch(url, {
    method: 'DELETE',
  });

  if (!response.ok && response.status !== 404) {
    const errorText = await response.text();
    throw new Error(`Failed to delete document: ${response.status} ${errorText}`);
  }
}

/**
 * Delete file from R2 bucket
 */
async function deleteFromR2(bucket: R2Bucket, fileUrl: string): Promise<void> {
  try {
    // Extract key from URL
    // URL format: https://files.lenv1.tech/announcements/abc123.jpg
    // or: https://pub-xxxxx.r2.dev/announcements/abc123.jpg
    const url = new URL(fileUrl);
    const key = url.pathname.substring(1); // Remove leading /

    await bucket.delete(key);
    console.log(`      ✓ Deleted from R2: ${key}`);
  } catch (error: any) {
    // If file doesn't exist, that's OK
    if (error.message?.includes('NoSuchKey') || error.message?.includes('404')) {
      console.log(`      ⚠️  File not found in R2 (already deleted?)`);
    } else {
      throw error;
    }
  }
}
