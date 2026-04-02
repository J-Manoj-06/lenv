import 'package:cloud_firestore/cloud_firestore.dart';

class StudentModel {
  final String uid;
  final String? studentId; // Human-readable ID like "STU-G10A-03"
  final String email;
  final String name;
  final String? photoUrl;
  final String? schoolId;
  final String? schoolCode; // Added: School code like "OAK001"
  final String? schoolName;
  final String? className;
  final String? section; // Added: Section like "A", "B", etc.
  final String? phone;
  final String? parentPhone;
  final String? parentEmail;
  final int rewardPoints;
  final int classRank;
  final double monthlyProgress;
  final double monthlyTarget;
  final int pendingTests;
  final int completedTests;
  final int newNotifications;
  final int streak;
  final String? lastStreakDate;
  final DateTime createdAt;
  final bool isActive;

  StudentModel({
    required this.uid,
    this.studentId,
    required this.email,
    required this.name,
    this.photoUrl,
    this.schoolId,
    this.schoolCode, // Added
    this.schoolName,
    this.className,
    this.section, // Added
    this.phone,
    this.parentPhone,
    this.parentEmail,
    this.rewardPoints = 0,
    this.classRank = 0,
    this.monthlyProgress = 0.0,
    this.monthlyTarget = 90.0,
    this.pendingTests = 0,
    this.completedTests = 0,
    this.newNotifications = 0,
    this.streak = 0,
    this.lastStreakDate,
    required this.createdAt,
    this.isActive = true,
  });

