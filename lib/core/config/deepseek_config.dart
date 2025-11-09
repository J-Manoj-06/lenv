/// OpenRouter API Configuration for DeepSeek
///
/// 🚀 QUICK START GUIDE:
/// ══════════════════════════════════════════════════════════════
///
/// 1. Get your API key from: https://openrouter.ai/
///    - Sign up or log in
///    - Navigate to API Keys section
///    - Create a new API key
///    - Copy the key (starts with "sk-or-v1-...")
///
/// 2. Your API key is already pasted below! ✅
///
/// 3. Run: flutter pub get (if not done already)
///
/// 4. Hot restart your app (press 'R' in terminal)
///
/// 5. Test it in the AI Test Generator screen!
///
/// 📖 OpenRouter provides access to DeepSeek models through their unified API
///
/// ══════════════════════════════════════════════════════════════
///
/// ⚠️ SECURITY NOTE:
/// - This file contains sensitive API keys
/// - Do NOT commit this file with real keys to public repositories
/// - Consider using environment variables or secure storage in production
///
/// 💡 HELPFUL LINKS:
/// - OpenRouter Platform: https://openrouter.ai/
/// - API Documentation: https://openrouter.ai/docs
/// - Available Models: https://openrouter.ai/models
/// - Pricing: https://openrouter.ai/pricing

class DeepSeekConfig {
  // 🔑 YOUR OPENROUTER API KEY (Already configured! ✅)
  static const String apiKey =
      "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";

  // 🌐 API Configuration (OpenRouter)
  static const String baseUrl = "https://openrouter.ai/api";
  static const String apiVersion = "v1";

  // 🔗 Optional: Your site URL and name for OpenRouter rankings
  static const String siteUrl = ""; // Optional: Add your app URL here
  static const String siteName = "Education Rewards App"; // Your app name

  // 🤖 Model Configuration (OpenRouter Free Models)
  // Available free models:
  // - meta-llama/llama-3.1-8b-instruct:free: Fast, reliable (FREE) ⭐ RECOMMENDED
  // - deepseek/deepseek-r1:free: Reasoning model (FREE, may be rate-limited)
  // - google/gemma-2-9b-it:free: Google's model (FREE)
  // - mistralai/mistral-7b-instruct:free: Good for general tasks (FREE)
  // Paid models:
  // - deepseek/deepseek-chat: Standard chat model (paid)
  // - deepseek/deepseek-coder: Code generation model (paid)
  static const String defaultModel =
      "meta-llama/llama-3.1-8b-instruct:free"; // Changed to avoid rate limits

  // Alternative free models you can try:
  static const String deepseekR1Free =
      "deepseek/deepseek-r1:free"; // May be rate-limited
  static const String gemmaFree =
      "google/gemma-2-9b-it:free"; // Google's free model
  static const String mistralFree =
      "mistralai/mistral-7b-instruct:free"; // Mistral free

  // Paid models:
  static const String chatModel = "deepseek/deepseek-chat"; // Paid
  static const String coderModel = "deepseek/deepseek-coder"; // Paid

  // 📊 Generation Parameters (can be adjusted as needed)
  static const double defaultTemperature =
      0.7; // 0.0 = deterministic, 1.0 = creative
  static const int defaultMaxTokens = 2000; // Maximum response length
  static const double defaultTopP = 0.9; // Nucleus sampling

  // ⏱️ Timeout Configuration
  static const Duration requestTimeout = Duration(seconds: 60);
  static const Duration connectionTimeout = Duration(seconds: 30);

  // 🔧 Feature Flags
  static const bool enableStreaming = false; // Enable streaming responses
  static const bool enableLogging = true; // Enable API call logging

  // Validation
  static bool get isConfigured =>
      apiKey.isNotEmpty && apiKey.startsWith("sk-or-v1-");
}
