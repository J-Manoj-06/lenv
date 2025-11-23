/// AI Configuration for DeepSeek API - Direct Access
///
/// Simple direct API configuration for testing without Firebase billing.
///
/// ⚠️ SECURITY WARNING: API key is stored in app code!
/// This is OK for testing, but for production you should use Firebase proxy.
///
/// SETUP: Add your DeepSeek API key on line 14 below
library;

class AIConfig {
  // Private constructor to prevent instantiation
  AIConfig._();

  // ⚠️ ADD YOUR DEEPSEEK API KEY HERE (Get it from https://platform.deepseek.com/)
  static const String apiKey = 'sk-your-deepseek-api-key-here';

  // DeepSeek API Configuration
  static const String baseUrl = 'https://api.deepseek.com';
  static const String apiVersion = 'v1';
  static const String model = 'deepseek-chat';

  // Request settings
  static const Duration requestTimeout = Duration(seconds: 60);
  static const Duration initialRetryDelay = Duration(seconds: 2);
  static const int maxRetries = 3;
  static const double temperature = 0.7;
  static const int maxTokens = 4000;

  // Validation
  static bool get isConfigured => apiKey.isNotEmpty && apiKey.startsWith('sk-');

  // Get full API URL
  static String get apiUrl => '$baseUrl/$apiVersion/chat/completions';

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
