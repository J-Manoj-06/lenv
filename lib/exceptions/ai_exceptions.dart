/// Custom exceptions for AI test generation service
///
/// These exceptions provide specific error handling for different failure scenarios
/// when generating tests with AI.
library;

/// Base exception for AI-related errors
class AIException implements Exception {
  final String message;
  final String? details;
  final dynamic originalError;

  AIException(this.message, {this.details, this.originalError});

  @override
  String toString() {
    if (details != null) {
      return 'AIException: $message\nDetails: $details';
    }
    return 'AIException: $message';
  }

  /// Get a user-friendly message suitable for display in UI
  String get userMessage => message;
}

/// Exception thrown when API call fails (4xx, 5xx errors)
class ApiException extends AIException {
  final int? statusCode;
  final String? responseBody;

  ApiException(
    super.message, {
    this.statusCode,
    this.responseBody,
    super.details,
    super.originalError,
  });

  @override
  String toString() {
    return 'ApiException: $message (Status: $statusCode)\n${details ?? responseBody ?? ''}';
  }

  @override
  String get userMessage {
    if (statusCode == 400) {
      return 'Invalid request. Please check your input and try again.';
    } else if (statusCode != null && statusCode! >= 500) {
      return 'Server error occurred. Please try again later.';
    }
    return 'Failed to generate test. Please try again.';
  }
}

/// Exception thrown when rate limit is exceeded (HTTP 429)
class RateLimitException extends AIException {
  final int? retryAfterSeconds;

  RateLimitException(super.message, {this.retryAfterSeconds, super.details});

  @override
  String get userMessage {
    if (retryAfterSeconds != null) {
      return 'Too many requests. Please wait $retryAfterSeconds seconds and try again.';
    }
    return 'Too many requests. Please wait a moment and try again.';
  }
}

/// Exception thrown when JSON parsing fails
class ParseException extends AIException {
  final String? rawResponse;

  ParseException(
    super.message, {
    this.rawResponse,
    super.details,
    super.originalError,
  });

  @override
  String toString() {
    return 'ParseException: $message\n${details ?? ''}\nRaw response: ${rawResponse?.substring(0, rawResponse!.length > 200 ? 200 : rawResponse!.length) ?? 'null'}';
  }

  @override
  String get userMessage {
    return 'Failed to parse AI response. The test could not be generated. Please try again.';
  }
}

/// Exception thrown when duplicate questions are detected
class DuplicateQuestionException extends AIException {
  final List<String> duplicateQuestions;

  DuplicateQuestionException(
    super.message, {
    required this.duplicateQuestions,
    super.details,
  });

  @override
  String get userMessage {
    if (duplicateQuestions.length == 1) {
      return 'A duplicate question was detected. Please regenerate the test.';
    }
    return '${duplicateQuestions.length} duplicate questions were detected. Please regenerate the test.';
  }
}

/// Exception thrown when network connection fails
class NetworkException extends AIException {
  NetworkException(super.message, {super.details, super.originalError});

  @override
  String get userMessage {
    return 'Network connection failed. Please check your internet connection and try again.';
  }
}

/// Exception thrown when validation fails
class ValidationException extends AIException {
  final Map<String, String>? fieldErrors;

  ValidationException(super.message, {this.fieldErrors, super.details});

  @override
  String get userMessage {
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      return 'Validation failed: ${fieldErrors!.values.first}';
    }
    return message;
  }
}

/// Exception thrown when timeout occurs
class TimeoutException extends AIException {
  final int timeoutSeconds;

  TimeoutException(
    super.message, {
    required this.timeoutSeconds,
    super.details,
  });

  @override
  String get userMessage {
    return 'Request timed out after $timeoutSeconds seconds. Please try again.';
  }
}
