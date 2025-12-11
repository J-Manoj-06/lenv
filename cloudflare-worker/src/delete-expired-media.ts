/**
 * Cloudflare Worker: Delete Expired Announcement Media (24-hour auto-deletion)
 * 
 * This scheduled worker:
 * 1. Queries Firestore for announcement media older than 24 hours
 * 2. Deletes files from R2 (main file + thumbnail)
 * 3. Soft-deletes Firestore documents (sets deletedAt)
 * 
 * Scheduled to run every hour via Cloudflare Cron Triggers
 */

interface Env {
  R2_BUCKET: R2Bucket;
  
  // Firestore REST API credentials
  FIREBASE_PROJECT_ID: string;
  FIREBASE_API_KEY: string;
  
  // Optional: Service account for admin access
  FIREBASE_CLIENT_EMAIL?: string;
  FIREBASE_PRIVATE_KEY?: string;
}

interface MediaMessage {
  id: string;
  mediaType: string;
  createdAt: { _seconds: number; _nanoseconds: number };
  deletedAt: any;
  r2Url: string;
  thumbnailUrl?: string;
  fileName: string;
}

/**
 * Scheduled handler - runs every hour
 */
export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    console.log('🗑️ [MEDIA] Starting cleanup of 24h+ announcement media...');
    
    try {
      const deletedCount = await deleteExpiredMedia(env);
      console.log(`✨ [MEDIA] Cleanup completed! Deleted: ${deletedCount}`);
    } catch (error) {
      console.error('❌ [MEDIA] Error during cleanup:', error);
    }
  },

  /**
   * HTTP handler for manual triggering
   */
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // Check if this is a manual trigger request
    const url = new URL(request.url);
    
    if (url.pathname === '/trigger-cleanup' && request.method === 'POST') {
      // Simple auth check
      const authHeader = request.headers.get('Authorization');
      if (!authHeader || authHeader !== `Bearer ${env.FIREBASE_API_KEY}`) {
        return new Response('Unauthorized', { status: 401 });
      }

      // Trigger cleanup manually
      try {
        const deletedCount = await deleteExpiredMedia(env);
        return new Response(JSON.stringify({
          success: true,
          deletedCount,
          timestamp: new Date().toISOString()
        }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' }
        });
      } catch (error: any) {
        return new Response(JSON.stringify({
          success: false,
          error: error.message
        }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    return new Response('Media Deletion Worker - Use POST /trigger-cleanup to manually trigger', {
      status: 200
    });
  }
};

/**
 * Main deletion logic
 */
async function deleteExpiredMedia(env: Env): Promise<number> {
  const twentyFourHoursAgo = Date.now() - (24 * 60 * 60 * 1000);
  let deletedCount = 0;

  try {
    // Query Firestore for expired announcement media
    const expiredMedia = await queryExpiredMedia(env, twentyFourHoursAgo);
    
    if (expiredMedia.length === 0) {
      console.log('✨ [MEDIA] No expired announcement media found');
      return 0;
    }

    console.log(`📂 [MEDIA] Found ${expiredMedia.length} expired announcement media to delete`);

    // Process each expired media
    for (const media of expiredMedia) {
      try {
        // Delete from R2
        if (media.r2Url) {
          await deleteFromR2(env.R2_BUCKET, media.r2Url);
          console.log(`  🗑️  Deleted R2 file: ${media.fileName}`);
        }

        // Delete thumbnail from R2
        if (media.thumbnailUrl && media.thumbnailUrl.startsWith('http')) {
          await deleteFromR2(env.R2_BUCKET, media.thumbnailUrl);
          console.log(`  🗑️  Deleted R2 thumbnail: ${media.fileName}`);
        }

        // Soft delete in Firestore
        await softDeleteInFirestore(env, media.id);
        
        deletedCount++;
      } catch (error: any) {
        console.error(`  ❌ Failed to delete media ${media.id}:`, error.message);
        // Continue with next media
      }
    }

    return deletedCount;
  } catch (error) {
    console.error('❌ [MEDIA] Error in deleteExpiredMedia:', error);
    throw error;
  }
}

/**
 * Query Firestore for expired announcement media
 * Uses Firestore REST API
 */
async function queryExpiredMedia(env: Env, timestampMs: number): Promise<MediaMessage[]> {
  const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:runQuery`;
  
  // Convert timestamp to Firestore Timestamp format
  const seconds = Math.floor(timestampMs / 1000);
  
  const query = {
    structuredQuery: {
      from: [{ collectionId: 'media_messages' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            {
              fieldFilter: {
                field: { fieldPath: 'mediaType' },
                op: 'EQUAL',
                value: { stringValue: 'announcement' }
              }
            },
            {
              fieldFilter: {
                field: { fieldPath: 'createdAt' },
                op: 'LESS_THAN',
                value: { timestampValue: new Date(timestampMs).toISOString() }
              }
            },
            {
              unaryFilter: {
                field: { fieldPath: 'deletedAt' },
                op: 'IS_NULL'
              }
            }
          ]
        }
      },
      limit: 50 // Process 50 at a time to avoid timeouts
    }
  };

  const response = await fetch(firestoreUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${env.FIREBASE_API_KEY}`
    },
    body: JSON.stringify(query)
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Firestore query failed: ${error}`);
  }

  const data = await response.json();
  
  // Parse Firestore response
  const mediaList: MediaMessage[] = [];
  
  if (data && Array.isArray(data)) {
    for (const item of data) {
      if (item.document) {
        const doc = item.document;
        const fields = doc.fields || {};
        
        // Extract document ID from name (projects/.../documents/media_messages/{id})
        const id = doc.name.split('/').pop();
        
        mediaList.push({
          id,
          mediaType: fields.mediaType?.stringValue || '',
          createdAt: parseFirestoreTimestamp(fields.createdAt),
          deletedAt: fields.deletedAt,
          r2Url: fields.r2Url?.stringValue || '',
          thumbnailUrl: fields.thumbnailUrl?.stringValue,
          fileName: fields.fileName?.stringValue || 'unknown'
        });
      }
    }
  }

  return mediaList;
}

/**
 * Soft delete document in Firestore by setting deletedAt timestamp
 */
async function softDeleteInFirestore(env: Env, documentId: string): Promise<void> {
  const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/media_messages/${documentId}?updateMask.fieldPaths=deletedAt`;
  
  const updateData = {
    fields: {
      deletedAt: {
        timestampValue: new Date().toISOString()
      }
    }
  };

  const response = await fetch(firestoreUrl, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${env.FIREBASE_API_KEY}`
    },
    body: JSON.stringify(updateData)
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Firestore update failed: ${error}`);
  }
}

/**
 * Delete file from R2
 */
async function deleteFromR2(bucket: R2Bucket, r2Url: string): Promise<void> {
  try {
    // Extract object key from URL
    // URL format: https://pub-xxx.r2.dev/media/file.jpg -> media/file.jpg
    const url = new URL(r2Url);
    const objectKey = url.pathname.substring(1); // Remove leading /

    await bucket.delete(objectKey);
    console.log(`    ✓ Deleted from R2: ${objectKey}`);
  } catch (error: any) {
    // If file doesn't exist, that's OK
    if (error.message?.includes('NoSuchKey') || error.message?.includes('404')) {
      console.log(`    ⚠️  File not found in R2 (already deleted?): ${r2Url}`);
    } else {
      throw error;
    }
  }
}

/**
 * Parse Firestore timestamp to JS timestamp
 */
function parseFirestoreTimestamp(timestamp: any): { _seconds: number; _nanoseconds: number } {
  if (timestamp?.timestampValue) {
    const date = new Date(timestamp.timestampValue);
    return {
      _seconds: Math.floor(date.getTime() / 1000),
      _nanoseconds: 0
    };
  }
  return { _seconds: 0, _nanoseconds: 0 };
}
