/// AI Configuration for DeepSeek API - Cloudflare Worker Proxy
///
/// ✅ SECURE IMPLEMENTATION - All requests go through Cloudflare Worker
/// API key is stored securely on the server and never exposed to clients
///
/// Previous direct API access has been removed for security
/// All features now use the secure Cloudflare Worker endpoint
///
library;

class AIConfig {
  // Private constructor to prevent instantiation
  AIConfig._();

  // 🔒 SECURE: Cloudflare Worker endpoint (no API key needed in app)
  static const String workerUrl =
      'https://deepseek-ai.giridharannj.workers.dev/generate';

  // DeepSeek Model Configuration
  static const String model = 'deepseek-chat';

  // Request settings
  static const Duration requestTimeout = Duration(seconds: 60);
  static const Duration initialRetryDelay = Duration(seconds: 2);
  static const int maxRetries = 3;
  static const double temperature = 0.7;
  static const int maxTokens = 4000;

  // Configuration is always valid with Cloudflare Worker
  static bool get isConfigured => true;

  // Get full API URL - returns Cloudflare Worker endpoint
  static String get apiUrl => workerUrl;

  /// System message for AI test generation
  static const String systemMessage =
      'You are an expert educational test writer. Output ONLY a JSON array of question objects. No extra text, no markdown fences, no explanations.';

  /// Format guidelines for AI responses
  static const String formatGuidelines = '''
Each question object MUST have these fields:
{
  "type": "mcq" or "truefalse",
  "questionText": "The question text",
  "marks": integer (points for this question),
  "options": ["A", "B", "C", "D"] (only for MCQ, exactly 4 options),
  "correctAnswer": "A" (for MCQ) or "true"/"false" (for true/false)
}

CRITICAL RULES:
1. Output ONLY valid JSON array
2. No markdown code fences
3. No explanatory text
4. All fields are required
5. MCQ must have exactly 4 options
6. correctAnswer must be "A", "B", "C", or "D" for MCQ
7. correctAnswer must be "true" or "false" for true/false questions
''';
}
