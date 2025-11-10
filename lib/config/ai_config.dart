/// AI Test Generation Configuration
///
/// This file integrates with the existing OpenRouter/DeepSeek configuration.
/// No proxy server needed - uses OpenRouter API directly with the configured API key.
///
/// 🔑 API KEY LOCATION: lib/core/config/deepseek_config.dart (line 43)
/// The API key is already configured there!

import '../core/config/deepseek_config.dart';

class AIConfig {
  // Private constructor to prevent instantiation
  AIConfig._();

  /// API URL (uses OpenRouter)
  static String get proxyUrl {
    return '${DeepSeekConfig.baseUrl}/${DeepSeekConfig.apiVersion}/chat/completions';
  }

  /// API Key (from DeepSeek config)
  static String get apiKey {
    return DeepSeekConfig.apiKey;
  }

  /// Site URL and Name for OpenRouter (optional but recommended)
  static String get siteUrl => DeepSeekConfig.siteUrl;
  static String get siteName => DeepSeekConfig.siteName;

  /// AI Model to use
  /// Using the free model to avoid rate limits and costs
  static String get model {
    return DeepSeekConfig.defaultModel; // meta-llama/llama-3.1-8b-instruct:free
  }

  /// Temperature setting (0.0 = deterministic, 1.0 = creative)
  static double get temperature => DeepSeekConfig.defaultTemperature;

  /// Maximum tokens in response
  static int get maxTokens => DeepSeekConfig.defaultMaxTokens;

  /// Request timeout in seconds
  static int get requestTimeoutSeconds {
    return DeepSeekConfig.requestTimeout.inSeconds;
  }

  /// Retry configuration
  static const int maxRetries = 3;
  static const int initialRetryDelayMs = 1000; // 1 second
  static const int maxRetryDelayMs = 10000; // 10 seconds

  /// System message for AI test generation
  static const String systemMessage =
      '''You are an expert educational test writer specializing in creating high-quality exam questions for students.

Your role is to:
1. Create clear, unambiguous questions appropriate for the specified grade level
2. Ensure all multiple choice questions have exactly 4 options (A, B, C, D)
3. Provide correct answers in the specified format
4. Avoid duplicate or similar questions
5. Match the difficulty level to the student's grade
6. Focus on the specified topic and subject matter

Quality standards:
- Questions must be grammatically correct and professionally written
- Options should be plausible and not obviously wrong
- True/False questions should test genuine understanding, not trivia
- Avoid trick questions or ambiguous wording''';

  /// Example prompt structure to guide AI responses
  static const String examplePromptStructure = '''
Example output format (MUST be valid JSON array):
[
  {
    "type": "mcq",
    "questionText": "What is the capital of France?",
    "marks": 2,
    "options": ["London", "Paris", "Berlin", "Madrid"],
    "correctAnswer": "B"
  },
  {
    "type": "truefalse",
    "questionText": "The Earth is flat.",
    "marks": 1,
    "correctAnswer": "false"
  }
]

Important:
- Return ONLY the JSON array
- No markdown code blocks (no ```json)
- No explanatory text before or after
- Ensure valid JSON syntax
- For MCQ: correctAnswer must be "A", "B", "C", or "D"
- For True/False: correctAnswer must be "true" or "false" (lowercase)
''';

  /// Check if AI service is properly configured
  static bool get isConfigured {
    return DeepSeekConfig.isConfigured;
  }

  /// Get configuration status message
  static String get configurationStatus {
    if (isConfigured) {
      return '✅ AI service configured and ready (using ${DeepSeekConfig.defaultModel})';
    } else {
      return '⚠️ AI service not configured. Please add API key in lib/core/config/deepseek_config.dart';
    }
  }

  /// Enable logging for debugging
  static bool get enableLogging => DeepSeekConfig.enableLogging;

  /// Helper to check if running on Android emulator
  static bool get isAndroidEmulator {
    return false; // Not needed with direct API calls
  }

  /// Helper to check if running on iOS simulator
  static bool get isIOSSimulator {
    return false; // Not needed with direct API calls
  }

  /// Get a human-readable description of current configuration
  static String get configDescription {
    return '''
AI Configuration:
- API URL: $proxyUrl
- Model: $model
- Temperature: $temperature
- Max Tokens: $maxTokens
- Max Retries: $maxRetries
- Request Timeout: ${requestTimeoutSeconds}s
- API Key: ${apiKey.isNotEmpty ? "Configured ✅" : "Not configured ❌"}
- Provider: OpenRouter (${DeepSeekConfig.baseUrl})
''';
  }
}
