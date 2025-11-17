/**
 * Firebase Cloud Functions for AI Test Generation - COMPLETE IMPLEMENTATION
 * 
 * This is a comprehensive, production-ready implementation that proxies
 * requests to DeepSeek API while keeping API keys secure on the server.
 * 
 * SETUP INSTRUCTIONS:
 * ==================
 * 
 * 1. Get DeepSeek API Key:
 *    - Visit: https://platform.deepseek.com/api_keys
 *    - Create an API key (starts with "sk-")
 * 
 * 2. Install Dependencies:
 *    cd functions
 *    npm install axios
 * 
 * 3. Create .env file in functions folder:
 *    DEEPSEEK_API_KEY=sk-your-actual-key-here
 * 
 * 4. Deploy:
 *    firebase deploy --only functions:generateTestQuestions
 *    
 * Note: The .env file is for local development only.
 * For production, set the secret in Firebase Console:
 * - Go to Firebase Console > Functions > Secrets
 * - Add secret: DEEPSEEK_API_KEY
 * 
 * 6. Test:
 *    curl -X POST https://YOUR-PROJECT.cloudfunctions.net/generateTestQuestions \
 *      -H "Content-Type: application/json" \
 *      -d '{"model":"deepseek-chat","messages":[...]}'
 * 
 * FEATURES:
 * =========
 * - Secure API key storage (never exposed to clients)
 * - CORS enabled for web apps
 * - Comprehensive error handling
 * - Request validation
 * - Timeout handling
 * - Detailed logging
 * - Rate limit detection
 * - Ping endpoint for health checks
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

// Initialize Firebase Admin (only if not already initialized)
if (!admin.apps.length) {
  admin.initializeApp();
}

// DeepSeek API Configuration
const DEEPSEEK_API_URL = 'https://api.deepseek.com/v1/chat/completions';
// Try environment variable first, then fall back to Firebase config
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY || functions.config().deepseek?.api_key;

/**
 * Generate Test Questions using DeepSeek AI
 * 
 * This is the main function that handles AI test generation requests
 * from the Flutter app. It acts as a secure proxy to DeepSeek API.
 * 
 * REQUEST FORMAT:
 * {
 *   "model": "deepseek-chat",
 *   "messages": [
 *     {"role": "system", "content": "You are a test writer..."},
 *     {"role": "user", "content": "Create 10 questions about..."}
 *   ],
 *   "temperature": 0.7,
 *   "max_tokens": 4000
 * }
 * 
 * RESPONSE FORMAT:
 * - Success (200): DeepSeek API response forwarded as-is
 * - Rate Limit (429): {"error": "Rate limit exceeded", "retryAfter": 60}
 * - Auth Error (500): {"error": "Authentication failed"}
 * - Server Error (502): {"error": "AI service error"}
 * - Timeout (504): {"error": "Request timeout"}
 */
