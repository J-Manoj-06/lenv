import 'dart:convert';
import 'package:http/http.dart' as http;

class DeepSeekService {
  static const String _apiUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const String _apiKey =
      'sk-ecd0161142054f39bb8b2d40545232c1'; // Add your DeepSeek API key here: sk-...

  Future<String> chat(String userMessage) async {
    // Check if API key is configured
    if (_apiKey.isEmpty || _apiKey == 'YOUR_DEEPSEEK_API_KEY') {
      return '''⚠️ **API Key Not Configured**

To use the AI Tutor, you need a DeepSeek API key:

1. Visit: https://platform.deepseek.com/
2. Sign up and get your API key
3. Add it to: lib/services/deepseek_service.dart (line 6)

**For now, here's a helpful response about "$userMessage":**

${_getFallbackResponse(userMessage)}''';
    }

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are an AI tutor. Answer the user succinctly in plain text, no markdown, no headings, no lists, no emojis. Provide only the essential explanation in 3-5 short lines. Do not add prefaces like "Of course" or "Here\'s"—just the answer.',
            },
            {'role': 'user', 'content': userMessage},
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['choices'][0]['message']['content'] ?? '';
        return _toPlainAndTrim(raw);
      } else {
        final errorData = jsonDecode(response.body);
        return '⚠️ API Error: ${errorData['error']?['message'] ?? response.body}\n\nPlease check your API key in lib/services/deepseek_service.dart';
      }
    } catch (e) {
      return '⚠️ Connection failed: $e\n\nFallback answer:\n${_getFallbackResponse(userMessage)}';
    }
  }

  String _getFallbackResponse(String question) {
    return '''I understand you're asking about: "$question"

To answer this properly, I need an active API connection. Here's a general approach:

1. **Identify key concepts** - Break down what you're asking
2. **Research the topic** - Look for reliable sources
3. **Apply step-by-step logic** - Work through the problem systematically
4. **Verify your answer** - Check if it makes sense

💡 Tip: Try searching educational resources for detailed explanations!''';
  }

  // Streamed chat: emits partial content as it arrives for typewriter effect
  Future<void> chatStream(
    String userMessage,
    void Function(String delta) onChunk,
  ) async {
    if (_apiKey.isEmpty || _apiKey == 'YOUR_DEEPSEEK_API_KEY') {
      onChunk(_toPlainAndTrim(_getFallbackResponse(userMessage)));
      return;
    }

    try {
      final requestBody = jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are an AI tutor. Answer succinctly in plain text, no markdown, no headings, no lists, no emojis. Provide only the essential explanation in 3-5 short lines. No prefaces.',
          },
          {'role': 'user', 'content': userMessage},
        ],
        'temperature': 0.7,
        'max_tokens': 200,
        'stream': true,
      });

      final request = http.Request('POST', Uri.parse(_apiUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      });
      request.body = requestBody;

      final response = await request.send();
      if (response.statusCode != 200) {
        onChunk('⚠️ API Error (${response.statusCode}).');
        return;
      }

      // Parse SSE lines: each line starts with 'data: {'...'}'
      final stream = response.stream.transform(const Utf8Decoder());
      await for (final chunk in stream) {
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('data:')) continue;
          final payload = trimmed.substring(5).trim();
          if (payload == '[DONE]') {
            return;
          }
          try {
            final json = jsonDecode(payload);
            final delta = json['choices']?[0]?['delta']?['content'];
            if (delta is String && delta.isNotEmpty) {
              onChunk(_sanitizeInline(delta));
            }
          } catch (_) {
            // ignore malformed lines
          }
        }
      }
    } catch (e) {
      onChunk('⚠️ Connection failed: $e');
    }
  }

  // Convert markdown-ish content to plain, then keep first 5 non-empty lines
  String _toPlainAndTrim(String input) {
    var s = _sanitizeInline(input);
    final lines = s
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length > 5) {
      lines.removeRange(5, lines.length);
    }
    return lines.join('\n');
  }

  // Remove markdown markers like ###, **bold**, bullets, repeated dashes
  String _sanitizeInline(String input) {
    var s = input
        .replaceAll(RegExp(r'^\s*#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'^\s*[-•]\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s*---\s*'), '\n')
        .replaceAll(RegExp(r'`{1,3}'), '')
        .replaceAll(RegExp(r'_([^_]+)_'), r'$1');
    // Collapse multiple blank lines
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s;
  }

  Future<Map<String, dynamic>> generateQuiz(
    String topic,
    int numQuestions,
  ) async {
    // Check if API key is configured
    if (_apiKey.isEmpty || _apiKey == 'YOUR_DEEPSEEK_API_KEY') {
      return _getFallbackQuiz(topic, numQuestions);
    }

    try {
      final prompt =
          '''Generate a quiz on "$topic" with $numQuestions multiple choice questions.
Format your response as JSON:
{
  "title": "$topic Quiz",
  "questions": [
    {
      "question": "Question text?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correctIndex": 0
    }
  ]
}
Only return valid JSON, no extra text.''';

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a quiz generator. Always respond with valid JSON only.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.8,
          'max_tokens': 2000,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];

        // Try to extract JSON from markdown code blocks if present
        String jsonContent = content;
        if (content.contains('```json')) {
          jsonContent = content.split('```json')[1].split('```')[0].trim();
        } else if (content.contains('```')) {
          jsonContent = content.split('```')[1].split('```')[0].trim();
        }

        return jsonDecode(jsonContent);
      } else {
        return _getFallbackQuiz(topic, numQuestions);
      }
    } catch (e) {
      return _getFallbackQuiz(topic, numQuestions);
    }
  }

  Map<String, dynamic> _getFallbackQuiz(String topic, int count) {
    return {
      'title': '$topic Quiz (Demo)',
      'questions': List.generate(
        count,
        (i) => {
          'question':
              '⚠️ API key not configured. This is demo question ${i + 1} about $topic. To get real AI-generated quizzes, add your DeepSeek API key.',
          'options': [
            'Option A (placeholder)',
            'Option B (placeholder)',
            'Option C (placeholder)',
            'Option D (placeholder)',
          ],
          'correctIndex': 0,
        },
      ),
    };
  }
}
