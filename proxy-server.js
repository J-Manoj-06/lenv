/**
 * AI Test Generation Proxy Server
 * 
 * This server acts as a secure proxy between the Flutter app and DeepSeek API.
 * The API key is stored here on the server, not in the mobile app.
 * 
 * Setup:
 * 1. Install dependencies: npm install express axios
 * 2. Add your DeepSeek API key below (line 16)
 * 3. Run: node proxy-server.js
 */

const express = require('express');
const axios = require('axios');
const app = express();

// ============================================================
// 🔑 ADD YOUR DEEPSEEK API KEY HERE:
// ============================================================
const DEEPSEEK_API_KEY = 'YOUR_DEEPSEEK_API_KEY_HERE';
// Get your API key from: https://platform.deepseek.com/
// ============================================================

const DEEPSEEK_API_URL = 'https://api.deepseek.com/v1/chat/completions';

// Enable JSON body parsing
app.use(express.json());

// CORS headers for development (allows Flutter app to call this server)
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  res.header('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// Health check endpoint
app.get('/', (req, res) => {
  res.json({
    status: 'running',
    message: 'AI Test Generation Proxy Server',
    version: '1.0.0',
    endpoints: {
      generate: 'POST /generate'
    }
  });
});

// Main generation endpoint
app.post('/generate', async (req, res) => {
  console.log('\n📥 Received test generation request');
  console.log('Time:', new Date().toISOString());
  
  // Validate API key is set
  if (!DEEPSEEK_API_KEY || DEEPSEEK_API_KEY === 'YOUR_DEEPSEEK_API_KEY_HERE') {
    console.error('❌ ERROR: DeepSeek API key not configured!');
    return res.status(500).json({
      error: 'Server configuration error',
      message: 'DeepSeek API key not set. Please configure the server.'
    });
  }

  try {
    // Log request details (without sensitive data)
    console.log('Model:', req.body.model);
    console.log('Temperature:', req.body.temperature);
    console.log('Max Tokens:', req.body.max_tokens);
    
    // Call DeepSeek API
    console.log('🚀 Calling DeepSeek API...');
    const startTime = Date.now();
    
    const response = await axios.post(
      DEEPSEEK_API_URL,
      req.body,
      {
        headers: {
          'Authorization': `Bearer ${DEEPSEEK_API_KEY}`,
          'Content-Type': 'application/json',
        },
        timeout: 60000, // 60 second timeout
      }
    );
    
    const duration = Date.now() - startTime;
    console.log(`✅ DeepSeek API responded in ${duration}ms`);
    
    // Log token usage if available
    if (response.data.usage) {
      console.log('Token usage:', response.data.usage);
    }
    
    // Return response to Flutter app
    res.json(response.data);
    
  } catch (error) {
    console.error('❌ Error calling DeepSeek API:');
    
    if (error.response) {
      // DeepSeek API returned an error
      console.error('Status:', error.response.status);
      console.error('Data:', error.response.data);
      
      return res.status(error.response.status).json({
        error: error.response.data.error || 'API Error',
        message: error.response.data.message || 'DeepSeek API returned an error',
        details: error.response.data
      });
    } else if (error.request) {
      // Request was made but no response received
      console.error('No response from DeepSeek API');
      
      return res.status(503).json({
        error: 'Network Error',
        message: 'Could not reach DeepSeek API. Please check your internet connection.'
      });
    } else {
      // Something else went wrong
      console.error('Error:', error.message);
      
      return res.status(500).json({
        error: 'Server Error',
        message: error.message
      });
    }
  }
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log('\n' + '='.repeat(60));
  console.log('🚀 AI Test Generation Proxy Server');
  console.log('='.repeat(60));
  console.log(`✅ Server running on http://localhost:${PORT}`);
  console.log(`📱 Android Emulator: http://10.0.2.2:${PORT}`);
  console.log(`📱 iOS Simulator: http://localhost:${PORT}`);
  console.log('');
  
  if (!DEEPSEEK_API_KEY || DEEPSEEK_API_KEY === 'YOUR_DEEPSEEK_API_KEY_HERE') {
    console.log('⚠️  WARNING: DeepSeek API key not configured!');
    console.log('   Please edit proxy-server.js and add your API key on line 16');
  } else {
    console.log('✅ DeepSeek API key configured');
  }
  
  console.log('');
  console.log('📋 Available endpoints:');
  console.log(`   GET  / - Health check`);
  console.log(`   POST /generate - Generate test questions`);
  console.log('='.repeat(60) + '\n');
});
