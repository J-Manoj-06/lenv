import 'package:cloud_firestore/cloud_firestore.dart';

enum TestStatus { draft, published, ongoing, completed, archived }

enum QuestionType { multipleChoice, trueFalse, shortAnswer, essay }

class Question {
  final String id;
  final QuestionType type;
  final String question;
  final List<String>? options; // For multiple choice
  final String? correctAnswer;
  final int points;

  Question({
    required this.id,
    required this.type,
    required this.question,
    this.options,
    this.correctAnswer,
    required this.points,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString().split('.').last,
      'question': question,
      'options': options,
      'correctAnswer': correctAnswer,
      'points': points,
    };
  }

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] ?? '',
      type: QuestionType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => QuestionType.multipleChoice,
      ),
      question: json['question'] ?? '',
      options: json['options'] != null
          ? List<String>.from(json['options'])
          : null,
      correctAnswer: json['correctAnswer'],
      points: json['points'] ?? 1,
    );
  }
}

class TestModel {
  final String id;
  final String title;
  final String description;
  final String teacherId;
  final String teacherName;
  final String instituteId;
  final String subject;
  // Targeting info for filtering in UI
  final String? className; // e.g. "Grade 8"
  final String? section; // e.g. "A"
  final List<Question> questions;
  final int totalPoints;
  final int duration; // in minutes
  final DateTime startDate;
  final DateTime endDate;
  final TestStatus status;
  final List<String> assignedStudentIds;
  final DateTime createdAt;
  final DateTime? updatedAt;
  // Result publishing fields
  final bool resultsPublished;
  final DateTime? publishedAt;

  TestModel({
    required this.id,
    required this.title,
    required this.description,
    required this.teacherId,
    required this.teacherName,
    required this.instituteId,
    required this.subject,
    this.className,
    this.section,
    required this.questions,
    required this.totalPoints,
    required this.duration,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.assignedStudentIds,
    required this.createdAt,
    this.updatedAt,
    this.resultsPublished = false,
    this.publishedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'instituteId': instituteId,
      'subject': subject,
      'className': className,
      'section': section,
      'questions': questions.map((q) => q.toJson()).toList(),
      'totalPoints': totalPoints,
      'duration': duration,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status.toString().split('.').last,
      'assignedStudentIds': assignedStudentIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'resultsPublished': resultsPublished,
      'publishedAt': publishedAt != null
          ? Timestamp.fromDate(publishedAt!)
          : null,
    };
  }

  factory TestModel.fromJson(Map<String, dynamic> json) {
    return TestModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      teacherId: json['teacherId'] ?? '',
      teacherName: json['teacherName'] ?? '',
      instituteId: json['instituteId'] ?? '',
      subject: json['subject'] ?? '',
      className: json['className'],
      section: json['section'],
      questions: json['questions'] != null
          ? (json['questions'] as List)
                .map((q) => Question.fromJson(q))
                .toList()
          : [],
      totalPoints: json['totalPoints'] ?? 0,
      duration: json['duration'] ?? 60,
      startDate: (json['startDate'] as Timestamp).toDate(),
      endDate: (json['endDate'] as Timestamp).toDate(),
      status: TestStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => TestStatus.draft,
      ),
      assignedStudentIds: json['assignedStudentIds'] != null
          ? List<String>.from(json['assignedStudentIds'])
          : [],
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
      resultsPublished: json['resultsPublished'] ?? false,
      publishedAt: json['publishedAt'] != null
          ? (json['publishedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Factory constructor for converting from scheduledTests collection format
  factory TestModel.fromScheduledTest(String id, Map<String, dynamic> json) {
    // Parse questions from scheduledTests format
    final List<Question> questions = [];
    if (json['questions'] != null) {
      final questionsData = json['questions'] as List;
      for (var i = 0; i < questionsData.length; i++) {
        final q = questionsData[i] as Map<String, dynamic>;

        // Determine question type from scheduledTests format
        QuestionType type;
        final typeStr = (q['type'] as String?)?.toLowerCase() ?? 'mcq';
        if (typeStr == 'mcq' || typeStr == 'multiplechoice') {
          type = QuestionType.multipleChoice;
        } else if (typeStr == 'tf' || typeStr == 'truefalse') {
          type = QuestionType.trueFalse;
        } else if (typeStr == 'short' || typeStr == 'shortanswer') {
          type = QuestionType.shortAnswer;
        } else if (typeStr == 'essay') {
          type = QuestionType.essay;
        } else {
          type = QuestionType.multipleChoice;
        }

        questions.add(
          Question(
            id: q['id'] ?? 'q_${i + 1}',
            type: type,
            question: q['questionText'] ?? q['question'] ?? '',
            options: q['options'] != null
                ? List<String>.from(q['options'])
                : null,
            correctAnswer: q['correctAnswer'],
            points: q['marks'] ?? q['points'] ?? 1,
          ),
        );
      }
    }

    // Parse dates - scheduledTests might have different formats
    DateTime startDate;
    DateTime endDate;

    try {
      if (json['startDate'] is Timestamp) {
        startDate = (json['startDate'] as Timestamp).toDate();
      } else if (json['date'] is String) {
        // Parse string date format "YYYY-MM-DD"
        final dateStr = json['date'] as String;
        final timeStr = json['startTime'] as String? ?? '00:00';
        startDate = DateTime.parse('$dateStr $timeStr');
      } else {
        startDate = DateTime.now();
      }

      if (json['endDate'] is Timestamp) {
        endDate = (json['endDate'] as Timestamp).toDate();
      } else if (json['date'] is String) {
        // Parse string date format "YYYY-MM-DD"
        final dateStr = json['date'] as String;
        final endTimeStr =
            json['endTime'] as String? ??
            json['scheduledTime'] as String? ??
            '23:59';
        final durationMinutes = json['duration'] as int? ?? 60;

        // Calculate end date from start + duration
        final tempStart = DateTime.parse('$dateStr $endTimeStr');
        endDate = tempStart.add(Duration(minutes: durationMinutes));
      } else {
        endDate = DateTime.now().add(const Duration(hours: 1));
      }
    } catch (e) {
      startDate = DateTime.now();
      endDate = DateTime.now().add(const Duration(hours: 1));
    }

    // Calculate total points
    int totalPoints = 0;
    for (var q in questions) {
      totalPoints += q.points;
    }

    return TestModel(
      id: id,
      title: json['title'] ?? json['testTitle'] ?? '',
      description: json['description'] ?? '',
      teacherId: json['teacherId'] ?? '',
      teacherName: json['teacherName'] ?? '',
      instituteId: json['schoolCode'] ?? json['instituteId'] ?? '',
      subject: json['subject'] ?? '',
      className: json['class'] ?? json['className'],
      section: json['section'],
      questions: questions,
      totalPoints: json['totalMarks'] ?? totalPoints,
      duration: json['duration'] ?? 60,
      startDate: startDate,
      endDate: endDate,
      status: TestStatus.published, // scheduledTests are always published
      assignedStudentIds: [], // Not used in new system
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : (json['dateCreated'] is Timestamp
                ? (json['dateCreated'] as Timestamp).toDate()
                : DateTime.now()),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
      resultsPublished:
          json['resultsPublished'] ?? json['autoPublished'] ?? false,
      publishedAt: json['publishedAt'] is Timestamp
          ? (json['publishedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
