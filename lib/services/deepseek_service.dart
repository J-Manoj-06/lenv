import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/deepseek_config.dart';

/// DeepSeek AI Service
/// Handles all interactions with DeepSeek API for AI-powered features
class DeepSeekService {
  // Singleton pattern
  static final DeepSeekService _instance = DeepSeekService._internal();
  factory DeepSeekService() => _instance;
  DeepSeekService._internal();

  /// Generate test questions using DeepSeek AI via OpenRouter
  ///
  /// Returns a list of generated questions with answers
  Future<List<Map<String, dynamic>>> generateTestQuestions({
    required String subject,
    required String topics,
    required int questionCount,
    required String difficulty,
    required String grade,
  }) async {
    if (!DeepSeekConfig.isConfigured) {
      throw Exception(
        'OpenRouter API key not configured properly. Please check your API key in lib/core/config/deepseek_config.dart',
      );
    }

    final prompt = _buildTestGenerationPrompt(
      subject: subject,
      topics: topics,
      questionCount: questionCount,
      difficulty: difficulty,
      grade: grade,
    );

    try {
      final response = await _makeApiCall(
        prompt: prompt,
        temperature: 0.7,
        maxTokens: 3000,
      );

      return _parseTestQuestions(response);
    } catch (e) {
      if (DeepSeekConfig.enableLogging) {
        print('Error generating test questions: $e');
      }
      rethrow;
    }
  }

  /// Build a prompt for test question generation
  String _buildTestGenerationPrompt({
    required String subject,
    required String topics,
    required int questionCount,
    required String difficulty,
    required String grade,
  }) {
    return '''You are an expert teacher creating exam questions for Grade $grade students.

Subject: $subject
Topics: $topics
Difficulty Level: $difficulty
Number of Questions: $questionCount

Please generate $questionCount multiple-choice questions following these guidelines:

1. Each question should have:
   - A clear, well-written question
   - Four answer options (A, B, C, D)
   - The correct answer marked clearly
   - A brief explanation of why the answer is correct
   - Appropriate difficulty level ($difficulty)

2. Format your response as a JSON array of objects with this structure:
[
  {
    "question": "What is...",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correctAnswer": "A",
    "explanation": "The correct answer is A because...",
    "topic": "Specific topic",
    "difficulty": "$difficulty",
    "points": 1
  }
]

3. Ensure questions are:
   - Age-appropriate for Grade $grade
   - Focused on the specified topics
   - Varied in format and style
   - Free from ambiguity
   - Educational and engaging

Generate the questions now in valid JSON format only (no additional text):''';
  }

  /// Make an API call to OpenRouter (DeepSeek model)
  Future<String> _makeApiCall({
    required String prompt,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    final url = Uri.parse(
      '${DeepSeekConfig.baseUrl}/${DeepSeekConfig.apiVersion}/chat/completions',
    );

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${DeepSeekConfig.apiKey}',
      // OpenRouter-specific headers
      if (DeepSeekConfig.siteUrl.isNotEmpty)
        'HTTP-Referer': DeepSeekConfig.siteUrl,
      if (DeepSeekConfig.siteName.isNotEmpty)
        'X-Title': DeepSeekConfig.siteName,
    };

    final body = jsonEncode({
      'model': model ?? DeepSeekConfig.defaultModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': temperature ?? DeepSeekConfig.defaultTemperature,
      'max_tokens': maxTokens ?? DeepSeekConfig.defaultMaxTokens,
      'top_p': DeepSeekConfig.defaultTopP,
    });

    if (DeepSeekConfig.enableLogging) {
      print('OpenRouter API Request (DeepSeek model):');
      print('URL: $url');
      print('Model: ${model ?? DeepSeekConfig.defaultModel}');
      print('Temperature: ${temperature ?? DeepSeekConfig.defaultTemperature}');
      print('Max Tokens: ${maxTokens ?? DeepSeekConfig.defaultMaxTokens}');
    }

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(DeepSeekConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;

        if (DeepSeekConfig.enableLogging) {
          print('OpenRouter API Response received successfully');
          print('Tokens used: ${data['usage']?['total_tokens'] ?? 'N/A'}');
          print('Model used: ${data['model'] ?? 'N/A'}');
        }

        return content;
      } else {
        if (DeepSeekConfig.enableLogging) {
          print('OpenRouter API Error Response: ${response.body}');
        }
        final error = jsonDecode(response.body);
        throw Exception(
          'OpenRouter API Error (${response.statusCode}): ${error['error']?['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      if (DeepSeekConfig.enableLogging) {
        print('OpenRouter API Error: $e');
      }
      rethrow;
    }
  }

  /// Parse test questions from API response
  List<Map<String, dynamic>> _parseTestQuestions(String response) {
    try {
      // Try to extract JSON from response
      String jsonStr = response.trim();

      // Remove markdown code blocks if present
      if (jsonStr.startsWith('```json')) {
        jsonStr = jsonStr.substring(7);
      }
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.substring(3);
      }
      if (jsonStr.endsWith('```')) {
        jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      }
      jsonStr = jsonStr.trim();

      // Parse JSON
      final List<dynamic> questions = jsonDecode(jsonStr);

      return questions.map((q) {
        final map = q as Map<String, dynamic>;
        return {
          'question': map['question'] ?? '',
          'options': List<String>.from(map['options'] ?? []),
          'correctAnswer': map['correctAnswer'] ?? 'A',
          'explanation': map['explanation'] ?? '',
          'topic': map['topic'] ?? '',
          'difficulty': map['difficulty'] ?? 'Medium',
          'points': map['points'] ?? 1,
        };
      }).toList();
    } catch (e) {
      if (DeepSeekConfig.enableLogging) {
        print('Error parsing test questions: $e');
        print('Response: $response');
      }
      throw Exception(
        'Failed to parse AI response. The AI may have returned invalid JSON.',
      );
    }
  }

  /// Generate feedback for student work
  Future<String> generateFeedback({
    required String studentWork,
    required String question,
    required String correctAnswer,
  }) async {
    if (!DeepSeekConfig.isConfigured) {
      throw Exception('OpenRouter API key not configured');
    }

    final prompt =
        '''You are a helpful teacher providing constructive feedback.

Question: $question
Correct Answer: $correctAnswer
Student's Answer: $studentWork

Please provide:
1. Whether the answer is correct or not
2. Specific feedback on what was done well
3. Suggestions for improvement (if needed)
4. Encouragement

Keep the feedback positive, constructive, and age-appropriate.''';

    try {
      return await _makeApiCall(
        prompt: prompt,
        temperature: 0.6,
        maxTokens: 500,
      );
    } catch (e) {
      if (DeepSeekConfig.enableLogging) {
        print('Error generating feedback: $e');
      }
      rethrow;
    }
  }

  /// Generate study tips for a topic
  Future<String> generateStudyTips({
    required String subject,
    required String topic,
    required String grade,
  }) async {
    if (!DeepSeekConfig.isConfigured) {
      throw Exception('OpenRouter API key not configured');
    }

    final prompt =
        '''You are an experienced teacher helping a Grade $grade student.

Subject: $subject
Topic: $topic

Please provide:
1. 3-5 key concepts to understand
2. 3-5 practical study tips
3. Common mistakes to avoid
4. Recommended practice activities

Keep the advice clear, practical, and age-appropriate for Grade $grade.''';

    try {
      return await _makeApiCall(
        prompt: prompt,
        temperature: 0.7,
        maxTokens: 1000,
      );
    } catch (e) {
      if (DeepSeekConfig.enableLogging) {
        print('Error generating study tips: $e');
      }
      rethrow;
    }
  }
}
