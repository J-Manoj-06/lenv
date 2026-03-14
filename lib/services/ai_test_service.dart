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
library;

import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config/ai_config.dart';
import '../config/ai_test_config.dart';
import '../models/test_question.dart';
import '../exceptions/ai_exceptions.dart';

class AITestService {
  final http.Client _client;
  final FirebaseFirestore _firestore;
  final Random _random = Random();

  static const int _maxScopedQuestionReads = 200;
  static const int _maxStoredEmbeddings = 400;
  static const int _maxRecentFingerprints = 600;
  static const double _semanticThreshold = 0.85;
  static const Duration _memoryCacheTtl = Duration(minutes: 8);

  static final Map<String, _ScopedMemoryCache> _scopedMemoryCache =
      <String, _ScopedMemoryCache>{};
  static final Map<String, List<double>> _embeddingCache =
      <String, List<double>>{};
  static final Map<String, DateTime> _recentFingerprintCache =
      <String, DateTime>{};

  /// Create service with optional custom HTTP client (for testing)
  AITestService({http.Client? client, FirebaseFirestore? firestore})
    : _client = client ?? http.Client(),
      _firestore = firestore ?? FirebaseFirestore.instance;

  /// Generate test questions using AI
  ///
  /// Parameters:
  /// - [className]: Grade/class name (e.g., "Grade 8")
  /// - [section]: Section name (e.g., "A")
  /// - [subject]: Subject name (e.g., "Mathematics")
  /// - [topic]: Specific topic for the test (e.g., "Pythagorean Theorem")
  /// - [difficulty]: Difficulty level (Easy, Medium, Hard, Mixed)
  /// - [totalMarks]: Total marks for the entire test
  /// - [numQuestions]: Number of questions to generate
  /// - [schoolId]: Institute/school identifier for scoped duplicate checks
  /// - [teacherId]: Teacher identifier for question bank traceability
  /// - [sectionId]: Optional section identifier (if different from section label)
  /// - [testTitle]: Optional title to store in metadata (source is test document)
  /// - [sourceTestId]: Optional source test id if known while generating
  /// - [previousQuestions]: Kept for backward compatibility; not sent to AI
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
    required String difficulty,
    required int totalMarks,
    required int numQuestions,
    String? schoolId,
    String? teacherId,
    String? sectionId,
    String? testTitle,
    String? sourceTestId,
    List<Map<String, dynamic>>? previousQuestions,
    List<Map<String, dynamic>>? difficultQuestions,
  }) async {
    // Validate inputs
    _validateInputs(
      className: className,
      section: section,
      subject: subject,
      topic: topic,
      difficulty: difficulty,
      totalMarks: totalMarks,
      numQuestions: numQuestions,
    );

    final scope = _QuestionScope(
      schoolId: (schoolId ?? '').trim(),
      standard: className.trim(),
      sectionId: (sectionId ?? section).trim(),
      subject: subject.trim(),
      topic: topic.trim(),
      difficultyLevel: difficulty.trim(),
    );

    final scopedMemory = await _loadScopedQuestionMemory(scope);
    final candidatesNeeded = _initialCandidateCount(numQuestions);

    final approvedQuestions = <TestQuestion>[];
    final exactFingerprints = <String>{...scopedMemory.fingerprints};
    final approvedVectors = <List<double>>[];
    final semanticReviewFallback = <TestQuestion>[];

    int rounds = 0;
    while (approvedQuestions.length < numQuestions && rounds < 4) {
      final remaining = numQuestions - approvedQuestions.length;
      final requestCount = max(
        remaining + 2,
        min(candidatesNeeded, remaining + 8),
      );

      final prompt = _buildPrompt(
        className: className,
        section: section,
        subject: subject,
        topic: topic,
        difficulty: difficulty,
        totalMarks: totalMarks,
        numQuestions: requestCount,
        previousQuestions: previousQuestions,
        difficultQuestions: difficultQuestions,
      );

      final responseContent = await _callProxyWithRetry(prompt);
      final generatedCandidates = _parseResponse(responseContent);

      for (final candidate in generatedCandidates) {
        if (approvedQuestions.length >= numQuestions) break;

        final normalized = _normalizeQuestionText(candidate.questionText);
        final fingerprint = _fingerprint(normalized);

        if (exactFingerprints.contains(fingerprint) ||
            _recentFingerprintCache.containsKey(fingerprint)) {
          continue;
        }

        final embedding = _safeVectorize(normalized);
        final semanticCheck = _isSemanticallyDuplicate(
          embedding,
          scopedMemory.embeddings,
          approvedVectors,
        );

        if (semanticCheck.duplicate) {
          continue;
        }

        if (semanticCheck.reviewOnly) {
          semanticReviewFallback.add(candidate);
          continue;
        }

        approvedQuestions.add(candidate);
        exactFingerprints.add(fingerprint);
        _trackRecentFingerprint(fingerprint);
        if (embedding != null) {
          approvedVectors.add(embedding);
          _cacheEmbedding(normalized, embedding);
        }
      }

      rounds++;
    }

    // Fallback: if semantic flow failed frequently, allow review-only candidates
    // while still enforcing exact duplicate prevention.
    if (approvedQuestions.length < numQuestions &&
        semanticReviewFallback.isNotEmpty) {
      for (final candidate in semanticReviewFallback) {
        if (approvedQuestions.length >= numQuestions) break;
        final normalized = _normalizeQuestionText(candidate.questionText);
        final fingerprint = _fingerprint(normalized);
        if (exactFingerprints.contains(fingerprint) ||
            _recentFingerprintCache.containsKey(fingerprint)) {
          continue;
        }

        approvedQuestions.add(candidate);
        exactFingerprints.add(fingerprint);
        _trackRecentFingerprint(fingerprint);
      }
    }

    if (approvedQuestions.isEmpty) {
      throw ParseException('No unique questions could be generated.');
    }

    final finalQuestions = approvedQuestions.take(numQuestions).toList();
    _distributeMarks(finalQuestions, totalMarks);
    _validateUniqueness(finalQuestions);

    await _storeApprovedQuestions(
      scope: scope,
      questions: finalQuestions,
      teacherId: (teacherId ?? '').trim(),
      testTitle: (testTitle ?? '').trim(),
      sourceTestId: (sourceTestId ?? '').trim(),
    );

    return finalQuestions;
  }

  /// Validate input parameters
  void _validateInputs({
    required String className,
    required String section,
    required String subject,
    required String topic,
    required String difficulty,
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
    final validDifficulties = ['Easy', 'Medium', 'Hard', 'Mixed'];
    if (!validDifficulties.contains(difficulty)) {
      errors['difficulty'] = 'Invalid difficulty level';
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
    required String difficulty,
    required int totalMarks,
    required int numQuestions,
    List<Map<String, dynamic>>? previousQuestions,
    List<Map<String, dynamic>>? difficultQuestions,
  }) {
    final buffer = StringBuffer();

    // Keep prompt compact to reduce token cost. Duplicate prevention is handled locally.
    buffer.writeln(
      'Generate $numQuestions questions for $className $section, subject $subject, topic "$topic", difficulty $difficulty.',
    );
    buffer.writeln('Return only JSON array with schema:');
    buffer.writeln(
      '[{"type":"mcq|truefalse","questionText":"...","marks":1,"options":["A","B","C","D"],"correctAnswer":"A|B|C|D|true|false"}]',
    );
    buffer.writeln('Rules:');
    buffer.writeln('1) MCQ must have 4 options and one correct letter A-D.');
    buffer.writeln(
      '2) truefalse must not include options; answer true or false.',
    );
    buffer.writeln('3) Keep wording concise and curriculum-aligned.');
    buffer.writeln('4) No markdown, no explanation, JSON only.');

    return buffer.toString();
  }

  int _initialCandidateCount(int requested) {
    if (requested <= 3) return requested + 3;
    return requested + max(2, (requested * 0.6).ceil());
  }

  /// Call proxy with exponential backoff retry
  Future<String> _callProxyWithRetry(String prompt) async {
    int attempt = 0;
    Duration delay = AITestConfig.initialRetryDelay;

    while (attempt <= AITestConfig.maxRetries) {
      try {
        final content = await _callProxy(prompt);
        return content;
      } on RateLimitException {
        rethrow; // Don't retry rate limits
      } on TimeoutException {
        if (attempt == AITestConfig.maxRetries) rethrow;
      } on NetworkException {
        if (attempt == AITestConfig.maxRetries) rethrow;
      } on ApiException catch (e) {
        // Don't retry client errors (4xx)
        if (e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500) {
          rethrow;
        }
        if (attempt == AITestConfig.maxRetries) rethrow;
      }

      // Calculate delay with jitter
      final jitter = _random.nextInt(1000); // 0-1000ms jitter
      final totalDelay = delay.inMilliseconds + jitter;

      await Future.delayed(Duration(milliseconds: totalDelay));

      // Exponential backoff
      delay *= 2;
      attempt++;
    }

    throw NetworkException('Failed after ${AITestConfig.maxRetries} retries');
  }

  /// Call the AI proxy (Firebase Cloud Function or Direct API)
  Future<String> _callProxy(String prompt) async {
    // Print configuration status
    AITestConfig.printStatus();

    // Check if configured
    if (!AITestConfig.isConfigured) {
      throw ApiException(AITestConfig.statusMessage, statusCode: 401);
    }

    try {
      final requestBody = jsonEncode({
        'model': AITestConfig.model,
        'messages': [
          {'role': 'system', 'content': AITestConfig.systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': AITestConfig.temperature,
        'max_tokens': AITestConfig.maxTokens,
      });

      final response = await _client
          .post(
            Uri.parse(AITestConfig.apiEndpoint),
            headers: AITestConfig.headers,
            body: requestBody,
          )
          .timeout(
            AITestConfig.requestTimeout,
            onTimeout: () {
              throw TimeoutException(
                'Request timed out after ${AIConfig.requestTimeout.inSeconds}s',
                timeoutSeconds: AIConfig.requestTimeout.inSeconds,
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

  Future<_ScopedQuestionMemory> _loadScopedQuestionMemory(
    _QuestionScope scope,
  ) async {
    if (scope.schoolId.isEmpty) {
      return const _ScopedQuestionMemory(entries: []);
    }

    final cacheKey = scope.cacheKey;
    final cached = _scopedMemoryCache[cacheKey];
    final now = DateTime.now();
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.memory;
    }

    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('question_bank')
          .where('schoolId', isEqualTo: scope.schoolId)
          .where('standard', isEqualTo: scope.standard)
          .where('subject', isEqualTo: scope.subject)
          .where('topic', isEqualTo: scope.topic)
          .limit(_maxScopedQuestionReads);

      if (scope.sectionId.isNotEmpty) {
        query = query.where('sectionId', isEqualTo: scope.sectionId);
      }

      final snap = await query.get();
      final entries = snap.docs
          .map((doc) {
            final data = doc.data();
            final normalized =
                (data['normalizedText'] as String?)?.trim() ?? '';
            final fingerprint = (data['fingerprint'] as String?)?.trim() ?? '';
            final embeddingRaw = data['embeddingVector'];
            final embedding = _parseEmbedding(embeddingRaw);

            return _QuestionMemoryEntry(
              normalizedText: normalized,
              fingerprint: fingerprint,
              embedding: embedding,
            );
          })
          .where((e) => e.fingerprint.isNotEmpty || e.normalizedText.isNotEmpty)
          .toList();

      final memory = _ScopedQuestionMemory(entries: entries);
      _scopedMemoryCache[cacheKey] = _ScopedMemoryCache(
        memory: memory,
        expiresAt: now.add(_memoryCacheTtl),
      );
      return memory;
    } catch (_) {
      // Network or query failure: allow generation to continue with local checks.
      return const _ScopedQuestionMemory(entries: []);
    }
  }

  Future<void> _storeApprovedQuestions({
    required _QuestionScope scope,
    required List<TestQuestion> questions,
    required String teacherId,
    required String testTitle,
    required String sourceTestId,
  }) async {
    if (scope.schoolId.isEmpty || questions.isEmpty) return;

    final batch = _firestore.batch();
    for (final question in questions) {
      final normalized = _normalizeQuestionText(question.questionText);
      final fingerprint = _fingerprint(normalized);
      final embedding = _safeVectorize(normalized);

      final docRef = _firestore.collection('question_bank').doc();
      batch.set(docRef, {
        'questionId': docRef.id,
        'schoolId': scope.schoolId,
        'standard': scope.standard,
        'sectionId': scope.sectionId,
        'subject': scope.subject,
        'topic': scope.topic,
        'difficultyLevel': scope.difficultyLevel,
        'questionText': question.questionText,
        'normalizedText': normalized,
        'fingerprint': fingerprint,
        if (embedding != null) 'embeddingVector': embedding,
        'questionFormat': question.type.toStringValue(),
        'answerOptions': question.options,
        'correctAnswer': question.correctAnswer,
        'marks': question.marks,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByTeacherId': teacherId,
        'sourceTestId': sourceTestId,
        if (testTitle.isNotEmpty) 'sourceTestTitle': testTitle,
      });
    }

    try {
      await batch.commit();

      // Invalidate scoped cache for fresh future reads.
      _scopedMemoryCache.remove(scope.cacheKey);
    } catch (_) {
      // Non-blocking: question bank write failure should not fail test generation.
    }
  }

  String _normalizeQuestionText(String text) {
    String normalized = text.toLowerCase();

    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\d+'), '#');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return normalized;
  }

  String _fingerprint(String normalizedText) {
    return sha256.convert(utf8.encode(normalizedText)).toString();
  }

  List<double>? _safeVectorize(String normalizedText) {
    try {
      if (_embeddingCache.containsKey(normalizedText)) {
        return _embeddingCache[normalizedText];
      }

      final tokens = normalizedText
          .split(' ')
          .where((t) => t.isNotEmpty && t.length > 1)
          .toList();

      if (tokens.isEmpty) return null;

      const size = 64;
      final vector = List<double>.filled(size, 0);
      for (final token in tokens) {
        final idx = token.hashCode.abs() % size;
        vector[idx] += 1.0;
      }

      double norm = 0;
      for (final v in vector) {
        norm += v * v;
      }
      norm = sqrt(norm);
      if (norm == 0) return null;

      for (var i = 0; i < vector.length; i++) {
        vector[i] = vector[i] / norm;
      }

      _cacheEmbedding(normalizedText, vector);
      return vector;
    } catch (_) {
      return null;
    }
  }

  _SemanticDuplicateResult _isSemanticallyDuplicate(
    List<double>? candidateVector,
    List<List<double>> historicalVectors,
    List<List<double>> currentVectors,
  ) {
    if (candidateVector == null) {
      return const _SemanticDuplicateResult(reviewOnly: true, duplicate: false);
    }

    try {
      for (final vector in historicalVectors) {
        if (_cosineSimilarity(candidateVector, vector) > _semanticThreshold) {
          return const _SemanticDuplicateResult(
            duplicate: true,
            reviewOnly: false,
          );
        }
      }

      for (final vector in currentVectors) {
        if (_cosineSimilarity(candidateVector, vector) > _semanticThreshold) {
          return const _SemanticDuplicateResult(
            duplicate: true,
            reviewOnly: false,
          );
        }
      }

      return const _SemanticDuplicateResult(
        duplicate: false,
        reviewOnly: false,
      );
    } catch (_) {
      // If embedding/similarity check fails, keep question but mark as review-only.
      return const _SemanticDuplicateResult(reviewOnly: true, duplicate: false);
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;

    double dot = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  List<double>? _parseEmbedding(dynamic raw) {
    if (raw is! List) return null;
    try {
      return raw.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  void _cacheEmbedding(String normalizedText, List<double> vector) {
    _embeddingCache[normalizedText] = vector;
    if (_embeddingCache.length > _maxStoredEmbeddings) {
      final firstKey = _embeddingCache.keys.first;
      _embeddingCache.remove(firstKey);
    }
  }

  void _trackRecentFingerprint(String fingerprint) {
    _recentFingerprintCache[fingerprint] = DateTime.now();
    if (_recentFingerprintCache.length > _maxRecentFingerprints) {
      final firstKey = _recentFingerprintCache.keys.first;
      _recentFingerprintCache.remove(firstKey);
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

class _QuestionScope {
  final String schoolId;
  final String standard;
  final String sectionId;
  final String subject;
  final String topic;
  final String difficultyLevel;

  const _QuestionScope({
    required this.schoolId,
    required this.standard,
    required this.sectionId,
    required this.subject,
    required this.topic,
    required this.difficultyLevel,
  });

  String get cacheKey =>
      '$schoolId|$standard|$sectionId|$subject|$topic|$difficultyLevel';
}

class _QuestionMemoryEntry {
  final String normalizedText;
  final String fingerprint;
  final List<double>? embedding;

  const _QuestionMemoryEntry({
    required this.normalizedText,
    required this.fingerprint,
    this.embedding,
  });
}

class _ScopedQuestionMemory {
  final List<_QuestionMemoryEntry> entries;

  const _ScopedQuestionMemory({required this.entries});

  Set<String> get fingerprints =>
      entries.map((e) => e.fingerprint).where((v) => v.isNotEmpty).toSet();

  List<List<double>> get embeddings =>
      entries.map((e) => e.embedding).whereType<List<double>>().toList();
}

class _ScopedMemoryCache {
  final _ScopedQuestionMemory memory;
  final DateTime expiresAt;

  const _ScopedMemoryCache({required this.memory, required this.expiresAt});
}

class _SemanticDuplicateResult {
  final bool duplicate;
  final bool reviewOnly;

  const _SemanticDuplicateResult({
    required this.duplicate,
    required this.reviewOnly,
  });
}
