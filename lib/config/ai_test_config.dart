/// AI Testing Configuration - Direct API Key
///
/// ⚠️ FOR TESTING ONLY! ⚠️
/// This file allows you to test with a direct API key without Firebase setup.
///
/// SETUP:
/// 1. Get your DeepSeek API key from: https://platform.deepseek.com/api_keys
/// 2. Paste it below in line 15 (replace 'PASTE_YOUR_API_KEY_HERE')
/// 3. Set useDirectAPI = true in line 18
/// 4. Run your app and test
///
/// SECURITY WARNING:
/// ⚠️ Never commit this file with a real API key to Git!
/// ⚠️ For production, use Firebase Cloud Functions (set useDirectAPI = false)
///

class AITestConfig {
  // 📝 PASTE YOUR DEEPSEEK API KEY HERE:
  static const String directApiKey = 'sk-ecd0161142054f39bb8b2d40545232c1';

  // 🔧 TESTING MODE: Set to true to use direct API (for testing)
  static const bool useDirectAPI = true; // Change to true for testing

  // Firebase Cloud Function URL (for production)
  static const String firebaseFunctionUrl =
      'https://us-central1-new-reward-38e46.cloudfunctions.net/generateQuestions';

  // ============================================================
  // DON'T MODIFY BELOW THIS LINE
  // ============================================================

  /// Check if direct API is configured
  static bool get isDirectApiConfigured {
    return directApiKey.isNotEmpty &&
        directApiKey != 'PASTE_YOUR_API_KEY_HERE' &&
        directApiKey.startsWith('sk-');
  }

  /// Check if Firebase function is configured
  static bool get isFirebaseConfigured {
    return firebaseFunctionUrl.isNotEmpty;
  }

  /// Get the appropriate API endpoint
  static String get apiEndpoint {
    if (useDirectAPI) {
      return 'https://api.deepseek.com/v1/chat/completions';
    } else {
      return firebaseFunctionUrl;
    }
  }

  /// Get the API key (only for direct API mode)
  static String? get apiKey {
    if (useDirectAPI) {
      return isDirectApiConfigured ? directApiKey : null;
    }
    return null; // Firebase function handles the key
  }

  /// Check if configuration is valid
  static bool get isConfigured {
    if (useDirectAPI) {
      return isDirectApiConfigured;
    } else {
      return isFirebaseConfigured;
    }
  }

  /// Get configuration status message
  static String get statusMessage {
    if (useDirectAPI) {
      if (!isDirectApiConfigured) {
        return '❌ Direct API key not configured. Please paste your DeepSeek API key in lib/config/ai_test_config.dart';
      }
      return '✅ Direct API mode enabled (Testing)';
    } else {
      if (!isFirebaseConfigured) {
        return '❌ Firebase function URL not configured';
      }
      return '✅ Firebase Cloud Function mode enabled (Production)';
    }
  }

  /// Get headers for API request
  static Map<String, String> get headers {
    if (useDirectAPI) {
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey ?? ''}',
      };
    } else {
      return {
        'Content-Type': 'application/json',
        // Firebase function handles authorization
      };
    }
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
  static void printStatus() {
    print('═══════════════════════════════════════════════════════');
    print('🤖 AI Test Configuration Status');
    print('═══════════════════════════════════════════════════════');
    print(
      'Mode: ${useDirectAPI ? "Direct API (Testing)" : "Firebase Function (Production)"}',
    );
    print('Status: $statusMessage');
    print('Endpoint: $apiEndpoint');
    print('Model: $model');
    print('Temperature: $temperature');
    print('Max Tokens: $maxTokens');
    print('═══════════════════════════════════════════════════════');
  }
}
