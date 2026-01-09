/**
 * Single media Worker: uploads (optional), public fetch via R2 binding (free egress), KV-backed expiry.
 * All downloads flow through this Worker domain: https://files.lenv1.tech/media/{key}
 * Bindings required: MEDIA_BUCKET (R2), MEDIA_METADATA (KV)
 */

export interface Env {
  MEDIA_BUCKET: R2Bucket;
  MEDIA_METADATA: KVNamespace;
  ADMIN_TOKEN?: string; // optional bearer token for admin routes
}

const DEFAULT_EXPIRY_DAYS = 30;
const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20 MB cap to keep PUT costs small
const META_PREFIX = 'meta:';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    try {
      // Public download – always via Worker to keep egress free
      if (request.method === 'GET' && url.pathname.startsWith('/media/')) {
        return await handleFetch(url, env);
      }

      // Test endpoint to list R2 objects
      if (request.method === 'GET' && url.pathname === '/test-r2') {
        try {
          const list = await env.MEDIA_BUCKET.list({ prefix: 'media/17654788', limit: 10 });
          return jsonResponse({ 
            success: true, 
            objects: list.objects.map(o => ({ key: o.key, size: o.size })),
            truncated: list.truncated 
          });
        } catch (error) {
          return jsonResponse({ error: String(error) }, 500);
        }
      }

      // Debug endpoint to see URL parsing
      if (request.method === 'GET' && url.pathname.startsWith('/debug/')) {
        const raw = url.pathname.slice(1);
        const decoded = decodeURIComponent(raw);
        return jsonResponse({
          pathname: url.pathname,
          raw,
          decoded,
          search: url.search,
        });
      }

      // Test fetching a specific key
      if (request.method === 'GET' && url.pathname === '/test-fetch') {
        const testKey = url.searchParams.get('key') || 'media/1765478885338/20ITPC502 -BIG DATA ESSENTIALS  QB CO DISTRIBUTION.doc.pdf';
        const object = await env.MEDIA_BUCKET.get(testKey);
        return jsonResponse({
          key: testKey,
          found: !!object,
          size: object?.size || null,
          contentType: object?.httpMetadata?.contentType || null,
        });
      }

      // Direct upload (optional) – still keeps public URL on Worker domain
      if (request.method === 'POST' && url.pathname === '/upload') {
        return await handleUpload(request, env, url);
      }

      // Admin cleanup trigger
      if (request.method === 'POST' && url.pathname === '/admin/cleanup') {
        if (!env.ADMIN_TOKEN) {
          return jsonResponse({ error: 'ADMIN_TOKEN not set' }, 500);
        }
        const auth = request.headers.get('Authorization');
        if (auth !== `Bearer ${env.ADMIN_TOKEN}`) {
          return jsonResponse({ error: 'Unauthorized' }, 401);
        }
        const deleted = await cleanupExpiredMedia(env, 500);
        return jsonResponse({ ok: true, deleted });
      }

      return new Response('Not Found', { status: 404, headers: corsHeaders });
    } catch (error) {
      console.error('Worker error:', error);
      return jsonResponse({ error: error instanceof Error ? error.message : 'Unknown error' }, 500);
    }
  },

  // Scheduled cleanup keeps bucket lean without scanning whole R2
  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    await cleanupExpiredMedia(env, 1000);
  },
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function buildKey(
  fileName: string,
  schoolId?: string,
  communityId?: string,
  groupId?: string,
  messageId?: string,
): string {
  // Encode filename to handle spaces and special characters
  const encodedFileName = encodeURIComponent(fileName);

  // Build path with optional context
  const pathParts = ['media'];
  if (schoolId) pathParts.push(`schools/${schoolId}`);
  if (communityId) pathParts.push(`communities/${communityId}`);
  if (groupId) pathParts.push(`groups/${groupId}`);
  if (messageId) pathParts.push(`messages/${messageId}`);

  // Add timestamp and filename
  const timestamp = Date.now();
  return `${pathParts.join('/')}/${timestamp}/${encodedFileName}`;
}

