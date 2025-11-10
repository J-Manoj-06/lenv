/// AI Test Generation Service
///
/// This service handles communication with the AI proxy server to generate
/// test questions based on educational parameters.
///
/// Features:
/// - Secure proxy-based API calls (no API key in app)
/// - Exponential backoff retry logic with jitter
/// - Robust JSON parsing with markdown stripping
/// - Automatic marks distribution
/// - Duplicate question detection
/// - Comprehensive error handling

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../config/ai_config.dart';
import '../models/test_question.dart';
import '../exceptions/ai_exceptions.dart';

class AITestService {
  final http.Client _client;
  final Random _random = Random();

  /// Create service with optional custom HTTP client (for testing)
  AITestService({http.Client? client}) : _client = client ?? http.Client();

  /// Generate test questions using AI
  ///
  /// Parameters:
  /// - [className]: Grade/class name (e.g., "Grade 8")
  /// - [section]: Section name (e.g., "A")
  /// - [subject]: Subject name (e.g., "Mathematics")
  /// - [topic]: Specific topic for the test (e.g., "Pythagorean Theorem")
  /// - [totalMarks]: Total marks for the entire test
  /// - [numQuestions]: Number of questions to generate
  /// - [previousQuestions]: Optional list of recent questions to avoid duplicates
  /// - [difficultQuestions]: Optional list of questions students found difficult
  ///
  /// Returns: List of generated TestQuestion objects
  ///
  /// Throws:
  /// - [NetworkException] if network connection fails
  /// - [RateLimitException] if rate limit is exceeded
  /// - [ApiException] if API returns error
  /// - [ParseException] if response cannot be parsed
  /// - [DuplicateQuestionException] if duplicate questions detected
  /// - [TimeoutException] if request times out
  Future<List<TestQuestion>> generateTest({
    required String className,
    required String section,
    required String subject,
    required String topic,
    required int totalMarks,
    required int numQuestions,
    List<Map<String, dynamic>>? previousQuestions,
    List<Map<String, dynamic>>? difficultQuestions,
  }) async {
    // Validate inputs
    _validateInputs(
      className: className,
      section: section,
      subject: subject,
      topic: topic,
      totalMarks: totalMarks,
      numQuestions: numQuestions,
    );

    // Build the prompt
    final prompt = _buildPrompt(
      className: className,
      section: section,
      subject: subject,
      topic: topic,
      totalMarks: totalMarks,
      numQuestions: numQuestions,
      previousQuestions: previousQuestions,
      difficultQuestions: difficultQuestions,
    );

    // Call the proxy with retry logic
    final responseContent = await _callProxyWithRetry(prompt);

    // Parse and process the response
    final questions = _parseResponse(responseContent);

    // Distribute marks across questions
    _distributeMarks(questions, totalMarks);

    // Validate uniqueness
    _validateUniqueness(questions);

    return questions;
  }

  /// Validate input parameters
  void _validateInputs({
    required String className,
    required String section,
    required String subject,
    required String topic,
    required int totalMarks,
    required int numQuestions,
  }) {
    final errors = <String, String>{};

    if (className.trim().isEmpty) {
      errors['className'] = 'Class name is required';
    }
    if (section.trim().isEmpty) {
      errors['section'] = 'Section is required';
    }
    if (subject.trim().isEmpty) {
      errors['subject'] = 'Subject is required';
    }
    if (topic.trim().isEmpty) {
      errors['topic'] = 'Topic is required';
    }
    if (totalMarks <= 0) {
      errors['totalMarks'] = 'Total marks must be greater than 0';
    }
    if (numQuestions <= 0) {
      errors['numQuestions'] = 'Number of questions must be greater than 0';
    }
    if (numQuestions > 50) {
      errors['numQuestions'] = 'Number of questions cannot exceed 50';
    }
    if (totalMarks < numQuestions) {
      errors['totalMarks'] =
          'Total marks must be at least equal to number of questions';
    }

    if (errors.isNotEmpty) {
      throw ValidationException(
        'Invalid input parameters',
        fieldErrors: errors,
      );
    }
  }

