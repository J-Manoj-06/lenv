import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

/// QuestionService
/// Calls the Firebase Callable Function 'generateQuestions' and decodes the
/// strict-JSON response into a usable Map<String, dynamic>.
class QuestionService {
  final FirebaseFunctions _functions;

  QuestionService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  /// Generate questions for the given topic and count.
  /// Throws [FirebaseFunctionsException] for backend errors and [FormatException]
  /// for unexpected response formats.
  Future<Map<String, dynamic>> generateQuestions({
    required String topic,
    required int count,
  }) async {
    if (topic.trim().isEmpty) {
      throw ArgumentError('topic cannot be empty');
    }
    if (count < 3 || count > 100) {
      throw ArgumentError('count must be between 3 and 100');
    }

    final callable = _functions.httpsCallable(
      'generateQuestions',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );

    final result = await callable.call(<String, dynamic>{
      'topic': topic.trim(),
      'count': count,
    });

    final data = result.data;

    // Backend returns a JSON STRING as per requirement.
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        throw const FormatException('Expected a JSON object at the top level');
      }
    }

    // If backend ever returns parsed JSON directly (Map), support it gracefully.
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    throw FormatException('Unexpected response type: ${data.runtimeType}');
  }
}
