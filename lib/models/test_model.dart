import 'package:cloud_firestore/cloud_firestore.dart';

enum TestStatus {
  draft,
  published,
  ongoing,
  completed,
  archived,
}

enum QuestionType {
  multipleChoice,
  trueFalse,
  shortAnswer,
  essay,
}

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
      options: json['options'] != null ? List<String>.from(json['options']) : null,
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
  final List<Question> questions;
  final int totalPoints;
  final int duration; // in minutes
  final DateTime startDate;
  final DateTime endDate;
  final TestStatus status;
  final List<String> assignedStudentIds;
  final DateTime createdAt;
  final DateTime? updatedAt;

  TestModel({
    required this.id,
    required this.title,
    required this.description,
    required this.teacherId,
    required this.teacherName,
    required this.instituteId,
    required this.subject,
    required this.questions,
    required this.totalPoints,
    required this.duration,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.assignedStudentIds,
    required this.createdAt,
    this.updatedAt,
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
      'questions': questions.map((q) => q.toJson()).toList(),
      'totalPoints': totalPoints,
      'duration': duration,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status.toString().split('.').last,
      'assignedStudentIds': assignedStudentIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
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
    );
  }
}