async function handleUpload(request: Request, env: Env, url: URL): Promise<Response> {
  const formData = await request.formData();
  const file = (formData.get('file') || formData.get('image')) as File | null;

  if (!file) {
    return jsonResponse({ error: 'Missing file' }, 400);
  }

  if (file.size > MAX_FILE_SIZE) {
    return jsonResponse({ error: `File exceeds 20MB cap. Got ${(file.size / 1024 / 1024).toFixed(2)}MB` }, 413);
  }

  // Optional context for organizing uploads
  const schoolId = (formData.get('schoolId') as string) || undefined;
  const communityId = (formData.get('communityId') as string) || undefined;
  const groupId = (formData.get('groupId') as string) || undefined;
  const messageId = (formData.get('messageId') as string) || undefined;
  const expiryDays = parseInt((formData.get('expiryDays') as string) || '') || DEFAULT_EXPIRY_DAYS;

  // Build key with optional path structure
  const key = buildKey(file.name, schoolId, communityId, groupId, messageId);
  const expiresAt = new Date(Date.now() + expiryDays * 24 * 60 * 60 * 1000);

  try {
    // Upload to R2
    await env.MEDIA_BUCKET.put(key, await file.arrayBuffer(), {
      httpMetadata: {
        contentType: file.type || 'application/octet-stream',
      },
      customMetadata: {
        uploadedAt: new Date().toISOString(),
        expiresAt: expiresAt.toISOString(),
        originalName: file.name,
      },
    });

    // Store metadata in KV for expiry tracking
    const meta = {
      key,
      fileName: file.name,
      uploadedAt: new Date().toISOString(),
      expiresAt: expiresAt.toISOString(),
      contentType: file.type || 'application/octet-stream',
      size: file.size,
      schoolId,
      communityId,
      groupId,
      messageId,
    };

    await env.MEDIA_METADATA.put(`${META_PREFIX}${key}`, JSON.stringify(meta), {
      expirationTtl: expiryDays * 24 * 60 * 60,
    });

    // Return public URL via worker domain (for free egress)
    const publicUrl = `${url.origin}/media/${key}`;
    return jsonResponse({
      success: true,
      key,
      publicUrl,
      fileName: file.name,
      fileSize: file.size,
      expiresAt: expiresAt.toISOString(),
    });
  } catch (error) {
    console.error('Upload failed:', error);
    return jsonResponse({ error: error instanceof Error ? error.message : 'Upload failed' }, 500);
  }
}

async function handleFetch(url: URL, env: Env): Promise<Response> {
  // Extract key from URL: /media/1234/file.jpg → media/1234/file.jpg
  // The R2 key includes the 'media/' prefix
  const raw = url.pathname.slice(1); // Remove leading '/' to get 'media/...'
  const key = decodeURIComponent(raw || '').trim();

  console.log('[handleFetch] URL pathname:', url.pathname);
  console.log('[handleFetch] Raw key:', raw);
  console.log('[handleFetch] Decoded key:', key);

  if (!key || !key.startsWith('media/')) {
    console.log('[handleFetch] Invalid key, returning 400');
    return jsonResponse({ error: 'Invalid media key' }, 400);
  }

  const metaKey = `${META_PREFIX}${key}`;
  const meta = await env.MEDIA_METADATA.get(metaKey, { type: 'json' }) as
    | { expiresAt?: string; contentType?: string }
    | null;

  console.log('[handleFetch] Checking metadata for key:', metaKey);
  console.log('[handleFetch] Metadata found:', !!meta);

  if (meta?.expiresAt && Date.now() > Date.parse(meta.expiresAt)) {
    console.log('[handleFetch] File expired, returning 410');
    await env.MEDIA_BUCKET.delete(key).catch(() => {});
    await env.MEDIA_METADATA.delete(metaKey).catch(() => {});
    return new Response('Gone', { status: 410, headers: corsHeaders });
  }

  console.log('[handleFetch] Fetching from R2, key:', key);
  const object = await env.MEDIA_BUCKET.get(key);
  console.log('[handleFetch] R2 object found:', !!object);

  if (!object) {
    // If metadata existed, treat as expired/deleted; else 404
    const status = meta ? 410 : 404;
    console.log(`[handleFetch] Object not found, returning ${status}`);
    return new Response(status === 410 ? 'Gone' : `Not Found: ${key}`, {
      status,
      headers: { ...corsHeaders, 'X-Debug-Key': key },
    });
  }

  const headers: Record<string, string> = {
    ...corsHeaders,
    'Content-Type': meta?.contentType || object.httpMetadata?.contentType || 'application/octet-stream',
    'Cache-Control': 'public, max-age=31536000', // 365d CDN cache
    'X-Debug-Key': key, // Debug: shows what key was looked up
  };

  if (object.httpEtag) headers['ETag'] = object.httpEtag;
  headers['Accept-Ranges'] = 'bytes';

  return new Response(object.body, { status: 200, headers });
}

async function cleanupExpiredMedia(env: Env, pageSize: number): Promise<number> {
  let cursor: string | undefined = undefined;
  let deleted = 0;
  const now = Date.now();

  do {
    const list = (await env.MEDIA_METADATA.list<{ expiresAt?: string; key?: string }>({
      prefix: META_PREFIX,
      limit: pageSize,
      cursor,
    })) as KVNamespaceListResult<{ expiresAt?: string; key?: string }> & { cursor?: string };
    cursor = list.cursor;

    for (const entry of list.keys) {
      const meta = (await env.MEDIA_METADATA.get(entry.name, { type: 'json' })) as
        | { expiresAt?: string; key?: string }
        | null;
      const expiresAt = meta?.expiresAt;
      const targetKey = meta?.key || entry.name.replace(META_PREFIX, '');

      if (expiresAt && now > Date.parse(expiresAt) && targetKey) {
        await env.MEDIA_BUCKET.delete(targetKey).catch(() => {});
        await env.MEDIA_METADATA.delete(entry.name).catch(() => {});
        deleted++;
      }
    }
  } while (cursor);

  if (deleted) console.log(`Cleanup removed ${deleted} expired objects`);
  return deleted;
}
