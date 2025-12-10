/**
 * Ultra-Optimized Cloudflare Worker for School Management App
 * Zero dependencies, minimal compute, cost-optimized
 */

interface Env {
  R2_BUCKET?: R2Bucket;
  API_KEY?: string;
  R2_PUBLIC_URL?: string;
}

// Allowed MIME types with fast lookup
const ALLOWED_MIMES = new Set([
  'application/pdf',
  'image/jpeg',
  'image/jpg',
  'image/png'
]);

const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20MB

// Fast authentication check
function authenticate(request: Request, env: Env): Response | null {
  const authHeader = request.headers.get('Authorization');
  const apiKey = env.API_KEY || 'dev-school-api-key-12345-change-this';
  
  if (!authHeader || authHeader !== `Bearer ${apiKey}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  return null;
}

// Fast CORS headers
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Content-Type': 'application/json'
};

// Handle OPTIONS preflight with minimal compute
function handleOptions(): Response {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

// Ultra-fast error response
function errorResponse(message: string, status: number = 400): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: CORS_HEADERS
  });
}

// Ultra-fast success response
function successResponse(data: any): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: CORS_HEADERS
  });
}

// POST /uploadFile - Optimized for minimal memory usage
async function handleUploadFile(request: Request, env: Env): Promise<Response> {
  try {
    if (!env.R2_BUCKET) {
      return errorResponse('R2 bucket not configured', 500);
    }

    const contentType = request.headers.get('Content-Type');
    if (!contentType?.includes('multipart/form-data')) {
      return errorResponse('Content-Type must be multipart/form-data');
    }

    const formData = await request.formData();
    const file = formData.get('file');
    
    if (!file) {
      return errorResponse('No file provided');
    }

    // Type guard for File
    const fileObj = file as any;
    if (typeof fileObj.stream !== 'function' || typeof fileObj.size !== 'number') {
      return errorResponse('Invalid file object');
    }

    // Fast validation
    if (fileObj.size > MAX_FILE_SIZE) {
      return errorResponse('File size exceeds 20MB limit');
    }

    if (!ALLOWED_MIMES.has(fileObj.type)) {
      return errorResponse('Invalid file type. Allowed: PDF, JPG, PNG');
    }

    // Generate unique filename with timestamp prefix
    const timestamp = Date.now();
    const sanitized = fileObj.name.replace(/[^a-zA-Z0-9._-]/g, '_');
    const fileName = `${timestamp}_${sanitized}`;

    // Stream directly to R2 - no buffering in memory
    await env.R2_BUCKET!.put(fileName, fileObj.stream(), {
      httpMetadata: {
        contentType: fileObj.type
      }
    });

    // Use custom R2 domain if configured, otherwise use generic URL
    const r2Domain = env.R2_PUBLIC_URL || 'https://files.lenv1.tech';
    const fileUrl = `${r2Domain}/${fileName}`;

    // Return minimal response
    return successResponse({
      fileUrl,
      fileName,
      size: fileObj.size,
      mime: fileObj.type
    });
  } catch (e) {
    return errorResponse(`Upload failed: ${e instanceof Error ? e.message : 'Unknown error'}`, 500);
  }
}

// POST /deleteFile - Minimal compute
async function handleDeleteFile(request: Request, env: Env): Promise<Response> {
  try {
    if (!env.R2_BUCKET) {
      return errorResponse('R2 bucket not configured', 500);
    }

    const body = await request.json() as { fileName?: string };
    
    if (!body.fileName) {
      return errorResponse('fileName is required');
    }

    await env.R2_BUCKET.delete(body.fileName);

    return successResponse({ success: true, deleted: body.fileName });
  } catch (e) {
    return errorResponse(`Delete failed: ${e instanceof Error ? e.message : 'Unknown error'}`, 500);
  }
}

// GET /signedUrl - Generate presigned URL
async function handleSignedUrl(url: URL, env: Env): Promise<Response> {
  const fileName = url.searchParams.get('fileName');
  
  if (!fileName) {
    return errorResponse('fileName parameter is required');
  }

  try {
    if (!env.R2_BUCKET) {
      return errorResponse('R2 bucket not configured', 500);
    }

    // Check if file exists
    const object = await env.R2_BUCKET.head(fileName);
    
    if (!object) {
      return errorResponse('File not found', 404);
    }

    // For now, return the public URL
    // In production, use R2's signed URL capability via API
    return successResponse({
      signedUrl: `https://your-r2-domain.com/${fileName}`,
      fileName,
      expiresIn: 3600
    });
  } catch (e) {
    return errorResponse(`Signed URL generation failed: ${e instanceof Error ? e.message : 'Unknown error'}`, 500);
  }
}