  /// Build the AI prompt
  String _buildPrompt({
    required String className,
    required String section,
    required String subject,
    required String topic,
    required int totalMarks,
    required int numQuestions,
    List<Map<String, dynamic>>? previousQuestions,
    List<Map<String, dynamic>>? difficultQuestions,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Generate $numQuestions test questions for:');
    buffer.writeln('- Class: $className, Section: $section');
    buffer.writeln('- Subject: $subject');
    buffer.writeln('- Topic: $topic');
    buffer.writeln('- Total Marks: $totalMarks');
    buffer.writeln();

    buffer.writeln('REQUIREMENTS:');
    buffer.writeln('1. Create exactly $numQuestions questions');
    buffer.writeln('2. Mix of MCQ (multiple choice) and True/False questions');
    buffer.writeln('3. For MCQ: provide exactly 4 options labeled A, B, C, D');
    buffer.writeln('4. For MCQ: correctAnswer must be "A", "B", "C", or "D"');
    buffer.writeln(
      '5. For True/False: correctAnswer must be "true" or "false" (lowercase)',
    );
    buffer.writeln('6. Questions must be appropriate for $className level');
    buffer.writeln('7. Questions must be clear and unambiguous');
    buffer.writeln('8. Avoid duplicates with previous questions');
    buffer.writeln();

    // Add previous questions context (limit to 5)
    if (previousQuestions != null && previousQuestions.isNotEmpty) {
      buffer.writeln('AVOID these recently used questions:');
      final recent = previousQuestions.take(5);
      for (var i = 0; i < recent.length; i++) {
        final q = recent.elementAt(i);
        buffer.writeln('${i + 1}. ${q['questionText']}');
      }
      buffer.writeln();
    }

    // Add difficult questions context
    if (difficultQuestions != null && difficultQuestions.isNotEmpty) {
      buffer.writeln(
        'Students found these questions difficult (create similar ones):',
      );
      for (var i = 0; i < difficultQuestions.length; i++) {
        final q = difficultQuestions[i];
        buffer.writeln('${i + 1}. ${q['questionText']}');
      }
      buffer.writeln();
    }

    buffer.writeln('OUTPUT FORMAT:');
    buffer.writeln(
      'Return ONLY a JSON array. No markdown code blocks. No explanatory text.',
    );
    buffer.writeln('Example:');
    buffer.writeln('[');
    buffer.writeln('  {');
    buffer.writeln('    "type": "mcq",');
    buffer.writeln('    "questionText": "What is 2 + 2?",');
    buffer.writeln('    "marks": 2,');
    buffer.writeln('    "options": ["3", "4", "5", "6"],');
    buffer.writeln('    "correctAnswer": "B"');
    buffer.writeln('  },');
    buffer.writeln('  {');
    buffer.writeln('    "type": "truefalse",');
    buffer.writeln('    "questionText": "The Earth is flat.",');
    buffer.writeln('    "marks": 1,');
    buffer.writeln('    "correctAnswer": "false"');
    buffer.writeln('  }');
    buffer.writeln(']');

    return buffer.toString();
  }

  /// Call proxy with exponential backoff retry
  Future<String> _callProxyWithRetry(String prompt) async {
    int attempt = 0;
    int delayMs = AIConfig.initialRetryDelayMs;

    while (attempt <= AIConfig.maxRetries) {
      try {
        final content = await _callProxy(prompt);
        return content;
      } on RateLimitException {
        rethrow; // Don't retry rate limits
      } on TimeoutException {
        if (attempt == AIConfig.maxRetries) rethrow;
      } on NetworkException {
        if (attempt == AIConfig.maxRetries) rethrow;
      } on ApiException catch (e) {
        // Don't retry client errors (4xx)
        if (e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500) {
          rethrow;
        }
        if (attempt == AIConfig.maxRetries) rethrow;
      }

      // Calculate delay with jitter
      final jitter = _random.nextInt(1000); // 0-1000ms jitter
      final totalDelay = delayMs + jitter;
      final cappedDelay = totalDelay > AIConfig.maxRetryDelayMs
          ? AIConfig.maxRetryDelayMs
          : totalDelay;

      print(
        'Retry attempt ${attempt + 1}/${AIConfig.maxRetries} after ${cappedDelay}ms',
      );

      await Future.delayed(Duration(milliseconds: cappedDelay));

      // Exponential backoff
      delayMs *= 2;
      attempt++;
    }

    throw NetworkException('Failed after ${AIConfig.maxRetries} retries');
  }

  /// Call the AI proxy
  Future<String> _callProxy(String prompt) async {
    try {
      final requestBody = jsonEncode({
        'model': AIConfig.model,
        'messages': [
          {'role': 'system', 'content': AIConfig.systemMessage},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': AIConfig.temperature,
        'max_tokens': AIConfig.maxTokens,
      });

      print('Calling AI API: ${AIConfig.proxyUrl}');
      print('Using model: ${AIConfig.model}');

      final response = await _client
          .post(
            Uri.parse(AIConfig.proxyUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${AIConfig.apiKey}',
              'HTTP-Referer': AIConfig.siteUrl.isNotEmpty
                  ? AIConfig.siteUrl
                  : 'https://education-rewards-app.com',
              'X-Title': AIConfig.siteName,
            },
            body: requestBody,
          )
          .timeout(
            Duration(seconds: AIConfig.requestTimeoutSeconds),
            onTimeout: () {
              throw TimeoutException(
                'Request timed out',
                timeoutSeconds: AIConfig.requestTimeoutSeconds,
              );
            },
          );

      // Handle rate limiting
      if (response.statusCode == 429) {
        final retryAfter = int.tryParse(
          response.headers['retry-after'] ?? '60',
        );
        throw RateLimitException(
          'Rate limit exceeded',
          retryAfterSeconds: retryAfter,
        );
      }

      // Handle other HTTP errors
      if (response.statusCode != 200) {
        throw ApiException(
          'API request failed',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }

      // Parse response
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      // Extract content from response
      // Support both OpenAI-style and direct content responses
      String? content;

      if (responseData.containsKey('choices')) {
        // OpenAI-style response
        final choices = responseData['choices'] as List<dynamic>;
        if (choices.isNotEmpty) {
          final firstChoice = choices[0] as Map<String, dynamic>;
          final message = firstChoice['message'] as Map<String, dynamic>;
          content = message['content'] as String?;
        }
      } else if (responseData.containsKey('content')) {
        // Direct content response
        content = responseData['content'] as String?;
      } else if (responseData.containsKey('response')) {
        // Alternative response format
        content = responseData['response'] as String?;
      }

      if (content == null || content.isEmpty) {
        throw ParseException(
          'No content in response',
          rawResponse: response.body,
        );
      }

      return content;
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network request failed',
        details: e.message,
        originalError: e,
      );
    } on FormatException catch (e) {
      throw ParseException(
        'Invalid JSON response from proxy',
        details: e.message,
        originalError: e,
      );
    } catch (e) {
      if (e is AIException) rethrow;
      throw NetworkException(
        'Unexpected error during API call',
        details: e.toString(),
        originalError: e,
      );
    }
  }

  /// Parse AI response into TestQuestion objects
  List<TestQuestion> _parseResponse(String content) {
    try {
      // Clean the content - remove markdown code blocks if present
      String cleanedContent = _cleanJsonContent(content);

      // Parse JSON array
      final dynamic parsed = jsonDecode(cleanedContent);

      if (parsed is! List) {
        throw ParseException(
          'Response is not a JSON array',
          rawResponse: content,
        );
      }

      // Convert to TestQuestion objects
      final questions = <TestQuestion>[];
      for (var i = 0; i < parsed.length; i++) {
        try {
          final questionData = parsed[i] as Map<String, dynamic>;
          final question = TestQuestion.fromJson(questionData);

          if (!question.isValid()) {
            throw ParseException(
              'Invalid question at index $i',
              details: 'Question failed validation: ${question.toString()}',
              rawResponse: content,
            );
          }

          questions.add(question);
        } catch (e) {
          throw ParseException(
            'Failed to parse question at index $i',
            details: e.toString(),
            rawResponse: content,
          );
        }
      }

      if (questions.isEmpty) {
        throw ParseException(
          'No valid questions generated',
          rawResponse: content,
        );
      }

      return questions;
    } on FormatException catch (e) {
      throw ParseException(
        'Invalid JSON format',
        details: e.message,
        rawResponse: content,
        originalError: e,
      );
    } catch (e) {
      if (e is AIException) rethrow;
      throw ParseException(
        'Failed to parse response',
        details: e.toString(),
        rawResponse: content,
        originalError: e,
      );
    }
  }

  /// Clean JSON content by removing markdown code blocks
  String _cleanJsonContent(String content) {
    String cleaned = content.trim();

    // Remove leading ```json or ``` markers
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7).trim();
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3).trim();
    }

