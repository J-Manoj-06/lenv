import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Helper script to seed test data in Firestore for student dashboard testing
/// Run this once to populate your Firestore with sample data
class FirestoreSeedData {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Seed schools data - run this first before creating users
  static Future<void> seedSchools() async {
    try {

      final schools = [
        {
          'id': 'sunrise',
          'name': 'Sunrise Public School',
          'address': 'Sunrise Avenue, City',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'id': 'vidhya-mandir',
          'name': 'Vidhya Mandir',
          'address': 'Education Street, City',
          'createdAt': FieldValue.serverTimestamp(),
        },
      ];

      for (var school in schools) {
        await _firestore
            .collection('schools')
            .doc(school['id'] as String)
            .set(school);
      }

    } catch (e) {
      rethrow;
    }
  }

  /// Seed all test data for a student
  static Future<void> seedStudentData(String studentUid) async {
    try {

      // 1. Create student document
      await _seedStudentDocument(studentUid);

      // 2. Create today's daily challenge
      await _seedDailyChallenge();

      // 3. Create sample notifications
      await _seedNotifications(studentUid);

      // 4. Create sample tests
      await _seedTests();

      // 5. Create sample test results
      await _seedTestResults(studentUid);

    } catch (e) {
      rethrow;
    }
  }

  /// Create student document with initial stats
  static Future<void> _seedStudentDocument(String uid) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'name': 'Alex Johnson',
      'email': 'alex.student@oakridge.edu',
      'photoUrl': 'https://i.pravatar.cc/150?img=12',
      'schoolId': 'oakridge',
      'schoolName': 'Oakridge International Academy',
      'role': 'student',
      'rewardPoints': 1250,
      'classRank': 5,
      'monthlyProgress': 85.0,
      'monthlyTarget': 90.0,
      'pendingTests': 2,
      'completedTests': 15,
      'newNotifications': 3,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Create today's daily challenge
  static Future<void> _seedDailyChallenge() async {
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    await _firestore.collection('dailyChallenges').doc(dateKey).set({
      'date': Timestamp.fromDate(DateTime(today.year, today.month, today.day)),
      'question': 'What is the chemical symbol for gold?',
      'correctAnswer': 'Au',
      'options': ['Au', 'Ag', 'Fe', 'Cu'],
      'subject': 'Chemistry',
      'points': 50,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Create sample notifications
  static Future<void> _seedNotifications(String studentUid) async {
    final notifications = [
      {
        'studentId': studentUid,
        'title': 'New Test Available',
        'message': 'Mathematics Quiz #5 is now available. Due: Tomorrow',
        'type': 'test',
        'isRead': false,
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 2)),
        ),
      },
      {
        'studentId': studentUid,
        'title': 'Challenge Reminder',
        'message': 'Don\'t forget to complete today\'s daily challenge!',
        'type': 'challenge',
        'isRead': false,
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 5)),
        ),
      },
      {
        'studentId': studentUid,
        'title': 'Achievement Unlocked',
        'message': '🎉 You earned the "5-Day Streak" badge!',
        'type': 'achievement',
        'isRead': false,
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
      },
      {
        'studentId': studentUid,
        'title': 'Test Result Posted',
        'message': 'Your score for Science Quiz #3 is now available',
        'type': 'result',
        'isRead': true,
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 2)),
        ),
      },
    ];

    for (var notification in notifications) {
      await _firestore.collection('notifications').add(notification);
    }
  }

  /// Create sample tests
  static Future<void> _seedTests() async {
    final tests = [
      {
        'id': 'math-quiz-5',
        'title': 'Mathematics Quiz #5',
        'subject': 'Mathematics',
        'grade': '10',
        'duration': 45,
        'totalQuestions': 20,
        'totalPoints': 100,
        'dueDate': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1)),
        ),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'id': 'science-test-4',
        'title': 'Science Test #4',
        'subject': 'Science',
        'grade': '10',
        'duration': 60,
        'totalQuestions': 25,
        'totalPoints': 100,
        'dueDate': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 3)),
        ),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'id': 'english-essay-2',
        'title': 'English Essay #2',
        'subject': 'English',
        'grade': '10',
        'duration': 90,
        'totalQuestions': 5,
        'totalPoints': 100,
        'dueDate': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      },
    ];

    for (var test in tests) {
      await _firestore.collection('tests').doc(test['id'] as String).set(test);
    }
  }

  /// Create sample test results
  static Future<void> _seedTestResults(String studentUid) async {
    final results = [
      {
        'studentId': studentUid,
        'testId': 'math-quiz-4',
        'testTitle': 'Mathematics Quiz #4',
        'subject': 'Mathematics',
        'score': 88,
        'totalPoints': 100,
        'percentage': 88.0,
        'completedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 3)),
        ),
        'createdAt': FieldValue.serverTimestamp(),
        // Detailed breakdown for UI
        'questions': [
          {
            'index': 1,
            'questionTitle': 'Question 1',
            'yourAnswer': 'A',
            'correctAnswer': 'A',
            'notes': 'Excellent work!',
            'isCorrect': true,
          },
          {
            'index': 2,
            'questionTitle': 'Question 2',
            'yourAnswer': 'B',
            'correctAnswer': 'C',
            'notes': 'Review the concept of derivatives.',
            'isCorrect': false,
          },
          {
            'index': 3,
            'questionTitle': 'Question 3',
            'yourAnswer': 'D',
            'correctAnswer': 'D',
            'notes': 'Well done! You\'ve mastered this topic.',
            'isCorrect': true,
          },
        ],
        'badges': ['Math Whiz', 'Problem Solver'],
        'swot': {
          'strengths': 'Calculus',
          'weaknesses': 'Algebra',
          'opportunities': 'Advanced Topics',
          'threats': 'Time Management',
        },
      },
      {
        'studentId': studentUid,
        'testId': 'science-quiz-3',
        'testTitle': 'Science Quiz #3',
        'subject': 'Science',
        'score': 92,
        'totalPoints': 100,
        'percentage': 92.0,
        'completedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 7)),
        ),
        'createdAt': FieldValue.serverTimestamp(),
        'questions': [
          {
            'index': 1,
            'questionTitle': 'Question 1',
            'yourAnswer': 'C',
            'correctAnswer': 'C',
            'notes': 'Great explanation of photosynthesis.',
            'isCorrect': true,
          },
          {
            'index': 2,
            'questionTitle': 'Question 2',
            'yourAnswer': 'A',
            'correctAnswer': 'A',
            'notes': 'Solid understanding of cell structure.',
            'isCorrect': true,
          },
        ],
        'badges': ['Science Star'],
        'swot': {
          'strengths': 'Biology',
          'weaknesses': 'Chemistry Balancing',
          'opportunities': 'Lab Work',
          'threats': 'Exam Anxiety',
        },
      },
      {
        'studentId': studentUid,
        'testId': 'english-quiz-3',
        'testTitle': 'English Quiz #3',
        'subject': 'English',
        'score': 75,
        'totalPoints': 100,
        'percentage': 75.0,
        'completedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        ),
        'createdAt': FieldValue.serverTimestamp(),
        'questions': [
          {
            'index': 1,
            'questionTitle': 'Question 1',
            'yourAnswer': 'D',
            'correctAnswer': 'D',
            'notes': 'Good interpretation.',
            'isCorrect': true,
          },
          {
            'index': 2,
            'questionTitle': 'Question 2',
            'yourAnswer': 'B',
            'correctAnswer': 'B',
            'notes': 'Nice vocabulary usage.',
            'isCorrect': true,
          },
          {
            'index': 3,
            'questionTitle': 'Question 3',
            'yourAnswer': 'A',
            'correctAnswer': 'C',
            'notes': 'Work on grammar rules.',
            'isCorrect': false,
          },
        ],
        'badges': ['Reader'],
        'swot': {
          'strengths': 'Comprehension',
          'weaknesses': 'Grammar',
          'opportunities': 'Essay Writing',
          'threats': 'Time Pressure',
        },
      },
    ];

    for (var result in results) {
      await _firestore.collection('testResults').add(result);
    }
  }

  /// Helper to get current authenticated user and seed their data
  static Future<void> seedCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await seedStudentData(user.uid);
    } else {
    }
  }

  /// Delete all test data (use carefully!)
  static Future<void> clearTestData(String studentUid) async {

    // Delete notifications
    final notificationsQuery = await _firestore
        .collection('notifications')
        .where('studentId', isEqualTo: studentUid)
        .get();
    for (var doc in notificationsQuery.docs) {
      await doc.reference.delete();
    }

    // Delete test results
    final resultsQuery = await _firestore
        .collection('testResults')
        .where('studentId', isEqualTo: studentUid)
        .get();
    for (var doc in resultsQuery.docs) {
      await doc.reference.delete();
    }

    // Delete challenge attempts
    final attemptsQuery = await _firestore
        .collection('challengeAttempts')
        .where('studentId', isEqualTo: studentUid)
        .get();
    for (var doc in attemptsQuery.docs) {
      await doc.reference.delete();
    }

    // Delete student document
    await _firestore.collection('users').doc(studentUid).delete();

  }
}