// POST /announcement - Metadata only, minimal compute
async function handleAnnouncement(request: Request): Promise<Response> {
  try {
    const body = await request.json() as {
      title?: string;
      message?: string;
      targetAudience?: string;
      standard?: string;
      fileUrl?: string;
    };

    // Fast validation
    if (!body.title || !body.message || !body.targetAudience) {
      return errorResponse('Missing required fields: title, message, targetAudience');
    }

    if (!['whole_school', 'standard'].includes(body.targetAudience)) {
      return errorResponse('targetAudience must be "whole_school" or "standard"');
    }

    if (body.targetAudience === 'standard' && !body.standard) {
      return errorResponse('standard is required when targetAudience is "standard"');
    }

    // Return metadata immediately - client handles Firestore
    return successResponse({
      id: `announcement_${Date.now()}`,
      title: body.title,
      message: body.message,
      targetAudience: body.targetAudience,
      standard: body.standard || null,
      fileUrl: body.fileUrl || null,
      createdAt: new Date().toISOString()
    });
  } catch (e) {
    return errorResponse(`Announcement processing failed: ${e instanceof Error ? e.message : 'Unknown error'}`, 500);
  }
}

// POST /groupMessage - Metadata only, minimal compute
async function handleGroupMessage(request: Request): Promise<Response> {
  try {
    const body = await request.json() as {
      groupId?: string;
      senderId?: string;
      messageText?: string;
      fileUrl?: string;
    };

    // Fast validation
    if (!body.groupId || !body.senderId) {
      return errorResponse('Missing required fields: groupId, senderId');
    }

    if (!body.messageText && !body.fileUrl) {
      return errorResponse('Either messageText or fileUrl must be provided');
    }

    // Return metadata immediately
    return successResponse({
      id: `message_${Date.now()}`,
      groupId: body.groupId,
      senderId: body.senderId,
      messageText: body.messageText || null,
      fileUrl: body.fileUrl || null,
      timestamp: new Date().toISOString()
    });
  } catch (e) {
    return errorResponse(`Message processing failed: ${e instanceof Error ? e.message : 'Unknown error'}`, 500);
  }
}

// POST /scheduleTest - Metadata only, minimal compute
async function handleScheduleTest(request: Request): Promise<Response> {
  try {
    const body = await request.json() as {
      classId?: string;
      subject?: string;
      date?: string;
      time?: string;
      duration?: number;
      createdBy?: string;
    };

    // Fast validation
    if (!body.classId || !body.subject || !body.date || !body.time || !body.createdBy) {
      return errorResponse('Missing required fields: classId, subject, date, time, createdBy');
    }

    // Return metadata immediately
    return successResponse({
      id: `test_${Date.now()}`,
      classId: body.classId,
      subject: body.subject,
      date: body.date,
      time: body.time,
      duration: body.duration || 60,
      createdBy: body.createdBy,
      scheduledAt: new Date().toISOString()
    });
  } catch (e) {
    return errorResponse(`Test scheduling failed: ${e instanceof Error ? e.message : 'Unknown error'}`, 500);
  }
}

// GET /status - Zero authentication, instant response
function handleStatus(): Response {
  return successResponse({ ok: true, timestamp: Date.now() });
}

// Main router - optimized for speed with early returns
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // Handle OPTIONS immediately
    if (request.method === 'OPTIONS') {
      return handleOptions();
    }

    // Status endpoint - no auth, instant return
    if (path === '/status' && request.method === 'GET') {
      return handleStatus();
    }

    // Authenticate all other routes
    const authError = authenticate(request, env);
    if (authError) return authError;

    // Route with early returns for speed
    try {
      // POST routes
      if (request.method === 'POST') {
        if (path === '/uploadFile') return await handleUploadFile(request, env);
        if (path === '/deleteFile') return await handleDeleteFile(request, env);
        if (path === '/announcement') return await handleAnnouncement(request);
        if (path === '/groupMessage') return await handleGroupMessage(request);
        if (path === '/scheduleTest') return await handleScheduleTest(request);
      }

      // GET routes
      if (request.method === 'GET') {
        if (path === '/signedUrl') return await handleSignedUrl(url, env);
      }

      // 404 for unmatched routes
      return errorResponse('Route not found', 404);
    } catch (e) {
      return errorResponse(`Internal error: ${e instanceof Error ? e.message : 'Unknown error'}`, 500);
    }
  }
};
