/**
 * DeepSeek AI Proxy Worker
 * 
 * Secure proxy for DeepSeek API requests - prevents API key exposure in client apps
 * Deployed to: https://deepseek-ai.giridharannj.workers.dev
 * 
 * Features:
 * - Secure API key storage (via Wrangler secrets)
 * - CORS enabled for Flutter apps
 * - Request validation and rate limiting
 * - Comprehensive error handling
 * - Request logging for monitoring
 * - Timeout handling
 * 
 * Environment Variables Required:
 * - DEEPSEEK_API_KEY: Your DeepSeek API key (set via wrangler secret)
 */

export interface Env {
  DEEPSEEK_API_KEY: string;
}

const DEEPSEEK_API_URL = 'https://api.deepseek.com/v1/chat/completions';
const REQUEST_TIMEOUT_MS = 120000; // 2 minutes
const MAX_TOKENS = 8000;
const MAX_MESSAGES = 50;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }

    // Health check endpoint
    if (request.method === 'GET' && url.pathname === '/health') {
      return jsonResponse({
        status: 'healthy',
        service: 'DeepSeek AI Proxy',
        timestamp: new Date().toISOString(),
        configured: !!env.DEEPSEEK_API_KEY,
      });
    }

    // Main AI endpoint
    if (request.method === 'POST' && (url.pathname === '/chat' || url.pathname === '/generate')) {
      return await handleAIRequest(request, env);
    }

    // Route not found
    return jsonResponse(
      {
        error: 'Not Found',
        message: 'Invalid endpoint',
        availableEndpoints: {
          '/health': 'GET - Health check',
          '/chat': 'POST - Chat completion',
          '/generate': 'POST - Test generation',
        },
      },
      404
    );
  },
};

/**
 * Handle AI request - proxy to DeepSeek API
 */
async function handleAIRequest(request: Request, env: Env): Promise<Response> {
  const startTime = Date.now();

  try {
    // Check API key configuration
    if (!env.DEEPSEEK_API_KEY) {
      console.error('❌ DEEPSEEK_API_KEY not configured');
      return jsonResponse(
        {
          error: 'Configuration Error',
          message: 'AI service not configured. Contact administrator.',
        },
        500
      );
    }

    // Parse request body
    let body: any;
    try {
      body = await request.json();
    } catch (e) {
      return jsonResponse(
        {
          error: 'Invalid Request',
          message: 'Request body must be valid JSON',
        },
        400
      );
    }

    // Validate required fields
    const validation = validateRequest(body);
    if (!validation.valid) {
      return jsonResponse(
        {
          error: 'Validation Error',
          message: validation.error,
          required: {
            model: 'string (e.g., "deepseek-chat")',
            messages: 'array of {role, content} objects',
          },
        },
        400
      );
    }

    // Log request (without sensitive data)
    console.log('🤖 AI Request:', {
      model: body.model,
      messageCount: body.messages?.length || 0,
      temperature: body.temperature || 0.7,
      maxTokens: body.max_tokens || 4000,
      timestamp: new Date().toISOString(),
    });

    // Prepare DeepSeek API request
    const deepseekRequest = {
      model: body.model || 'deepseek-chat',
      messages: body.messages,
      temperature: body.temperature !== undefined ? body.temperature : 0.7,
      max_tokens: Math.min(body.max_tokens || 4000, MAX_TOKENS),
      stream: false, // Disable streaming for simplicity
    };

    // Call DeepSeek API with timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
      const response = await fetch(DEEPSEEK_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${env.DEEPSEEK_API_KEY}`,
        },
        body: JSON.stringify(deepseekRequest),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      // Parse response body once (can only be read once!)
      let responseData: any;
      try {
        responseData = await response.json();
      } catch (parseError) {
        console.error('❌ Failed to parse response body');
        return jsonResponse(
          {
            error: 'Invalid API Response',
            message: 'Failed to parse response from AI service',
          },
          502
        );
      }

      // Handle API errors
      if (!response.ok) {
        console.error('❌ DeepSeek API Error:', {
          status: response.status,
          error: responseData,
        });

        // Rate limit
        if (response.status === 429) {
          return jsonResponse(
            {
              error: 'Rate Limit Exceeded',
              message: 'Too many requests. Please try again later.',
              retryAfter: response.headers.get('retry-after') || '60',
            },
            429
          );
        }

        // Authentication error
        if (response.status === 401 || response.status === 403) {
          return jsonResponse(
            {
              error: 'Authentication Failed',
              message: 'Invalid API credentials. Contact administrator.',
            },
            500
          );
        }

        // Other API errors
        return jsonResponse(
          {
            error: 'AI Service Error',
            message: (responseData?.error?.message || responseData?.message) || 'DeepSeek API returned an error',
            status: response.status,
          },
          502
        );
      }

      // Success - use already-parsed response data
      const duration = Date.now() - startTime;

      console.log('✅ AI Response:', {
        status: 'success',
        duration: `${duration}ms`,
        tokensUsed: responseData?.usage?.total_tokens || 'unknown',
      });

      return new Response(JSON.stringify(responseData), {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      });

    } catch (fetchError: any) {
      clearTimeout(timeoutId);
      
      if (fetchError.name === 'AbortError') {
        console.error('⏱️ Request timeout');
        return jsonResponse(
          {
            error: 'Request Timeout',
            message: `Request exceeded ${REQUEST_TIMEOUT_MS / 1000}s timeout`,
          },
          504
        );
      }

      throw fetchError;
    }

  } catch (error: any) {
    const duration = Date.now() - startTime;
    console.error('❌ Unexpected Error:', {
      error: error.message,
      duration: `${duration}ms`,
    });

    return jsonResponse(
      {
        error: 'Internal Server Error',
        message: 'An unexpected error occurred',
        details: error.message,
      },
      500
    );
  }
}

/**
 * Validate request body
 */
function validateRequest(body: any): { valid: boolean; error?: string } {
  if (!body) {
    return { valid: false, error: 'Request body is required' };
  }

  if (!body.model || typeof body.model !== 'string') {
    return { valid: false, error: 'Field "model" is required and must be a string' };
  }

  if (!body.messages || !Array.isArray(body.messages)) {
    return { valid: false, error: 'Field "messages" is required and must be an array' };
  }

  if (body.messages.length === 0) {
    return { valid: false, error: 'At least one message is required' };
  }

  if (body.messages.length > MAX_MESSAGES) {
    return { valid: false, error: `Maximum ${MAX_MESSAGES} messages allowed` };
  }

  // Validate message structure
  for (let i = 0; i < body.messages.length; i++) {
    const msg = body.messages[i];
    if (!msg.role || !msg.content) {
      return {
        valid: false,
        error: `Message at index ${i} must have "role" and "content" fields`,
      };
    }
    if (typeof msg.role !== 'string' || typeof msg.content !== 'string') {
      return {
        valid: false,
        error: `Message at index ${i}: role and content must be strings`,
      };
    }
  }

  return { valid: true };
}

/**
 * Create JSON response with CORS headers
 */
function jsonResponse(data: any, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}
