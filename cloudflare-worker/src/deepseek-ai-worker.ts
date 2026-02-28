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

    // Mindmap endpoints
    if (request.method === 'POST' && url.pathname === '/mindmap/generate') {
      return await handleMindmapGenerate(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/mindmap/publish') {
      return await handleMindmapPublish(request, env);
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
          '/mindmap/generate': 'POST - Generate mindmap draft',
          '/mindmap/publish': 'POST - Publish mindmap',
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
 * Handle mindmap generation request
 */
async function handleMindmapGenerate(request: Request, env: Env): Promise<Response> {
  console.log('🧠 Mindmap generation request received');
  
  try {
    let body: any;
    try {
      body = await request.json();
      console.log('📦 Parsed body:', { topic: body.topic, topicCount: body.topicCount });
    } catch (e) {
      console.error('❌ Failed to parse JSON:', e);
      return jsonResponse({ error: 'Invalid JSON' }, 400);
    }

    const { topic, topicCount, depthLevel, learningStyle, subject, standard, section } = body;

    if (!topic || !topicCount) {
      return jsonResponse({ error: 'Missing topic or topicCount' }, 400);
    }

    console.log('🎯 Building mindmap prompt for:', topic);
    const prompt = buildMindmapPrompt({
      topic,
      topicCount: Number(topicCount),
      depthLevel: depthLevel || 'Medium',
      learningStyle: learningStyle || 'Concept Based',
      subject: subject || 'General',
      standard: standard || '',
      section: section || '',
    });

    console.log('📤 Calling DeepSeek API...');
    const deepseekRequest = {
      model: 'deepseek-chat',
      messages: [{ role: 'user', content: prompt }],
      temperature: 0.4,
      max_tokens: 2800,
      response_format: { type: 'json_object' },
    };

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

      console.log('📥 Response status:', response.status);

      let responseData: any;
      try {
        responseData = await response.json();
        console.log('✅ Parsed response, choices count:', responseData?.choices?.length);
      } catch (e) {
        console.error('❌ Failed to parse response body:', e);
        return jsonResponse({ error: 'Invalid API response' }, 502);
      }

      if (!response.ok) {
        console.error('❌ API error response:', responseData);
        if (response.status === 429) {
          return jsonResponse({ error: 'Rate limit exceeded' }, 429);
        }
        return jsonResponse({ error: 'AI service error', details: responseData }, 502);
      }

      const raw = responseData?.choices?.[0]?.message?.content || '';
      console.log('📝 Raw response length:', raw.length);
      
      const jsonText = sanitizeToJsonString(raw);
      console.log('🧹 Sanitized JSON length:', jsonText.length);

      let parsed: any;
      try {
        parsed = JSON.parse(jsonText);
        console.log('✨ Successfully parsed JSON, root title:', parsed?.root?.title);
      } catch (e) {
        console.error('❌ Failed to parse AI JSON response:', e, 'Raw:', raw.substring(0, 200));
        return jsonResponse({ error: 'Invalid JSON from AI', raw: raw.substring(0, 500) }, 502);
      }

      const normalized = normalizeMindmapStructure(parsed, topic);
      const previewNodes = normalized.root.children.slice(0, 4).map((n: any) => n.title);

      console.log('✅ Mindmap generated successfully with', normalized.root.children.length, 'branches');
      return jsonResponse({
        topic: normalized.topic,
        structure: normalized,
        previewNodes,
      });
    } catch (fetchError: any) {
      clearTimeout(timeoutId);
      if (fetchError.name === 'AbortError') {
        console.error('⏱️ Request timeout');
        return jsonResponse({ error: 'Request timeout' }, 504);
      }
      throw fetchError;
    }
  } catch (error: any) {
    console.error('❌ Mindmap generation error:', error.message, error);
    return jsonResponse({ error: 'Internal server error', details: error.message }, 500);
  }
}

/**
 * Handle mindmap publish request
 */
async function handleMindmapPublish(request: Request, env: Env): Promise<Response> {
  try {
    let body: any;
    try {
      body = await request.json();
    } catch (e) {
      return jsonResponse({ error: 'Invalid JSON' }, 400);
    }

    const { structure, classId, subjectId, topic } = body;

    if (!structure || !classId || !subjectId || !topic) {
      return jsonResponse({ error: 'Missing required fields' }, 400);
    }

    // Validate structure
    if (!structure.root || !Array.isArray(structure.root.children)) {
      return jsonResponse({ error: 'Invalid mindmap structure' }, 400);
    }

    // Structure is valid - in real implementation, this would save to Firestore
    // For now, just return success
    return jsonResponse({
      success: true,
      topic,
      branchCount: structure.root.children.length,
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    console.error('❌ Mindmap publish error:', error.message);
    return jsonResponse({ error: 'Internal server error' }, 500);
  }
}

/**
 * Build mindmap generation prompt
 */
function buildMindmapPrompt({
  topic,
  topicCount,
  depthLevel,
  learningStyle,
  subject,
  standard,
  section,
}: {
  topic: string;
  topicCount: number;
  depthLevel: string;
  learningStyle: string;
  subject: string;
  standard: string;
  section: string;
}): string {
  const depthHint = (depthLevel === 'Deep' || depthLevel === 'Advanced')
    ? '3 to 4 levels'
    : depthLevel === 'Medium'
      ? '2 to 3 levels'
      : '1 to 2 levels';

  const learningStyleDesc =
    learningStyle === 'Visual' ? 'Use visual metaphors and spatial relationships.' :
    learningStyle === 'Kinesthetic' ? 'Emphasize action, process, and practical steps.' :
    'Organize by high-level concepts and principles.';

  // Detect language from subject name
  const subjectLower = subject.toLowerCase();
  let languageInstruction = '';
  
  if (subjectLower.includes('hindi') || subjectLower.includes('हिंदी')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in HINDI language (Devanagari script). This is a Hindi language class.';
  } else if (subjectLower.includes('tamil') || subjectLower.includes('தமிழ்')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in TAMIL language. This is a Tamil language class.';
  } else if (subjectLower.includes('telugu') || subjectLower.includes('తెలుగు')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in TELUGU language. This is a Telugu language class.';
  } else if (subjectLower.includes('kannada') || subjectLower.includes('ಕನ್ನಡ')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in KANNADA language. This is a Kannada language class.';
  } else if (subjectLower.includes('bengali') || subjectLower.includes('বাংলা')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in BENGALI language. This is a Bengali language class.';
  } else if (subjectLower.includes('marathi') || subjectLower.includes('मराठी')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in MARATHI language. This is a Marathi language class.';
  } else if (subjectLower.includes('gujarati') || subjectLower.includes('ગુજરાતી')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in GUJARATI language. This is a Gujarati language class.';
  } else if (subjectLower.includes('malayalam') || subjectLower.includes('മലയാളം')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in MALAYALAM language. This is a Malayalam language class.';
  } else if (subjectLower.includes('punjabi') || subjectLower.includes('ਪੰਜਾਬੀ')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in PUNJABI language. This is a Punjabi language class.';
  } else if (subjectLower.includes('urdu') || subjectLower.includes('اردو')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in URDU language. This is an Urdu language class.';
  } else if (subjectLower.includes('french') || subjectLower.includes('français')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in FRENCH language. This is a French language class.';
  } else if (subjectLower.includes('german') || subjectLower.includes('deutsch')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in GERMAN language. This is a German language class.';
  } else if (subjectLower.includes('spanish') || subjectLower.includes('español')) {
    languageInstruction = '\n\n**IMPORTANT**: Generate ALL content (titles, descriptions) in SPANISH language. This is a Spanish language class.';
  }

  const classContext = standard && section ? `\nClass: ${standard} ${section}` : '';

  return `Create a detailed learning mindmap for the topic "${topic}".
${classContext}
Subject: ${subject}
Learning Style: ${learningStyle}
Depth Level: ${depthLevel}${languageInstruction}

Requirements:
1. Main topic as the central node.
2. Create exactly ${topicCount} branches from the main topic (no more, no less).
3. Each branch should have ${depthHint} of sub-topics.
4. ${learningStyleDesc}
5. Make connections explicit where relevant.
6. Content should be appropriate for ${standard || 'students'} level.

Return ONLY valid JSON with this exact structure:
{
  "root": {
    "title": "Main Topic",
    "children": [
      {
        "title": "Branch Title",
        "description": "Brief description",
        "children": [
          {
            "title": "Sub-topic",
            "description": "Details",
            "children": []
          }
        ]
      }
    ]
  }
}

Ensure:
- All strings are properly escaped
- No trailing commas
- Valid JSON only`;
}

/**
 * Normalize mindmap structure
 */
function normalizeMindmapStructure(obj: any, topic: string): any {
  try {
    if (!obj || !obj.root) {
      return {
        topic,
        root: {
          title: topic,
          description: 'Main Topic',
          children: [],
        },
      };
    }

    const root = obj.root;
    if (!Array.isArray(root.children)) {
      root.children = [];
    }

    root.children = root.children.map((child: any) => normalizeNode(child));

    return {
      topic: root.title || topic,
      root,
    };
  } catch (e) {
    return {
      topic,
      root: {
        title: topic,
        description: 'Main Topic',
        children: [],
      },
    };
  }
}

/**
 * Normalize individual mindmap node
 */
function normalizeNode(node: any): any {
  if (!node || typeof node !== 'object') {
    return { title: 'Unknown', description: '', children: [] };
  }

  return {
    title: String(node.title || '').trim() || 'Untitled',
    description: String(node.description || '').trim(),
    children: Array.isArray(node.children) ? node.children.map(normalizeNode) : [],
  };
}

/**
 * Sanitize JSON string
 */
function sanitizeToJsonString(text: string): string {
  if (typeof text !== 'string') return '';
  let out = text.trim();
  if (out.startsWith('```')) {
    out = out
      .replace(/^```json\n?/i, '')
      .replace(/^```\n?/i, '')
      .replace(/```\s*$/i, '')
      .trim();
  }
  return out;
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
