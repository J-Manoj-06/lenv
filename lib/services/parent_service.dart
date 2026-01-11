import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student_model.dart';
import '../models/test_result_model.dart';
import '../models/reward_request_model.dart';

class ParentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get all children (students) linked to a parent by email
  /// First fetches parent document to get linkedStudents, then fetches each student
  Future<List<StudentModel>> getChildrenByParentEmail(
    String parentEmail,
  ) async {
    try {

      // First, get the parent document to find linked students
      final parentQuery = await _firestore
          .collection('parents')
          .where('email', isEqualTo: parentEmail)
          .limit(1)
          .get();

      if (parentQuery.docs.isEmpty) {
        return [];
      }

      final parentDoc = parentQuery.docs.first;
      final parentData = parentDoc.data();
      final linkedStudents = parentData['linkedStudents'] as List<dynamic>?;

      if (linkedStudents == null || linkedStudents.isEmpty) {
        return [];
      }


      // ✅ OPTIMIZATION: Fetch all students in parallel instead of sequentially
      final studentFutures = linkedStudents.map((studentInfo) async {
        var studentId = studentInfo['id'] as String?;
        if (studentId == null) {
          return null;
        }

        // Trim whitespace and ensure clean ID
        studentId = studentId.trim();

        try {
          // Try to get student document
          final studentDoc = await _firestore
              .collection('students')
              .doc(studentId)
              .get();

          StudentModel? studentModel;

          if (studentDoc.exists) {
            studentModel = StudentModel.fromFirestore(studentDoc);
          } else {
            // Fallback: try querying by uid field
            final querySnapshot = await _firestore
                .collection('students')
                .where('uid', isEqualTo: studentId)
                .limit(1)
                .get();

            if (querySnapshot.docs.isNotEmpty) {
              studentModel = StudentModel.fromFirestore(
                querySnapshot.docs.first,
              );
            }
          }

          if (studentModel != null) {
            var hydratedStudent = studentModel;

            // ✅ OPTIMIZATION: Try to use aggregate query for points (if available)
            try {
              final authUid = hydratedStudent.uid;

              // Try aggregate query first (Firestore aggregate - more efficient)
              try {
                final aggregateResult = await _firestore
                    .collection('student_rewards')
                    .where('studentId', isEqualTo: authUid)
                    .count()
                    .get();

                // If we have rewards, get the sum
                if ((aggregateResult.count ?? 0) > 0) {
                  // Note: Firestore doesn't support sum aggregation yet in all SDKs
                  // Fall back to manual calculation
                  final rewardsSnapshot = await _firestore
                      .collection('student_rewards')
                      .where('studentId', isEqualTo: authUid)
                      .limit(100) // ✅ Limit to prevent excessive reads
                      .get();

                  int totalPoints = 0;
                  for (final doc in rewardsSnapshot.docs) {
                    final data = doc.data();
                    final points = data['pointsEarned'];
                    if (points is int) {
                      totalPoints += points;
                    } else if (points is num) {
                      totalPoints += points.toInt();
                    }
                  }

                  hydratedStudent = hydratedStudent.copyWith(
                    rewardPoints: totalPoints,
                  );
                }
              } catch (e) {
              }
            } catch (e) {
            }

            // Apply fallback data from linkedStudents
            final linkedName = (studentInfo['name'] as String?)?.trim();
            final linkedClass = (studentInfo['class'] as String?)?.trim();
            final linkedSection = (studentInfo['section'] as String?)?.trim();

            if (hydratedStudent.name.isEmpty &&
                linkedName != null &&
                linkedName.isNotEmpty) {
              hydratedStudent = hydratedStudent.copyWith(name: linkedName);
            }
            if ((hydratedStudent.className == null ||
                    hydratedStudent.className!.isEmpty) &&
                linkedClass != null &&
                linkedClass.isNotEmpty) {
              hydratedStudent = hydratedStudent.copyWith(
                className: linkedClass,
              );
            }
            if ((hydratedStudent.section == null ||
                    hydratedStudent.section!.isEmpty) &&
                linkedSection != null &&
                linkedSection.isNotEmpty) {
              hydratedStudent = hydratedStudent.copyWith(
                section: linkedSection,
              );
            }

            return hydratedStudent;
          } else {
            // Create placeholder from linkedStudents data
            return StudentModel(
              uid: studentId,
              name: (studentInfo['name'] as String?) ?? 'Unknown Student',
              email: '',
              schoolCode: parentData['schoolCode'] as String? ?? '',
              className: (studentInfo['class'] as String?) ?? '',
              section: (studentInfo['section'] as String?) ?? '',
              rewardPoints: 0,
              monthlyProgress: 0.0,
              createdAt: DateTime.now(),
            );
          }
        } catch (e) {
          return null;
        }
      }).toList();

      // ✅ OPTIMIZATION: Wait for all students in parallel
      final studentResults = await Future.wait(studentFutures);
      final children = studentResults.whereType<StudentModel>().toList();

      return children;
    } catch (e) {
      return [];
    }
  }

  /// Get real-time stream of children for a parent
  /// Note: This returns a stream but checks parent's linkedStudents on each update
  Stream<List<StudentModel>> getChildrenStream(String parentEmail) async* {
    try {
      // Get parent document to find linked student IDs
      final parentQuery = await _firestore
          .collection('parents')
          .where('email', isEqualTo: parentEmail)
          .limit(1)
          .get();

      if (parentQuery.docs.isEmpty) {
        yield [];
        return;
      }

      final parentDoc = parentQuery.docs.first;
      final parentData = parentDoc.data();
      final linkedStudents = parentData['linkedStudents'] as List<dynamic>?;

      if (linkedStudents == null || linkedStudents.isEmpty) {
        yield [];
        return;
      }

      // Fetch students by IDs
      final children = <StudentModel>[];
      for (var studentInfo in linkedStudents) {
        final studentId = studentInfo['id'] as String?;
        if (studentId != null) {
          try {
            final studentDoc = await _firestore
                .collection('students')
                .doc(studentId)
                .get();

            if (studentDoc.exists) {
              children.add(StudentModel.fromFirestore(studentDoc));
            }
          } catch (e) {
          }
        }
      }

      yield children;
    } catch (e) {
      yield [];
    }
  }

  /// Get student's test results with detailed information
  Future<List<TestResultModel>> getStudentTestResults(String studentId) async {
    try {

      final querySnapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .orderBy('completedAt', descending: true)
          .get();


      final results = querySnapshot.docs.map((doc) {
        return TestResultModel.fromFirestore(doc);
      }).toList();

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Get student's test results stream
  Stream<List<TestResultModel>> getStudentTestResultsStream(String studentId) {
    return _firestore
        .collection('testResults')
        .where('studentId', isEqualTo: studentId)
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TestResultModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// Compute class average percentage for a given testId across all test results
  Future<double?> getClassAverageForTest(String testId) async {
    try {
      final qs = await _firestore
          .collection('testResults')
          .where('testId', isEqualTo: testId)
          .get();
      if (qs.docs.isEmpty) {
        return null;
      }
      double sum = 0;
      int count = 0;
      for (final d in qs.docs) {
        final data = d.data();
        final totalQ = (data['totalQuestions'] ?? 0) as int;
        final correct = (data['correctAnswers'] ?? 0) as int;
        double pct;
        if (totalQ > 0) {
          pct = (correct / totalQ) * 100.0;
        } else {
          pct = (data['score'] ?? 0).toDouble();
        }
        sum += pct;
        count++;
      }
      final average = count > 0 ? (sum / count) : null;
      return average;
    } catch (e) {
      return null;
    }
  }

  /// Get highest score percentage for a given testId across all test results
  Future<double?> getHighestScoreForTest(String testId) async {
    try {
      final qs = await _firestore
          .collection('testResults')
          .where('testId', isEqualTo: testId)
          .get();
      if (qs.docs.isEmpty) return null;

      double highest = 0.0;
      for (final d in qs.docs) {
        final data = d.data();
        final totalQ = (data['totalQuestions'] ?? 0) as int;
        final correct = (data['correctAnswers'] ?? 0) as int;
        double pct;
        if (totalQ > 0) {
          pct = (correct / totalQ) * 100.0;
        } else {
          pct = (data['score'] ?? 0).toDouble();
        }
        if (pct > highest) {
          highest = pct;
        }
      }
      return highest;
    } catch (e) {
      return null;
    }
  }

  /// Fetch attendance breakdown: present/absent/late counts from Firestore
  Future<Map<String, int>> getStudentAttendanceBreakdown(
    String studentId,
  ) async {
    try {
      // Get student details from users collection (using auth UID)
      final userDoc = await _firestore.collection('users').doc(studentId).get();

      if (!userDoc.exists) {
        return {'present': 0, 'absent': 0, 'late': 0, 'total': 0};
      }

      final userData = userDoc.data();
      final className = userData?['className'] as String?;
      final schoolCode = userData?['schoolCode'] as String?;

      if (className == null || schoolCode == null || schoolCode.isEmpty) {
        return {'present': 0, 'absent': 0, 'late': 0, 'total': 0};
      }

      // Parse grade and section from className (e.g., "Grade 10" or "Grade 10 - A")
      final gradeMatch = RegExp(r'Grade\s+(\d+)').firstMatch(className);
      final sectionMatch = RegExp(r'-\s*([A-Za-z])').firstMatch(className);
      final grade = gradeMatch?.group(1);
      final section = sectionMatch?.group(1);

      if (grade == null) {
        return {'present': 0, 'absent': 0, 'late': 0, 'total': 0};
      }


      // Query attendance records
      var query = _firestore
          .collection('attendance')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('standard', isEqualTo: grade);

      if (section != null && section.isNotEmpty) {
        query = query.where('section', isEqualTo: section);
      }

      final snapshot = await query.limit(120).get();

      int present = 0;
      int absent = 0;
      int late = 0;

      for (final doc in snapshot.docs) {
        final students = doc.data()['students'] as Map<String, dynamic>?;
        if (students == null) continue;

        // Look up student by auth UID (which is the studentId)
        final studentInfo = students[studentId] as Map<String, dynamic>?;
        if (studentInfo == null) continue;

        final status =
            studentInfo['status']?.toString().toLowerCase() ?? 'present';
        switch (status) {
          case 'present':
            present++;
            break;
          case 'absent':
            absent++;
            break;
          case 'late':
            late++;
            break;
        }
      }

      final total = present + absent + late;

      return {
        'present': present,
        'absent': absent,
        'late': late,
        'total': total,
      };
    } catch (e) {
      return {'present': 0, 'absent': 0, 'late': 0, 'total': 0};
    }
  }

  /// Get attendance percentage for student
  /// Deprecated: Use getStudentAttendanceBreakdown for more detailed data
  Future<double> getStudentAttendance(String studentId) async {
    try {
      final breakdown = await getStudentAttendanceBreakdown(studentId);
      final present = breakdown['present'] ?? 0;
      final total = breakdown['total'] ?? 0;

      if (total == 0) {
        return 0.0;
      }

      final attendancePercentage = (present / total * 100).clamp(0.0, 100.0);

      return attendancePercentage;
    } catch (e) {
      return 0.0;
    }
  }

  /// Get student's reward requests
  Future<List<RewardRequestModel>> getStudentRewardRequests(
    String studentId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('reward_requests')
          .where('studentId', isEqualTo: studentId)
          .orderBy('requestedOn', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => RewardRequestModel.fromJson(doc.data(), id: doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get student's reward requests stream
  Stream<List<RewardRequestModel>> getStudentRewardRequestsStream(
    String studentId,
  ) {
    return _firestore
        .collection('reward_requests')
        .where('studentId', isEqualTo: studentId)
        .orderBy('requestedOn', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RewardRequestModel.fromJson(doc.data(), id: doc.id))
              .toList(),
        );
  }

  /// Get announcements for student's class
  Future<List<Map<String, dynamic>>> getAnnouncementsForStudent(
    String studentId,
  ) async {
    try {
      // First get student data to know their class
      final studentDoc = await _firestore
          .collection('students')
          .doc(studentId)
          .get();

      if (!studentDoc.exists) return [];

      final studentData = studentDoc.data()!;
      final schoolCode = studentData['schoolCode'] as String?;
      final className = studentData['className'] as String?;
      final section = studentData['section'] as String?;

      if (schoolCode == null || className == null) return [];

      // Fetch class-level announcements (no section filter)
      final classQuerySnapshot = await _firestore
          .collection('announcements')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: className)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      // Optionally fetch section-level announcements for the student's section
      List<QueryDocumentSnapshot<Map<String, dynamic>>> sectionDocs = [];
      if (section != null && section.isNotEmpty) {
        final sectionQuerySnapshot = await _firestore
            .collection('announcements')
            .where('schoolCode', isEqualTo: schoolCode)
            .where('className', isEqualTo: className)
            .where('section', isEqualTo: section)
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();
        sectionDocs = sectionQuerySnapshot.docs;
      }

      // Merge and de-duplicate by id
      final allDocs = <String, Map<String, dynamic>>{};
      for (final doc in classQuerySnapshot.docs) {
        final data = doc.data();
        allDocs[doc.id] = {'id': doc.id, ...data};
      }
      for (final doc in sectionDocs) {
        final data = doc.data();
        allDocs[doc.id] = {'id': doc.id, ...data};
      }

      // Sort by createdAt desc (if present)
      final results = allDocs.values.toList();
      results.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        DateTime? ad;
        DateTime? bd;
        if (aTs is Timestamp) ad = aTs.toDate();
        if (bTs is Timestamp) bd = bTs.toDate();
        if (ad != null && bd != null) {
          return bd.compareTo(ad);
        }
        return 0;
      });

      // Limit to a reasonable number
      return results.take(20).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get announcements visible to a parent (aggregates announcements for all linked students)
  Future<List<Map<String, dynamic>>> getAnnouncementsForParentEmail(
    String parentEmail,
  ) async {
    try {
      // Find parent document
      final parentQuery = await _firestore
          .collection('parents')
          .where('email', isEqualTo: parentEmail)
          .limit(1)
          .get();

      if (parentQuery.docs.isEmpty) return [];

      final parentDoc = parentQuery.docs.first;
      final parentData = parentDoc.data();
      final linkedStudents = parentData['linkedStudents'] as List<dynamic>?;

      if (linkedStudents == null || linkedStudents.isEmpty) return [];

      final allDocs = <String, Map<String, dynamic>>{};

      for (final studentInfo in linkedStudents) {
        String className = (studentInfo['class'] as String?)?.trim() ?? '';
        String section = (studentInfo['section'] as String?)?.trim() ?? '';
        final studentId = (studentInfo['id'] as String?)?.trim();
        String schoolCode = (parentData['schoolCode'] as String?)?.trim() ?? '';

        // If schoolCode/class/section are missing in linkedStudents/parent, try to fetch student doc
        if (schoolCode.isEmpty || className.isEmpty) {
          if (studentId != null && studentId.isNotEmpty) {
            try {
              final studentDoc = await _firestore
                  .collection('students')
                  .doc(studentId)
                  .get();
              if (studentDoc.exists) {
                final s = studentDoc.data();
                schoolCode =
                    (s?['schoolCode'] as String?)?.trim() ?? schoolCode;
                className = (s?['className'] as String?)?.trim() ?? className;
                section = (s?['section'] as String?)?.trim() ?? section;
              }
            } catch (_) {}
          }
        }

        if (schoolCode.isEmpty) continue;
        if (className.isEmpty) continue;

        // Class-level announcements
        try {
          final classQuerySnapshot = await _firestore
              .collection('announcements')
              .where('schoolCode', isEqualTo: schoolCode)
              .where('className', isEqualTo: className)
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get();

          for (final doc in classQuerySnapshot.docs) {
            final data = doc.data();
            allDocs[doc.id] = {'id': doc.id, ...data};
          }
        } catch (e) {
        }

        // Section-level announcements
        if (section.isNotEmpty) {
          try {
            final sectionQuerySnapshot = await _firestore
                .collection('announcements')
                .where('schoolCode', isEqualTo: schoolCode)
                .where('className', isEqualTo: className)
                .where('section', isEqualTo: section)
                .orderBy('createdAt', descending: true)
                .limit(50)
                .get();

            for (final doc in sectionQuerySnapshot.docs) {
              final data = doc.data();
              allDocs[doc.id] = {'id': doc.id, ...data};
            }
          } catch (e) {
          }
        }
      }

      // Sort and return merged results
      final results = allDocs.values.toList();
      results.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        DateTime? ad;
        DateTime? bd;
        if (aTs is Timestamp) ad = aTs.toDate();
        if (bTs is Timestamp) bd = bTs.toDate();
        if (ad != null && bd != null) {
          return bd.compareTo(ad);
        }
        return 0;
      });

      return results.take(50).toList();
    } catch (e) {
      return [];
    }
  }

  /// Stream announcements visible to a parent. This listens to the parent
  /// document for linkedStudents changes and subscribes to the corresponding
  /// announcements queries for real-time updates.
  Stream<List<Map<String, dynamic>>> getAnnouncementsStreamForParent(
    String parentEmail,
  ) {
    // Controller to emit merged announcement lists
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    // Track active subscriptions for announcement queries
    final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> subs =
        [];
    final Map<String, Map<String, dynamic>> allDocs = {};

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? parentSub;

    void emitMerged() {
      final results = allDocs.values.toList();
      results.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        DateTime? ad;
        DateTime? bd;
        if (aTs is Timestamp) ad = aTs.toDate();
        if (bTs is Timestamp) bd = bTs.toDate();
        if (ad != null && bd != null) {
          return bd.compareTo(ad);
        }
        return 0;
      });
      controller.add(results.take(50).toList());
    }

    // Start listening to the parent document
    parentSub = _firestore
        .collection('parents')
        .where('email', isEqualTo: parentEmail)
        .limit(1)
        .snapshots()
        .listen(
          (parentQuery) {
            // Cancel previous announcement listeners
            for (final s in subs) {
              s.cancel();
            }
            subs.clear();
            allDocs.clear();

            if (parentQuery.docs.isEmpty) {
              controller.add([]);
              return;
            }

            final parentDoc = parentQuery.docs.first;
            final parentData = parentDoc.data();
            final linkedStudents =
                parentData['linkedStudents'] as List<dynamic>?;

            if (linkedStudents == null || linkedStudents.isEmpty) {
              controller.add([]);
              return;
            }

            // For each linked student, create announcement listeners (class-level and section-level)
            for (final studentInfo in linkedStudents) {
              final studentId = (studentInfo['id'] as String?)?.trim();
              String className =
                  (studentInfo['class'] as String?)?.trim() ?? '';
              String section =
                  (studentInfo['section'] as String?)?.trim() ?? '';
              String schoolCode =
                  (parentData['schoolCode'] as String?)?.trim() ?? '';

              // If critical fields missing, try to fetch student doc once (fire-and-forget)
              if (schoolCode.isEmpty || className.isEmpty) {
                if (studentId != null && studentId.isNotEmpty) {
                  _firestore
                      .collection('students')
                      .doc(studentId)
                      .get()
                      .then((sd) {
                        if (sd.exists) {
                          final s = sd.data();
                          schoolCode =
                              (s?['schoolCode'] as String?)?.trim() ??
                              schoolCode;
                          className =
                              (s?['className'] as String?)?.trim() ?? className;
                          section =
                              (s?['section'] as String?)?.trim() ?? section;
                        }
                      })
                      .whenComplete(() {
                        // After fetching student doc, we do not re-enter this parent listener callback
                        // immediately; announcements for that student may arrive on next parent snapshot.
                      });
                }
              }

              if (schoolCode.isEmpty) continue;
              if (className.isEmpty) continue;

              try {
                final classQuery = _firestore
                    .collection('announcements')
                    .where('schoolCode', isEqualTo: schoolCode)
                    .where('className', isEqualTo: className)
                    .orderBy('createdAt', descending: true)
                    .limit(50)
                    .withConverter<Map<String, dynamic>>(
                      fromFirestore: (snap, _) => snap.data()!,
                      toFirestore: (m, _) => m,
                    );

                final classSub = classQuery.snapshots().listen(
                  (snap) {
                    for (final doc in snap.docs) {
                      final data = doc.data();
                      allDocs[doc.id] = {'id': doc.id, ...data};
                    }
                    emitMerged();
                  },
                  onError: (e) {
                  },
                );

                subs.add(classSub);
              } catch (e) {
              }

              if (section.isNotEmpty) {
                try {
                  final sectionQuery = _firestore
                      .collection('announcements')
                      .where('schoolCode', isEqualTo: schoolCode)
                      .where('className', isEqualTo: className)
                      .where('section', isEqualTo: section)
                      .orderBy('createdAt', descending: true)
                      .limit(50)
                      .withConverter<Map<String, dynamic>>(
                        fromFirestore: (snap, _) => snap.data()!,
                        toFirestore: (m, _) => m,
                      );

                  final sectionSub = sectionQuery.snapshots().listen(
                    (snap) {
                      for (final doc in snap.docs) {
                        final data = doc.data();
                        allDocs[doc.id] = {'id': doc.id, ...data};
                      }
                      emitMerged();
                    },
                    onError: (e) {
                    },
                  );

                  subs.add(sectionSub);
                } catch (e) {
                }
              }
            }
          },
          onError: (e) {
            controller.add([]);
          },
        );

    // Handle cancellation: when no listeners remain, cleanup
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
      await parentSub?.cancel();
    };

    return controller.stream;
  }

  /// Get announcements stream for student's class
  Stream<List<Map<String, dynamic>>> getAnnouncementsStream(
    String schoolCode,
    String className,
    String? section,
  ) {
    var query = _firestore
        .collection('announcements')
        .where('schoolCode', isEqualTo: schoolCode)
        .where('className', isEqualTo: className);

    if (section != null && section.isNotEmpty) {
      query = query.where('section', isEqualTo: section);
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  /// Approve or reject a reward request
  Future<bool> updateRewardRequestStatus({
    required String requestId,
    required String status, // 'approved' or 'rejected'
    String? parentNote,
  }) async {
    try {
      final updateData = {
        'status': status,
        'parentApprovedAt': FieldValue.serverTimestamp(),
      };

      if (parentNote != null) {
        updateData['parentNote'] = parentNote;
      }

      await _firestore
          .collection('reward_requests')
          .doc(requestId)
          .update(updateData);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get student's reward points history
  Future<List<Map<String, dynamic>>> getStudentRewardHistory(
    String studentId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('student_rewards')
          .where('studentId', isEqualTo: studentId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get student's performance statistics
  Future<Map<String, dynamic>> getStudentPerformanceStats(
    String studentId,
  ) async {
    try {
      // Get all test results
      final testResults = await getStudentTestResults(studentId);

      if (testResults.isEmpty) {
        return {
          'totalTests': 0,
          'averageScore': 0.0,
          'highestScore': 0.0,
          'lowestScore': 0.0,
          'completedTests': 0,
          'pendingTests': 0,
        };
      }

      // Calculate statistics
      final completedTests = testResults; // All testResults are completed

      double totalScore = 0;
      double highestScore = 0;
      double lowestScore = 100;

      for (var result in completedTests) {
        // Use score field which is already a percentage (0-100)
        final percentage = result.score;
        totalScore += percentage;
        if (percentage > highestScore) highestScore = percentage;
        if (percentage < lowestScore) lowestScore = percentage;
      }

      final averageScore = completedTests.isNotEmpty
          ? totalScore / completedTests.length
          : 0.0;

      // Get pending tests count
      final pendingQuery = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'assigned')
          .get();

      return {
        'totalTests': testResults.length,
        'averageScore': averageScore,
        'highestScore': highestScore,
        'lowestScore': lowestScore == 100 ? 0.0 : lowestScore,
        'completedTests': completedTests.length,
        'pendingTests': pendingQuery.docs.length,
      };
    } catch (e) {
      return {
        'totalTests': 0,
        'averageScore': 0.0,
        'highestScore': 0.0,
        'lowestScore': 0.0,
        'completedTests': 0,
        'pendingTests': 0,
      };
    }
  }

  /// Get conversations between parent and teachers
  Future<List<Map<String, dynamic>>> getParentConversations(
    String parentId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('conversations')
          .where('parentId', isEqualTo: parentId)
          .orderBy('lastMessageAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get messages from a specific conversation
  Stream<List<Map<String, dynamic>>> getConversationMessages(
    String conversationId,
  ) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  /// Get student's attendance percentage
  /// Get upcoming tests for student
  Future<List<Map<String, dynamic>>> getUpcomingTests(String studentId) async {
    try {
      final now = DateTime.now();

      final querySnapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'assigned')
          .get();

      // Filter for future tests
      final upcomingTests = <Map<String, dynamic>>[];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final testId = data['testId'] as String?;

        if (testId != null) {
          // Get test details
          final testDoc = await _firestore
              .collection('scheduledTests')
              .doc(testId)
              .get();

          if (testDoc.exists) {
            final testData = testDoc.data()!;
            final startDate = testData['startDate'];

            DateTime? testDate;
            if (startDate is Timestamp) {
              testDate = startDate.toDate();
            } else if (startDate is String) {
              try {
                testDate = DateTime.parse(startDate);
              } catch (_) {}
            }

            if (testDate != null && testDate.isAfter(now)) {
              upcomingTests.add({
                'id': testId,
                'resultId': doc.id,
                ...testData,
                'assignmentData': data,
              });
            }
          }
        }
      }

      // Sort by date
      upcomingTests.sort((a, b) {
        final aDate = a['startDate'];
        final bDate = b['startDate'];

        DateTime? dateA;
        DateTime? dateB;

        if (aDate is Timestamp) dateA = aDate.toDate();
        if (bDate is Timestamp) dateB = bDate.toDate();

        if (dateA != null && dateB != null) {
          return dateA.compareTo(dateB);
        }
        return 0;
      });

      return upcomingTests;
    } catch (e) {
      return [];
    }
  }
}
