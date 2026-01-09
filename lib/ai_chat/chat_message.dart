class ChatMessage {
  final String id;
  final String sender; // "student" or "ai"
  final String? text;
  final String? imageUrl;
  final dynamic quiz; // AiGeneratedQuiz or null
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.sender,
    this.text,
    this.imageUrl,
    this.quiz,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