exports.generateTestQuestions = functions
  .runWith({
    timeoutSeconds: 120,  // 2 minute timeout for complex generations
    memory: '256MB',       // Adequate memory for processing
  })
  .https.onRequest(async (req, res) => {
    // ============================================================
    // CORS CONFIGURATION
    // ============================================================
    // Enable CORS for all origins (adjust for production security)
    res.set('Access-Control-Allow-Origin', '*');
    
    // Handle CORS preflight requests
    if (req.method === 'OPTIONS') {
      res.set('Access-Control-Allow-Methods', 'POST');
      res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      res.set('Access-Control-Max-Age', '3600');
      res.status(204).send('');
      return;
    }

    // ============================================================
    // METHOD VALIDATION
    // ============================================================
    if (req.method !== 'POST') {
      res.status(405).json({
        error: 'Method not allowed',
        message: 'This endpoint only accepts POST requests.',
      });
      return;
    }

    // ============================================================
    // API KEY CONFIGURATION CHECK
    // ============================================================
    if (!DEEPSEEK_API_KEY) {
      console.error('❌ DeepSeek API key not configured');
      console.error('💡 Set it with: firebase functions:config:set deepseek.api_key="your-key"');
      
      res.status(500).json({
        error: 'Server configuration error',
        message: 'DeepSeek API key not configured on server. Please contact administrator.',
      });
      return;
    }

    try {
      // ============================================================
      // REQUEST VALIDATION
      // ============================================================
      const { model, messages, temperature, max_tokens } = req.body;

      // Validate required fields
      if (!model || typeof model !== 'string') {
        res.status(400).json({
          error: 'Invalid request',
          message: 'Field "model" is required and must be a string.',
        });
        return;
      }

      if (!messages || !Array.isArray(messages) || messages.length === 0) {
        res.status(400).json({
          error: 'Invalid request',
          message: 'Field "messages" is required and must be a non-empty array.',
        });
        return;
      }

      // Validate messages format
      for (let i = 0; i < messages.length; i++) {
        const msg = messages[i];
        if (!msg.role || !msg.content) {
          res.status(400).json({
            error: 'Invalid request',
            message: `Message at index ${i} must have "role" and "content" fields.`,
          });
          return;
        }
      }

      // ============================================================
      // LOGGING
      // ============================================================
      console.log('🤖 AI Test Generation Request');
      console.log('📝 Model:', model);
      console.log('📝 Messages count:', messages.length);
      console.log('🌡️  Temperature:', temperature || 0.7);
      console.log('📏 Max tokens:', max_tokens || 4000);
      console.log('⏰ Timestamp:', new Date().toISOString());

      // ============================================================
      // DEEPSEEK API CALL
      // ============================================================
      const response = await axios.post(
        DEEPSEEK_API_URL,
        {
          model: model || 'deepseek-chat',
          messages: messages,
          temperature: temperature !== undefined ? temperature : 0.7,
          max_tokens: max_tokens || 4000,
          stream: false,  // Disable streaming for simplicity
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${DEEPSEEK_API_KEY}`,
          },
          timeout: 60000,  // 60 second timeout
        }
      );

      // ============================================================
      // SUCCESS RESPONSE
      // ============================================================
      console.log('✅ DeepSeek API responded successfully');
      console.log('📊 Response status:', response.status);
      console.log('📦 Response data size:', JSON.stringify(response.data).length, 'bytes');

      // Forward the successful response
      res.status(200).json(response.data);

    } catch (error) {
      // ============================================================
      // ERROR HANDLING
      // ============================================================
      console.error('❌ Error in generateTestQuestions');
      console.error('🔍 Error type:', error.name);
      console.error('💬 Error message:', error.message);

      // Handle Axios response errors (API returned an error)
      if (error.response) {
        const status = error.response.status;
        const data = error.response.data;

        console.error('📡 API Error Status:', status);
        console.error('📡 API Error Data:', JSON.stringify(data).substring(0, 500));

        // Rate Limit (429)
        if (status === 429) {
          const retryAfter = error.response.headers['retry-after'] || '60';
          console.warn('⏳ Rate limit exceeded. Retry after:', retryAfter, 'seconds');
          
          res.status(429).json({
            error: 'Rate limit exceeded',
            message: 'Too many requests to AI service. Please try again later.',
            retryAfter: parseInt(retryAfter, 10),
          });
          return;
        }

        // Authentication Error (401/403)
        if (status === 401 || status === 403) {
          console.error('🔐 Authentication failed - check API key');
          
          res.status(500).json({
            error: 'Authentication failed',
            message: 'Server API key is invalid. Please contact administrator.',
          });
          return;
        }

        // Server Errors (5xx)
        if (status >= 500) {
          console.error('🔥 DeepSeek API server error');
          
          res.status(502).json({
            error: 'AI service error',
            message: 'DeepSeek API is experiencing issues. Please try again in a few minutes.',
          });
          return;
        }

        // Other 4xx Errors
        res.status(status).json({
          error: 'API request failed',
          message: data.error?.message || 'Request to AI service failed.',
          details: data.error?.type || 'unknown_error',
        });
        return;
      }

      // Handle timeout errors
      if (error.code === 'ECONNABORTED' || error.message.includes('timeout')) {
        console.error('⏱️  Request timeout');
        
        res.status(504).json({
          error: 'Request timeout',
          message: 'The AI service took too long to respond. Please try again.',
        });
        return;
      }

      // Handle network errors
      if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED' || error.code === 'ENETUNREACH') {
        console.error('🌐 Network error:', error.code);
        
        res.status(503).json({
          error: 'Network error',
          message: 'Unable to reach AI service. Please check your connection and try again.',
        });
        return;
      }

      // Handle unknown errors
      console.error('❓ Unknown error:', error);
      
      res.status(500).json({
        error: 'Internal server error',
        message: 'An unexpected error occurred while processing your request.',
        errorType: error.name || 'UnknownError',
      });
    }
  });

/**
 * Health Check / Ping Endpoint
 * 
 * Use this to verify the Cloud Function is deployed and running.
 * 
 * GET/POST: https://YOUR-PROJECT.cloudfunctions.net/ping
 * 
 * Response:
 * {
 *   "status": "ok",
 *   "message": "AI Test Generation Functions are running!",
 *   "timestamp": "2025-01-13T10:30:00.000Z",
 *   "configured": true,
 *   "version": "1.0.0"
 * }
 */
exports.ping = functions.https.onRequest((req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Methods', 'GET, POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    res.status(204).send('');
    return;
  }

  console.log('🏓 Ping request received');
  
  res.status(200).json({
    status: 'ok',
    message: 'AI Test Generation Functions are running!',
    timestamp: new Date().toISOString(),
    configured: !!DEEPSEEK_API_KEY,
    version: '1.0.0',
    endpoints: {
      generateTestQuestions: '/generateTestQuestions',
      ping: '/ping',
    },
  });
});
