/**
 * Cloudflare Worker: Firestore Announcement Cleanup
 * 
 * This worker replaces Firebase scheduled Cloud Functions for TTL cleanup.
 * Runs every 6 hours to delete expired announcements from Firestore.
 * 
 * Cost: FREE (Cloudflare Workers free tier)
 * Schedule: Cron trigger (0 */6 * * *)
 * 
 * Deployment: wrangler deploy --config wrangler-cleanup.jsonc
 */

interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT_KEY: string;
}

export default {
  /**
   * Scheduled cleanup - runs every 6 hours
   */
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    console.log('🗑️ Starting scheduled cleanup of expired announcements...');
    
    try {
      const result = await cleanupExpiredAnnouncements(env);
      console.log('✅ Cleanup completed:', result);
    } catch (error) {
      console.error('❌ Cleanup failed:', error);
    }
  },

  /**
   * HTTP endpoint for manual cleanup
   */
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // Handle manual trigger
    if (request.method === 'POST') {
      try {
        const result = await cleanupExpiredAnnouncements(env);
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

    // Health check
    return new Response(JSON.stringify({
      status: 'healthy',
      worker: 'cleanup-worker',
      message: 'POST to trigger manual cleanup',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  },
};

/**
 * Main cleanup logic
 */
async function cleanupExpiredAnnouncements(env: Env): Promise<any> {
  const projectId = env.FIREBASE_PROJECT_ID;
  const serviceAccountKey = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_KEY);

  // Get OAuth token for Firestore REST API
  const accessToken = await getFirestoreAccessToken(serviceAccountKey);

  // Query expired announcements
  const now = new Date();
  const expiredDocs = await queryExpiredAnnouncements(projectId, accessToken, now);

  if (expiredDocs.length === 0) {
    return {
      deletedCount: 0,
      message: 'No expired announcements found',
    };
  }

  // Delete in batches
  let deletedCount = 0;
  for (const doc of expiredDocs.slice(0, 100)) { // Limit to 100 per run
    try {
      await deleteFirestoreDocument(projectId, accessToken, doc.name);
      deletedCount++;
    } catch (error) {
      console.error(`Failed to delete ${doc.name}:`, error);
    }
  }

  return {
    deletedCount,
    totalExpired: expiredDocs.length,
    hasMore: expiredDocs.length > 100,
  };
}

/**
 * Get OAuth2 access token for Firestore API
 */
async function getFirestoreAccessToken(serviceAccount: any): Promise<string> {
  const jwtHeader = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  
  const now = Math.floor(Date.now() / 1000);
  const jwtClaim = btoa(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }));

  // Note: Full JWT signing requires crypto libraries
  // For production, use Firebase Admin SDK or pre-generated token
  // This is a simplified example - you'll need proper JWT signing

  throw new Error('JWT signing not implemented - use Firebase Admin SDK or service account');
}

/**
 * Query Firestore for expired announcements
 */
async function queryExpiredAnnouncements(
  projectId: string,
  accessToken: string,
  now: Date
): Promise<any[]> {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;

  const query = {
    structuredQuery: {
      from: [{ collectionId: 'institute_announcements' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'expiresAt' },
          op: 'LESS_THAN',
          value: { timestampValue: now.toISOString() },
        },
      },
      limit: 100,
    },
  };

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(query),
  });

  if (!response.ok) {
    throw new Error(`Firestore query failed: ${response.statusText}`);
  }

  const results = await response.json();
  return results
    .filter((r: any) => r.document)
    .map((r: any) => r.document);
}

/**
 * Delete Firestore document
 */
async function deleteFirestoreDocument(
  projectId: string,
  accessToken: string,
  documentPath: string
): Promise<void> {
  const url = `https://firestore.googleapis.com/v1/${documentPath}`;

  const response = await fetch(url, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
    },
  });

  if (!response.ok && response.status !== 404) {
    throw new Error(`Failed to delete document: ${response.statusText}`);
  }
}
