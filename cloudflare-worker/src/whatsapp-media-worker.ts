/**
 * WhatsApp-Style Media Worker
 * Handles image upload, fetch, and expiry with R2
 */

export interface Env {
  MEDIA_BUCKET: R2Bucket;
  MEDIA_METADATA: KVNamespace;
}

const EXPIRY_DAYS = 30;
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      // Route: Upload image
      if (url.pathname === '/upload' && request.method === 'POST') {
        return await handleUpload(request, env, corsHeaders);
      }

      // Route: Fetch image
      if (url.pathname.startsWith('/media/') && request.method === 'GET') {
        return await handleFetch(url, env, corsHeaders);
      }

      return new Response('Not Found', { status: 404, headers: corsHeaders });
    } catch (error) {
      console.error('Worker error:', error);
      return new Response(
        JSON.stringify({
          success: false,
          errorCode: 'INTERNAL_ERROR',
          message: error instanceof Error ? error.message : 'Unknown error',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }
  },

  // Scheduled cleanup for expired media
  async scheduled(event: ScheduledEvent, env: Env): Promise<void> {
    console.log('Running scheduled media cleanup...');
    await cleanupExpiredMedia(env);
  },
};

/**
 * Handle image upload
 */
async function handleUpload(
  request: Request,
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  try {
    const formData = await request.formData();
    const imageFile = formData.get('image') as unknown as File;
    const messageId = formData.get('messageId') as string;
    const conversationId = formData.get('conversationId') as string;
    const senderId = formData.get('senderId') as string;
    const expiryDays = parseInt(formData.get('expiryDays') as string) || EXPIRY_DAYS;

    // Validate
    if (!imageFile || !messageId || !conversationId || !senderId) {
      return new Response(
        JSON.stringify({
          success: false,
          errorCode: 'MISSING_FIELDS',
          message: 'Missing required fields',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Check file size
    if (imageFile.size > MAX_FILE_SIZE) {
      return new Response(
        JSON.stringify({
          success: false,
          errorCode: 'FILE_TOO_LARGE',
          message: 'File exceeds 10 MB limit',
        }),
        {
          status: 413,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Generate R2 key
    const timestamp = Date.now();
    const r2Key = `chat_images/${conversationId}/${messageId}_${timestamp}.jpg`;

    // Upload to R2
    const imageBytes = await imageFile.arrayBuffer();
    const expiresAt = new Date(Date.now() + expiryDays * 24 * 60 * 60 * 1000);

    await env.MEDIA_BUCKET.put(r2Key, imageBytes, {
      httpMetadata: {
        contentType: 'image/jpeg',
      },
      customMetadata: {
        messageId,
        conversationId,
        senderId,
        uploadedAt: new Date().toISOString(),
        expiresAt: expiresAt.toISOString(),
      },
    });

    // Store metadata in KV
    const metadata = {
      key: r2Key,
      messageId,
      conversationId,
      senderId,
      uploadedAt: new Date().toISOString(),
      expiresAt: expiresAt.toISOString(),
      fileSize: imageFile.size,
    };
    await env.MEDIA_METADATA.put(messageId, JSON.stringify(metadata), {
      expirationTtl: expiryDays * 24 * 60 * 60,
    });

    // Generate public URL
    const publicUrl = `${new URL(request.url).origin}/media/${r2Key}`;

    return new Response(
      JSON.stringify({
        success: true,
        key: r2Key,
        publicUrl,
        expiresAt: expiresAt.toISOString(),
        fileSize: imageFile.size,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('Upload error:', error);
    return new Response(
      JSON.stringify({
        success: false,
        errorCode: 'UPLOAD_FAILED',
        message: error instanceof Error ? error.message : 'Upload failed',
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
}

/**
 * Handle image fetch with proper HTTP codes
 */
async function handleFetch(
  url: URL,
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  try {
    const path = url.pathname.replace('/media/', '');
    
    // Check if exists in R2
    const object = await env.MEDIA_BUCKET.get(path);

    if (!object) {
      // Check metadata to determine if expired vs missing
      const messageId = path.split('/').pop()?.split('_')[0];
      if (messageId) {
        const metadata = await env.MEDIA_METADATA.get(messageId);
        if (metadata) {
          // Had metadata but file is gone = expired/deleted
          return new Response('Gone - File expired or deleted', {
            status: 410,
            headers: corsHeaders,
          });
        }
      }
      // No metadata = never existed
      return new Response('Not Found', {
        status: 404,
        headers: corsHeaders,
      });
    }

    // Check expiry from metadata
    const customMetadata = object.customMetadata;
    if (customMetadata?.expiresAt) {
      const expiresAt = new Date(customMetadata.expiresAt);
      if (new Date() > expiresAt) {
        // Expired - return 410 and delete
        await env.MEDIA_BUCKET.delete(path);
        return new Response('Gone - File expired', {
          status: 410,
          headers: corsHeaders,
        });
      }
    }

    // Return image
    const headers = {
      ...corsHeaders,
      'Content-Type': object.httpMetadata?.contentType || 'image/jpeg',
      'Cache-Control': 'public, max-age=86400', // Cache for 1 day
      'ETag': object.httpEtag || '',
    };

    return new Response(object.body, {
      status: 200,
      headers,
    });
  } catch (error) {
    console.error('Fetch error:', error);
    return new Response('Internal Server Error', {
      status: 500,
      headers: corsHeaders,
    });
  }
}

/**
 * Cleanup expired media (cron job)
 */
async function cleanupExpiredMedia(env: Env): Promise<void> {
  try {
    const now = new Date();
    let deletedCount = 0;

    // List all objects in bucket
    const listed = await env.MEDIA_BUCKET.list({
      prefix: 'chat_images/',
    });

    for (const object of listed.objects) {
      const metadata = object.customMetadata;
      if (metadata?.expiresAt) {
        const expiresAt = new Date(metadata.expiresAt);
        if (now > expiresAt) {
          await env.MEDIA_BUCKET.delete(object.key);
          deletedCount++;
          console.log(`Deleted expired media: ${object.key}`);
        }
      }
    }

    console.log(`Cleanup complete: ${deletedCount} files deleted`);
  } catch (error) {
    console.error('Cleanup error:', error);
  }
}