    // Remove trailing ``` marker
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3).trim();
    }

    return cleaned;
  }

  /// Distribute marks evenly across questions
  void _distributeMarks(List<TestQuestion> questions, int totalMarks) {
    if (questions.isEmpty) return;

    final baseMarks = totalMarks ~/ questions.length;
    final remainder = totalMarks % questions.length;

    for (var i = 0; i < questions.length; i++) {
      // Distribute remainder to first few questions
      final marks = baseMarks + (i < remainder ? 1 : 0);
      questions[i] = questions[i].copyWith(marks: marks);
    }
  }

  /// Validate that there are no duplicate questions
  void _validateUniqueness(List<TestQuestion> questions) {
    final seen = <String>{};
    final duplicates = <String>[];

    for (final question in questions) {
      final normalized = question.normalizedText;
      if (seen.contains(normalized)) {
        duplicates.add(question.questionText);
      } else {
        seen.add(normalized);
      }
    }

    if (duplicates.isNotEmpty) {
      throw DuplicateQuestionException(
        'Duplicate questions detected',
        duplicateQuestions: duplicates,
      );
    }
  }

  /// Get a sample mock response for testing UI without proxy
  static String getMockResponse() {
    return jsonEncode([
      {
        'type': 'mcq',
        'questionText': 'What is the capital of France?',
        'marks': 2,
        'options': ['London', 'Paris', 'Berlin', 'Madrid'],
        'correctAnswer': 'B',
      },
      {
        'type': 'truefalse',
        'questionText': 'The Earth is flat.',
        'marks': 1,
        'correctAnswer': 'false',
      },
      {
        'type': 'mcq',
        'questionText': 'Which planet is known as the Red Planet?',
        'marks': 2,
        'options': ['Venus', 'Mars', 'Jupiter', 'Saturn'],
        'correctAnswer': 'B',
      },
      {
        'type': 'mcq',
        'questionText': 'What is 12 × 12?',
        'marks': 2,
        'options': ['124', '134', '144', '154'],
        'correctAnswer': 'C',
      },
      {
        'type': 'truefalse',
        'questionText': 'Water boils at 100°C at sea level.',
        'marks': 1,
        'correctAnswer': 'true',
      },
    ]);
  }

  /// Dispose resources
  void dispose() {
    _client.close();
  }
}
