/**
 * Cloudflare Worker: Institute Announcement Auto-Delete (Simplified)
 * 
 * This version works WITHOUT Firebase authentication by:
 * 1. App stores deletion timestamp in R2 metadata when uploading images
 * 2. Worker checks R2 objects and deletes expired ones
 * 3. App handles Firestore cleanup when loading announcements
 * 
 * Cost: FREE (Cloudflare Workers + R2)
 * Schedule: Runs every 1 hour
 * 
 * Deployment:
 *   wrangler deploy --config wrangler-institute-cleanup-simple.jsonc
 */

interface Env {
  R2_BUCKET: R2Bucket;
  ANNOUNCEMENT_BUCKET: R2Bucket; // Separate bucket for announcements
}

export default {
  /**
   * Scheduled cleanup - runs every 1 hour
   */
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    console.log('🗑️ [R2 CLEANUP] Starting cleanup of expired announcement images...');
    
    try {
      const result = await cleanupExpiredImages(env);
      console.log('✅ [R2 CLEANUP] Completed:', result);
    } catch (error) {
      console.error('❌ [R2 CLEANUP] Failed:', error);
    }
  },

  /**
   * HTTP endpoint for manual trigger
   */
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method === 'POST') {
      try {
        const result = await cleanupExpiredImages(env);
        return new Response(JSON.stringify({
          success: true,
          ...result,
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      } catch (error: any) {
        return new Response(JSON.stringify({
          success: false,
          error: error.message,
        }), {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    return new Response(JSON.stringify({
      status: 'healthy',
      worker: 'r2-cleanup-simple',
      message: 'POST to trigger manual cleanup',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  },
};

/**
 * Cleanup expired images from R2
 */
async function cleanupExpiredImages(env: Env): Promise<{
  deletedCount: number;
  scannedCount: number;
}> {
  const bucket = env.R2_BUCKET;
  let deletedCount = 0;
  let scannedCount = 0;

  // List all objects in announcements/ prefix
  const listed = await bucket.list({ prefix: 'announcements/' });

  console.log(`📂 Found ${listed.objects.length} announcement files`);

  for (const object of listed.objects) {
    scannedCount++;

    try {
      // Get object with metadata
      const obj = await bucket.get(object.key);
      if (!obj) continue;

      // Check custom metadata for expiry
      const expiryDate = obj.customMetadata?.expiresAt;
      if (!expiryDate) {
        console.log(`  ⚠️  No expiry metadata: ${object.key}`);
        continue;
      }

      const expiry = new Date(expiryDate);
      const now = new Date();

      if (now > expiry) {
        // Delete expired image
        await bucket.delete(object.key);
        deletedCount++;
        console.log(`  🗑️  Deleted expired: ${object.key}`);
      }
    } catch (error) {
      console.error(`  ❌ Error processing ${object.key}:`, error);
    }
  }

  return {
    deletedCount,
    scannedCount,
  };
}