  // From Firestore
  factory StudentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StudentModel(
      uid:
          data['uid'] ??
          doc.id, // Use uid field from document, fallback to doc.id
      studentId: data['studentId'],
      email: data['email'] ?? '',
      name: (data['name'] ?? data['studentName'] ?? '').toString(),
      photoUrl: data['photoUrl'],
      schoolId: data['schoolId'],
      schoolCode: data['schoolCode'], // Added: Read schoolCode from Firestore
      schoolName: data['schoolName'],
      className: data['className'],
      section: data['section'], // Added: Read section from Firestore
      phone: data['phone'],
      parentPhone: data['parentPhone'],
      parentEmail: data['parentEmail'] ?? data['parent_email'],
      rewardPoints: _parseRewardPoints(data),
      classRank: data['classRank'] ?? 0,
      monthlyProgress: (data['monthlyProgress'] ?? 0.0).toDouble(),
      monthlyTarget: (data['monthlyTarget'] ?? 90.0).toDouble(),
      pendingTests: data['pendingTests'] ?? 0,
      completedTests: data['completedTests'] ?? 0,
      newNotifications: data['newNotifications'] ?? 0,
      streak: data['streak'] ?? 0,
      lastStreakDate: data['lastStreakDate'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] ?? true,
    );
  }

  static int _parseRewardPoints(Map<String, dynamic> data) {
    final candidates = [
      data['available_points'],
      data['rewardPoints'],
      data['totalPoints'],
      data['points'],
      data['reward_points'],
    ];

    for (final value in candidates) {
      final parsed = _toInt(value);
      if (parsed != null) return parsed;
    }

    return 0;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  // To Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'email': email,
      'name': name,
      'photoUrl': photoUrl,
      'schoolId': schoolId,
      'schoolCode': schoolCode, // Added: Write schoolCode to Firestore
      'schoolName': schoolName,
      'className': className,
      'section': section, // Added: Write section to Firestore
      'phone': phone,
      'parentPhone': parentPhone,
      'parentEmail': parentEmail,
      'rewardPoints': rewardPoints,
      'classRank': classRank,
      'monthlyProgress': monthlyProgress,
      'monthlyTarget': monthlyTarget,
      'pendingTests': pendingTests,
      'completedTests': completedTests,
      'newNotifications': newNotifications,
      'streak': streak,
      'lastStreakDate': lastStreakDate,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'role': 'student',
    };
  }

  // To Cacheable Map (for SharedPreferences - converts Timestamp to milliseconds)
  Map<String, dynamic> toCacheableMap() {
    return {
      'studentId': studentId,
      'email': email,
      'name': name,
      'photoUrl': photoUrl,
      'schoolId': schoolId,
      'schoolCode': schoolCode,
      'schoolName': schoolName,
      'className': className,
      'section': section,
      'phone': phone,
      'parentPhone': parentPhone,
      'parentEmail': parentEmail,
      'rewardPoints': rewardPoints,
      'classRank': classRank,
      'monthlyProgress': monthlyProgress,
      'monthlyTarget': monthlyTarget,
      'pendingTests': pendingTests,
      'completedTests': completedTests,
      'newNotifications': newNotifications,
      'streak': streak,
      'lastStreakDate': lastStreakDate,
      'createdAt':
          createdAt.millisecondsSinceEpoch, // ✅ Convert to int for JSON
      'isActive': isActive,
      'role': 'student',
    };
  }

  // Copy with
  StudentModel copyWith({
    String? uid,
    String? studentId,
    String? email,
    String? name,
    String? photoUrl,
    String? schoolId,
    String? schoolCode, // Added
    String? schoolName,
    String? className,
    String? section, // Added
    String? phone,
    String? parentPhone,
    String? parentEmail,
    int? rewardPoints,
    int? classRank,
    double? monthlyProgress,
    double? monthlyTarget,
    int? pendingTests,
    int? completedTests,
    int? newNotifications,
    int? streak,
    String? lastStreakDate,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return StudentModel(
      uid: uid ?? this.uid,
      studentId: studentId ?? this.studentId,
      email: email ?? this.email,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      schoolId: schoolId ?? this.schoolId,
      schoolCode: schoolCode ?? this.schoolCode, // Added
      schoolName: schoolName ?? this.schoolName,
      className: className ?? this.className,
      section: section ?? this.section, // Added
      phone: phone ?? this.phone,
      parentPhone: parentPhone ?? this.parentPhone,
      parentEmail: parentEmail ?? this.parentEmail,
      rewardPoints: rewardPoints ?? this.rewardPoints,
      classRank: classRank ?? this.classRank,
      monthlyProgress: monthlyProgress ?? this.monthlyProgress,
      monthlyTarget: monthlyTarget ?? this.monthlyTarget,
      pendingTests: pendingTests ?? this.pendingTests,
      completedTests: completedTests ?? this.completedTests,
      newNotifications: newNotifications ?? this.newNotifications,
      streak: streak ?? this.streak,
      lastStreakDate: lastStreakDate ?? this.lastStreakDate,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

class DailyChallengeModel {
  final String id;
  final String question;
  final String correctAnswer;
  final List<String> options;
  final String subject;
  final int points;
  final DateTime date;
  final bool isActive;

  DailyChallengeModel({
    required this.id,
    required this.question,
    required this.correctAnswer,
    required this.options,
    required this.subject,
    this.points = 10,
    required this.date,
    this.isActive = true,
  });

  factory DailyChallengeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DailyChallengeModel(
      id: doc.id,
      question: data['question'] ?? '',
      correctAnswer: data['correctAnswer'] ?? '',
      options: List<String>.from(data['options'] ?? []),
      subject: data['subject'] ?? '',
      points: data['points'] ?? 10,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'question': question,
      'correctAnswer': correctAnswer,
      'options': options,
      'subject': subject,
      'points': points,
      'date': Timestamp.fromDate(date),
      'isActive': isActive,
    };
  }
}

class NotificationModel {
  final String id;
  final String studentId;
  final String title;
  final String message;
  final String type; // 'test', 'reward', 'announcement', 'reminder'
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? data;

  NotificationModel({
    required this.id,
    required this.studentId,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.data,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      type: data['type'] ?? 'announcement',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
      data: data['data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'title': title,
      'message': message,
      'type': type,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
      'data': data,
    };
  }
}
