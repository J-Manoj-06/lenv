import 'dart:convert';
import 'package:http/http.dart' as http;

class DeepSeekService {
  /// Cloudflare Worker endpoint - API key is secured on the server
  static const String _workerUrl =
      'https://deepseek-ai-worker.giridharannj.workers.dev/chat';

  /// No API key needed in Flutter app anymore - handled by Cloudflare Worker
  /// This keeps the API key secure and prevents theft

  Future<String> chat(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json'},
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
        return '⚠️ AI Service Error: ${errorData['message'] ?? 'Please try again later'}';
      }
    } catch (e) {
      return '⚠️ Connection failed: Unable to reach AI service. Please check your internet connection and try again.';
    }
  }

  // Streamed chat: emits partial content as it arrives for typewriter effect
  Future<void> chatStream(
    String userMessage,
    void Function(String delta) onChunk,
  ) async {
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
      });

      final request = http.Request('POST', Uri.parse(_workerUrl));
      request.headers.addAll({'Content-Type': 'application/json'});
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
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json'},
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
