import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to fetch daily content (quote, fact, history) from Firestore
/// Content is pre-fetched by Cloudflare Worker at 2 AM daily
/// This eliminates per-user API calls and reduces costs by 98%
class DailyContentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get today's date in YYYY-MM-DD format
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Fetch today's daily content from Firestore
  /// Returns null if content doesn't exist yet (worker hasn't run)
  Future<DailyContent?> getTodayContent() async {
    try {
      final today = _getTodayKey();
      final doc = await _firestore
          .collection('daily_content')
          .doc(today)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists || doc.data() == null) {
        return null; // Content not yet available
      }

      final data = doc.data()!;
      return DailyContent.fromMap(data);
    } catch (e) {
      return null;
    }
  }

  /// Get quote for today
  Future<DailyQuote?> getTodayQuote() async {
    final content = await getTodayContent();
    return content?.quote;
  }

  /// Get fact for today
  Future<DailyFact?> getTodayFact() async {
    final content = await getTodayContent();
    return content?.fact;
  }

  /// Get history events for today
  Future<DailyHistory?> getTodayHistory() async {
    final content = await getTodayContent();
    return content?.history;
  }
}

/// Complete daily content model
class DailyContent {
  final String date;
  final DailyQuote quote;
  final DailyFact fact;
  final DailyHistory history;
  final DateTime fetchedAt;
  final String status; // 'success', 'partial', or 'failed'
  final List<String>? errors;

  DailyContent({
    required this.date,
    required this.quote,
    required this.fact,
    required this.history,
    required this.fetchedAt,
    required this.status,
    this.errors,
  });

  factory DailyContent.fromMap(Map<String, dynamic> map) {
    return DailyContent(
      date: map['date'] ?? '',
      quote: DailyQuote.fromMap(map['quote'] ?? {}),
      fact: DailyFact.fromMap(map['fact'] ?? {}),
      history: DailyHistory.fromMap(map['history'] ?? {}),
      fetchedAt: DateTime.parse(map['fetchedAt'] ?? DateTime.now().toIso8601String()),
      status: map['status'] ?? 'unknown',
      errors: map['errors'] != null ? List<String>.from(map['errors']) : null,
    );
  }
}

/// Daily motivational quote
class DailyQuote {
  final String text;
  final String author;
  final String source;

  DailyQuote({
    required this.text,
    required this.author,
    required this.source,
  });

  factory DailyQuote.fromMap(Map<String, dynamic> map) {
    return DailyQuote(
      text: map['text'] ?? '',
      author: map['author'] ?? 'Unknown',
      source: map['source'] ?? '',
    );
  }

  /// Fallback quotes when Firestore data unavailable
  static List<DailyQuote> get fallbacks => [
        DailyQuote(
          text: 'Success is not final, failure is not fatal: it is the courage to continue that counts.',
          author: 'Winston Churchill',
          source: 'fallback',
        ),
        DailyQuote(
          text: 'Believe you can and you\'re halfway there.',
          author: 'Theodore Roosevelt',
          source: 'fallback',
        ),
        DailyQuote(
          text: 'The only way to do great work is to love what you do.',
          author: 'Steve Jobs',
          source: 'fallback',
        ),
        DailyQuote(
          text: 'Education is the most powerful weapon which you can use to change the world.',
          author: 'Nelson Mandela',
          source: 'fallback',
        ),
      ];

  static DailyQuote randomFallback() {
    final fallbackList = fallbacks;
    fallbackList.shuffle();
    return fallbackList.first;
  }
}

/// Daily interesting fact
class DailyFact {
  final String text;
  final String source;

  DailyFact({
    required this.text,
    required this.source,
  });

  factory DailyFact.fromMap(Map<String, dynamic> map) {
    return DailyFact(
      text: map['text'] ?? '',
      source: map['source'] ?? '',
    );
  }

  /// Fallback facts when Firestore data unavailable
  static List<DailyFact> get fallbacks => [
        DailyFact(
          text: 'The Eiffel Tower can be 15 cm taller during hot days due to thermal expansion.',
          source: 'fallback',
        ),
        DailyFact(
          text: 'Octopuses have three hearts and blue blood.',
          source: 'fallback',
        ),
        DailyFact(
          text: 'Bananas are berries, but strawberries are not.',
          source: 'fallback',
        ),
        DailyFact(
          text: 'Honeybees can recognize human faces.',
          source: 'fallback',
        ),
        DailyFact(
          text: 'A day on Venus is longer than its year.',
          source: 'fallback',
        ),
      ];

  static DailyFact randomFallback() {
    final fallbackList = fallbacks;
    fallbackList.shuffle();
    return fallbackList.first;
  }
}

/// Historical events for today's date
class DailyHistory {
  final List<HistoryEvent> events;
  final String source;

  DailyHistory({
    required this.events,
    required this.source,
  });

  factory DailyHistory.fromMap(Map<String, dynamic> map) {
    final eventsList = map['events'] as List?;
    return DailyHistory(
      events: eventsList?.map((e) => HistoryEvent.fromMap(e as Map<String, dynamic>)).toList() ?? [],
      source: map['source'] ?? '',
    );
  }

  /// Fallback history events when Firestore data unavailable
  static List<HistoryEvent> get fallbacks => [
        HistoryEvent(
          text: 'The Wright Brothers made the first powered, sustained, and controlled airplane flight',
          year: '1903',
          title: 'Wright Brothers\' First Flight',
          thumb: 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0b/First_flight2.jpg/240px-First_flight2.jpg',
          category: 'Technology',
        ),
        HistoryEvent(
          text: 'The Declaration of Independence was adopted by the Continental Congress',
          year: '1776',
          title: 'Declaration of Independence',
          thumb: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e2/Declaration_of_Independence.jpg/240px-Declaration_of_Independence.jpg',
          category: 'Politics',
        ),
        HistoryEvent(
          text: 'Albert Einstein published his theory of Special Relativity',
          year: '1905',
          title: 'Theory of Special Relativity',
          thumb: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Albert_Einstein_Head.jpg/240px-Albert_Einstein_Head.jpg',
          category: 'Science',
        ),
      ];

  static DailyHistory randomFallback() {
    final fallbackList = fallbacks;
    fallbackList.shuffle();
    return DailyHistory(events: [fallbackList.first], source: 'fallback');
  }
}

/// Single historical event
class HistoryEvent {
  final String text;
  final String year;
  final String title;
  final String thumb;
  final String category;

  HistoryEvent({
    required this.text,
    required this.year,
    required this.title,
    required this.thumb,
    required this.category,
  });

  factory HistoryEvent.fromMap(Map<String, dynamic> map) {
    return HistoryEvent(
      text: map['text'] ?? '',
      year: map['year'] ?? '',
      title: map['title'] ?? '',
      thumb: map['thumb'] ?? '',
      category: map['category'] ?? '',
    );
  }

  Map<String, String> toMap() {
    return {
      'text': text,
      'year': year,
      'title': title,
      'thumb': thumb,
      'category': category,
    };
  }
}
