/// AI Testing Configuration - Cloudflare Worker Proxy
///
/// ✅ SECURE IMPLEMENTATION ✅
/// All API requests are routed through Cloudflare Worker
/// API key is stored securely on the server - never exposed to client
///
/// Features:
/// - Zero API key exposure in Flutter app
/// - Cloudflare edge caching and DDoS protection
/// - Automatic retry with exponential backoff
/// - Comprehensive error handling
///
library;

class AITestConfig {
  // 🔒 SECURE: Cloudflare Worker endpoint (API key stored on server)
  static const String workerUrl =
      'https://deepseek-ai.giridharannj.workers.dev/generate';

  // 🎯 DEPRECATED: Direct API mode removed for security
  // All requests now go through the secure Cloudflare Worker
  static const bool useDirectAPI = false; // Always false - using secure worker

  // Firebase Cloud Function URL (legacy - keeping for backward compatibility)
  static const String firebaseFunctionUrl =
      'https://us-central1-new-reward-38e46.cloudfunctions.net/generateQuestions';

  // ============================================================
  // DON'T MODIFY BELOW THIS LINE
  // ============================================================

  /// Configuration is always valid with Cloudflare Worker
  static bool get isConfigured => true;

  /// Get the API endpoint - always returns Cloudflare Worker URL
  static String get apiEndpoint => workerUrl;

  /// Get configuration status message
  static String get statusMessage => '✅ Secure Cloudflare Worker mode enabled';

  /// Get headers for API request - no authentication needed (handled by worker)
  static Map<String, String> get headers {
    return {
      'Content-Type': 'application/json',
      // No Authorization header - API key is on the server
    };
  }

  /// AI Model Configuration
  static const String model = 'deepseek-chat';
  static const double temperature = 0.7;
  static const int maxTokens = 4000;

  /// Request Configuration
  static const Duration requestTimeout = Duration(seconds: 60);
  static const int maxRetries = 3;
  static const Duration initialRetryDelay = Duration(milliseconds: 1000);

  /// Question Limits
  static const int maxQuestionsPerRequest = 20;
  static const int minQuestionsPerRequest = 1;

  /// System prompt for test generation
  static const String systemPrompt =
      'You are an expert educational test writer. '
      'Output ONLY a valid JSON array of question objects. '
      'No extra text, no markdown fences, no explanations.';

  /// Debug information
  static Map<String, dynamic> get debugInfo => {
    'mode': useDirectAPI
        ? 'Direct API (Testing)'
        : 'Firebase Function (Production)',
    'endpoint': apiEndpoint,
    'configured': isConfigured,
    'status': statusMessage,
    'model': model,
    'temperature': temperature,
    'maxTokens': maxTokens,
  };

  /// Print configuration status
  static void printStatus() {}
}
