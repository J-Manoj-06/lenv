import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../models/test_result_model.dart';
import '../models/reward_request_model.dart';
import '../models/attendance_record.dart';

class ParentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Set<String> _approverRoles = {
    'teacher',
    'admin',
    'principal',
    'institute',
    'parent',
  };

  /// Get all children (students) linked to a parent by email
  /// First fetches parent document to get linkedStudents, then fetches each student
  /// Falls back to direct UID lookup on the parents collection if email query returns empty
  Future<List<StudentModel>> getChildrenByParentEmail(
    String parentEmail, {
    String? parentId,
  }) async {
    try {
      // Helper to coerce any value (String/int) to a trimmed String
      String? toStr(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }

      /// Resolve linked students using multiple strategies:
      /// 1. Query parents collection by email
      /// 2. Direct parents/{uid} doc lookup
      /// 3. Query parents by lowercase email
      /// 4. Query users/{uid} for children/linkedStudents array
      /// 5. Query students collection directly by parentEmail / parentId fields
      DocumentSnapshot<Map<String, dynamic>>? parentDoc;
      final lowerEmail = parentEmail.toLowerCase().trim();

      // Strategy 1: query parents collection by email
      debugPrint(
        '👨‍👩‍👧 [ParentService] S1: querying parents where email==$parentEmail',
      );
      final parentQuery = await _firestore
          .collection('parents')
          .where('email', isEqualTo: parentEmail)
          .limit(1)
          .get();
      debugPrint(
        '👨‍👩‍👧 [ParentService] S1 result: ${parentQuery.docs.length} docs',
      );

      if (parentQuery.docs.isNotEmpty) {
        parentDoc = parentQuery.docs.first;
        debugPrint('👨‍👩‍👧 [ParentService] S1 found: ${parentDoc.id}');
      }

      // Strategy 2: direct doc lookup by UID
      if (parentDoc == null && parentId != null && parentId.isNotEmpty) {
        debugPrint(
          '👨‍👩‍👧 [ParentService] S2: direct lookup parents/$parentId',
        );
        final directDoc = await _firestore
            .collection('parents')
            .doc(parentId)
            .get();
        debugPrint('👨‍👩‍👧 [ParentService] S2 exists: ${directDoc.exists}');
        if (directDoc.exists) {
          parentDoc = directDoc;
        }
      }

      // Strategy 3: query by lowercase email
      if (parentDoc == null && lowerEmail != parentEmail) {
        debugPrint(
          '👨‍👩‍👧 [ParentService] S3: querying parents where email==$lowerEmail',
        );
        final lowerQuery = await _firestore
            .collection('parents')
            .where('email', isEqualTo: lowerEmail)
            .limit(1)
            .get();
        debugPrint(
          '👨‍👩‍👧 [ParentService] S3 result: ${lowerQuery.docs.length} docs',
        );
        if (lowerQuery.docs.isNotEmpty) {
          parentDoc = lowerQuery.docs.first;
        }
      }

      // Strategy 4: look in users/{uid} for linkedStudents / children array
      if (parentDoc == null && parentId != null && parentId.isNotEmpty) {
        debugPrint(
          '👨‍👩‍👧 [ParentService] S4: checking users/$parentId for children',
        );
        final userDoc = await _firestore
            .collection('users')
            .doc(parentId)
            .get();
        debugPrint(
          '👨‍👩‍👧 [ParentService] S4 exists: ${userDoc.exists}, data keys: ${userDoc.data()?.keys.toList()}',
        );
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          // Accept any field that holds an array of student refs
          final linked =
              userData['linkedStudents'] ??
              userData['children'] ??
              userData['students'] ??
              userData['childIds'];
          if (linked != null && linked is List && linked.isNotEmpty) {
            debugPrint(
              '👨‍👩‍👧 [ParentService] S4 found linked array with ${linked.length} items',
            );
            // Fetch each student directly
            final futures = linked.map((item) async {
              final id = (item is Map ? (item['id'] ?? item['uid']) : item)
                  ?.toString()
                  .trim();
              if (id == null || id.isEmpty) return null;
              try {
                final doc = await _firestore
                    .collection('students')
                    .doc(id)
                    .get();
                if (doc.exists) return StudentModel.fromFirestore(doc);
              } catch (_) {}
              return null;
            }).toList();
            final results = await Future.wait(futures);
            final found = results.whereType<StudentModel>().toList();
            debugPrint(
              '👨‍👩‍👧 [ParentService] S4 resolved ${found.length} students',
            );
            if (found.isNotEmpty) return found;
          }
        }
      }

      // Strategy 5: search students collection directly by parentEmail or parentId
      if (parentDoc == null) {
        debugPrint(
          '👨‍👩‍👧 [ParentService] S5: searching students by parentEmail/parentId',
        );
        final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

        // Search by parentEmail field
        futures.add(
          _firestore
              .collection('students')
              .where('parentEmail', isEqualTo: parentEmail)
              .limit(20)
              .get(),
        );
        // Also try lowercase
        if (lowerEmail != parentEmail) {
          futures.add(
            _firestore
                .collection('students')
                .where('parentEmail', isEqualTo: lowerEmail)
                .limit(20)
                .get(),
          );
        }
        // Search by parentId (UID)
        if (parentId != null && parentId.isNotEmpty) {
          futures.add(
            _firestore
                .collection('students')
                .where('parentId', isEqualTo: parentId)
                .limit(20)
                .get(),
          );
        }

        final snapshots = await Future.wait(futures);
        final seen = <String>{};
        final found = <StudentModel>[];
        for (final snap in snapshots) {
          for (final doc in snap.docs) {
            if (seen.add(doc.id)) {
              found.add(StudentModel.fromFirestore(doc));
            }
          }
        }
        debugPrint(
          '👨‍👩‍👧 [ParentService] S5 found ${found.length} students',
        );
        if (found.isNotEmpty) return found;
      }

      if (parentDoc == null) {
        debugPrint(
          '👨‍👩‍👧 [ParentService] All strategies failed — no parent doc found for $parentEmail / $parentId',
        );
        return [];
      }

      final parentData = parentDoc.data()!;
      debugPrint(
        '👨‍👩‍👧 [ParentService] Parent doc found: ${parentDoc.id}, keys: ${parentData.keys.toList()}',
      );
      final linkedStudents = parentData['linkedStudents'] as List<dynamic>?;
      debugPrint('👨‍👩‍👧 [ParentService] linkedStudents: $linkedStudents');

      // If linkedStudents is empty/null, fall through to student-direct search (S5 below)
      if (linkedStudents != null && linkedStudents.isNotEmpty) {
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
            }

            // Cache linked-student fields for reuse (avoid recompute)
            final linkedName = toStr(studentInfo['name']);
            final linkedClass = toStr(studentInfo['class']);
            final linkedSection = toStr(studentInfo['section']);
            final linkedEmail =
                toStr(studentInfo['email']) ??
                toStr(studentInfo['studentEmail']) ??
                toStr(studentInfo['emailId']) ??
                toStr(studentInfo['mail']) ??
                toStr(studentInfo['contactEmail']);

            if (studentModel != null) {
              var hydratedStudent = studentModel;
              final sd = studentDoc.data();

              // Hydrate email: prioritize linkedEmail (parent's metadata), then student doc
              if (hydratedStudent.email.isEmpty) {
                final email =
                    linkedEmail ??
                    toStr(sd?['email']) ??
                    toStr(sd?['studentEmail']) ??
                    toStr(sd?['emailId']) ??
                    toStr(sd?['mail']) ??
                    toStr(sd?['contactEmail']);
                if (email != null && email.isNotEmpty) {
                  hydratedStudent = hydratedStudent.copyWith(email: email);
                }
              }

              // Fill in missing name/class/section from linkedStudents data only
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
                name: linkedName ?? 'Unknown Student',
                email: '',
                schoolCode: parentData['schoolCode'] as String? ?? '',
                className: linkedClass ?? '',
                section: linkedSection ?? '',
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
        // Deduplicate by UID in case linkedStudents array has duplicate entries
        final seenUids = <String>{};
        final children = studentResults
            .whereType<StudentModel>()
            .where((s) => seenUids.add(s.uid))
            .toList();
        debugPrint(
          '👨‍👩‍👧 [ParentService] linkedStudents resolved ${children.length} students',
        );
        if (children.isNotEmpty) return children;
      } // end if (linkedStudents not empty)

      // Strategy 5 (final fallback): search students collection directly
      // This handles the case where the parent doc exists but linkedStudents is empty/not populated
      debugPrint(
        '👨‍👩‍👧 [ParentService] S5 (final): searching students by parentEmail/parentId',
      );
      {
        final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
        final resolvedEmail = parentData['email'] as String? ?? parentEmail;
        final resolvedLower = resolvedEmail.toLowerCase().trim();

        futures.add(
          _firestore
              .collection('students')
              .where('parentEmail', isEqualTo: resolvedEmail)
              .limit(20)
              .get(),
        );
        if (resolvedLower != resolvedEmail) {
          futures.add(
            _firestore
                .collection('students')
                .where('parentEmail', isEqualTo: resolvedLower)
                .limit(20)
                .get(),
          );
        }
        if (parentId != null && parentId.isNotEmpty) {
          futures.add(
            _firestore
                .collection('students')
                .where('parentId', isEqualTo: parentId)
                .limit(20)
                .get(),
          );
        }
        // Also try parentPhone if stored on the parent doc
        final phone = parentData['phoneNumber'] as String?;
        if (phone != null && phone.isNotEmpty) {
          futures.add(
            _firestore
                .collection('students')
                .where('parentPhone', isEqualTo: phone)
                .limit(20)
                .get(),
          );
        }

        final snapshots = await Future.wait(futures);
        final seen = <String>{};
        final found = <StudentModel>[];
        for (final snap in snapshots) {
          for (final doc in snap.docs) {
            if (seen.add(doc.id)) found.add(StudentModel.fromFirestore(doc));
          }
        }
        debugPrint(
          '👨‍👩‍👧 [ParentService] S5 found ${found.length} students',
        );
        if (found.isNotEmpty) return found;
      }

      debugPrint(
        '👨‍👩‍👧 [ParentService] All strategies exhausted — returning empty',
      );
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get real-time stream of children for a parent
  /// Note: This returns a stream but checks parent's linkedStudents on each update
  Stream<List<StudentModel>> getChildrenStream(
    String parentEmail, {
    String? parentId,
  }) async* {
    try {
      // Resolve parent document using the same multi-strategy lookup
      DocumentSnapshot<Map<String, dynamic>>? parentDocSnap;

      final parentQuery = await _firestore
          .collection('parents')
          .where('email', isEqualTo: parentEmail)
          .limit(1)
          .get();

      if (parentQuery.docs.isNotEmpty) {
        parentDocSnap = parentQuery.docs.first;
      }

      if (parentDocSnap == null && parentId != null && parentId.isNotEmpty) {
        final directDoc = await _firestore
            .collection('parents')
            .doc(parentId)
            .get();
        if (directDoc.exists) parentDocSnap = directDoc;
      }

      if (parentDocSnap == null) {
        final lowerEmail = parentEmail.toLowerCase().trim();
        if (lowerEmail != parentEmail) {
          final lowerQuery = await _firestore
              .collection('parents')
              .where('email', isEqualTo: lowerEmail)
              .limit(1)
              .get();
          if (lowerQuery.docs.isNotEmpty) parentDocSnap = lowerQuery.docs.first;
        }
      }

      if (parentDocSnap == null) {
        yield [];
        return;
      }

      final parentData = parentDocSnap.data()!;
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
          } catch (e) {}
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
      final snapshots = await Future.wait([
        _firestore
            .collection('reward_requests')
            .where('studentId', isEqualTo: studentId)
            .get(),
        _firestore
            .collection('reward_requests')
            .where('student_id', isEqualTo: studentId)
            .get(),
      ]);

      final deduped = <String, RewardRequestModel>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          deduped[doc.id] = RewardRequestModel.fromJson(doc.data(), id: doc.id);
        }
      }

      final requests = deduped.values.toList()
        ..sort((a, b) => b.requestedOn.compareTo(a.requestedOn));
      return requests;
    } catch (e) {
      return [];
    }
  }

  /// Get student's reward requests stream
  Stream<List<RewardRequestModel>> getStudentRewardRequestsStream(
    String studentId,
  ) {
    final streams = <Stream<List<RewardRequestModel>>>[
      _firestore
          .collection('reward_requests')
          .where('studentId', isEqualTo: studentId)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => RewardRequestModel.fromJson(doc.data(), id: doc.id),
                )
                .toList(),
          ),
      _firestore
          .collection('reward_requests')
          .where('student_id', isEqualTo: studentId)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => RewardRequestModel.fromJson(doc.data(), id: doc.id),
                )
                .toList(),
          ),
    ];

    return _combineRewardStreams(streams);
  }

  /// Get reward requests stream for ALL children of a parent (real-time)
  Stream<List<RewardRequestModel>> getParentRewardRequestsStream(
    List<String> studentIds, {
    String? parentId,
  }) {
    print(
      '🔵 ParentService: getParentRewardRequestsStream for students: $studentIds',
    );
    if (studentIds.isEmpty && (parentId == null || parentId.isEmpty)) {
      return Stream.value([]);
    }

    final streams = <Stream<List<RewardRequestModel>>>[];

    // Firestore 'in' query supports max 10 items per chunk
    final chunks = <List<String>>[];
    for (var i = 0; i < studentIds.length; i += 10) {
      chunks.add(
        studentIds.sublist(
          i,
          (i + 10 < studentIds.length) ? i + 10 : studentIds.length,
        ),
      );
    }

    for (final chunk in chunks) {
      // Query by snake_case field (new request format)
      streams.add(
        _safeStream(
          _firestore
              .collection('reward_requests')
              .where('student_id', whereIn: chunk)
              .snapshots()
              .map((snapshot) {
                print(
                  '🔵 ParentService: Got ${snapshot.docs.length} reward docs (student_id)',
                );
                return snapshot.docs
                    .map(
                      (doc) =>
                          RewardRequestModel.fromJson(doc.data(), id: doc.id),
                    )
                    .toList();
              }),
        ),
      );

      // Query by camelCase field (old request format)
      streams.add(
        _safeStream(
          _firestore
              .collection('reward_requests')
              .where('studentId', whereIn: chunk)
              .snapshots()
              .map((snapshot) {
                print(
                  '🔵 ParentService: Got ${snapshot.docs.length} reward docs (studentId)',
                );
                return snapshot.docs
                    .map(
                      (doc) =>
                          RewardRequestModel.fromJson(doc.data(), id: doc.id),
                    )
                    .toList();
              }),
        ),
      );
    }

    // Fallback: also query by parent_id so approved requests always appear
    if (parentId != null && parentId.isNotEmpty) {
      streams.add(
        _safeStream(
          _firestore
              .collection('reward_requests')
              .where('parent_id', isEqualTo: parentId)
              .snapshots()
              .map(
                (snapshot) => snapshot.docs
                    .map(
                      (doc) =>
                          RewardRequestModel.fromJson(doc.data(), id: doc.id),
                    )
                    .toList(),
              ),
        ),
      );
      // Also try camelCase parentId field
      streams.add(
        _safeStream(
          _firestore
              .collection('reward_requests')
              .where('parentId', isEqualTo: parentId)
              .snapshots()
              .map(
                (snapshot) => snapshot.docs
                    .map(
                      (doc) =>
                          RewardRequestModel.fromJson(doc.data(), id: doc.id),
                    )
                    .toList(),
              ),
        ),
      );
    }

    if (streams.isEmpty) return Stream.value([]);
    return _combineRewardStreams(streams);
  }

  /// Wraps a stream so errors emit an empty list instead of terminating the stream
  Stream<List<RewardRequestModel>> _safeStream(
    Stream<List<RewardRequestModel>> source,
  ) {
    return source.transform(
      StreamTransformer<
        List<RewardRequestModel>,
        List<RewardRequestModel>
      >.fromHandlers(
        handleError: (error, stackTrace, sink) {
          // Swallow the error and emit empty list so the combined stream keeps working
          sink.add([]);
        },
      ),
    );
  }

  Stream<List<RewardRequestModel>> _combineRewardStreams(
    List<Stream<List<RewardRequestModel>>> streams,
  ) {
    if (streams.isEmpty) {
      return Stream.value([]);
    }

    final controller = StreamController<List<RewardRequestModel>>();
    final latest = List<List<RewardRequestModel>?>.filled(streams.length, null);
    final subscriptions = <StreamSubscription<List<RewardRequestModel>>>[];

    void emitMerged() {
      final merged = <String, RewardRequestModel>{};
      for (final list in latest) {
        if (list == null) continue;
        for (final req in list) {
          merged[req.id] = req;
        }
      }

      final sorted = merged.values.toList()
        ..sort((a, b) => b.requestedOn.compareTo(a.requestedOn));
      controller.add(sorted);
    }

    for (var i = 0; i < streams.length; i++) {
      final sub = streams[i].listen((data) {
        latest[i] = data;
        emitMerged();
      }, onError: controller.addError);
      subscriptions.add(sub);
    }

    controller.onCancel = () async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    };

    return controller.stream;
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
        } catch (e) {}

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
          } catch (e) {}
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

                final classSub = classQuery.snapshots().listen((snap) {
                  for (final doc in snap.docs) {
                    final data = doc.data();
                    allDocs[doc.id] = {'id': doc.id, ...data};
                  }
                  emitMerged();
                }, onError: (e) {});

                subs.add(classSub);
              } catch (e) {}

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

                  final sectionSub = sectionQuery.snapshots().listen((snap) {
                    for (final doc in snap.docs) {
                      final data = doc.data();
                      allDocs[doc.id] = {'id': doc.id, ...data};
                    }
                    emitMerged();
                  }, onError: (e) {});

                  subs.add(sectionSub);
                } catch (e) {}
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

  Future<Map<String, dynamic>> approveRewardByLink({
    required String requestId,
  }) async {
    try {
      final roleResult = await _validateApproverRole();
      if (!(roleResult['success'] as bool)) return roleResult;

      final approverId = _auth.currentUser?.uid;
      final requestRef = _firestore
          .collection('reward_requests')
          .doc(requestId);

      // Pre-fetch request data OUTSIDE the transaction so we know which
      // student refs to read inside the transaction (all reads must precede
      // all writes inside a Firestore transaction on mobile).
      final preSnap = await requestRef.get();
      if (!preSnap.exists) throw Exception('Reward request not found');
      final preData = preSnap.data() ?? <String, dynamic>{};
      final studentId =
          (preData['student_id'] as String?) ??
          (preData['studentId'] as String?) ??
          '';
      int pointsLocked = 0;
      if (preData['points'] is Map) {
        pointsLocked =
            ((preData['points'] as Map)['locked'] as num?)?.toInt() ?? 0;
      }
      if (pointsLocked == 0) {
        pointsLocked = (preData['pointsRequired'] as num?)?.toInt() ?? 0;
      }

      final studentRef = studentId.isNotEmpty
          ? _firestore.collection('students').doc(studentId)
          : null;
      final userRef = studentId.isNotEmpty
          ? _firestore.collection('users').doc(studentId)
          : null;

      await _firestore.runTransaction((transaction) async {
        // ── ALL READS FIRST ──────────────────────────────────────────────
        final requestSnap = await transaction.get(requestRef);
        if (!requestSnap.exists) throw Exception('Reward request not found');

        final studentSnap = studentRef != null
            ? await transaction.get(studentRef)
            : null;
        final userSnap = userRef != null
            ? await transaction.get(userRef)
            : null;

        // ── ALL WRITES AFTER ─────────────────────────────────────────────
        // Update request status - use both old and new status strings for compatibility
        transaction.update(requestRef, {
          'status': 'approved',
          'purchaseMethod': 'link',
          'purchase_method': 'link',
          'purchase_mode': 'link',
          'priceEntered': false,
          'pointsDeducted': pointsLocked,
          'points_deducted': pointsLocked,
          'points.deducted': pointsLocked,
          'approved_on': FieldValue.serverTimestamp(),
          'approvedOn': FieldValue.serverTimestamp(),
          'parentApprovedAt': FieldValue.serverTimestamp(),
          'approvedBy': approverId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Deduct points from student and convert locked → deducted
        if (studentId.isNotEmpty && pointsLocked > 0) {
          if (studentSnap != null && studentSnap.exists) {
            transaction.update(studentRef!, {
              'locked_points': FieldValue.increment(-pointsLocked),
              'deducted_points': FieldValue.increment(pointsLocked),
              'rewardPoints': FieldValue.increment(-pointsLocked),
              'totalPoints': FieldValue.increment(-pointsLocked),
              'points': FieldValue.increment(-pointsLocked),
              'reward_points': FieldValue.increment(-pointsLocked),
              'lastRewardRedemptionAt': FieldValue.serverTimestamp(),
            });
          }

          if (userSnap != null && userSnap.exists) {
            transaction.update(userRef!, {
              'rewardPoints': FieldValue.increment(-pointsLocked),
              'totalPoints': FieldValue.increment(-pointsLocked),
              'points': FieldValue.increment(-pointsLocked),
              'reward_points': FieldValue.increment(-pointsLocked),
              'lastRewardRedemptionAt': FieldValue.serverTimestamp(),
            });
          }

          // Create transaction log
          final logRef = _firestore.collection('reward_transactions').doc();
          transaction.set(logRef, {
            'type': 'reward_redemption',
            'student_id': studentId,
            'request_id': requestId,
            'points_deducted': pointsLocked,
            'purchase_method': 'link',
            'approved_by': approverId,
            'created_at': FieldValue.serverTimestamp(),
          });

          // Add negative entry to student_rewards so dashboard, leaderboard,
          // and all point displays reflect the deduction immediately.
          final rewardHistoryRef = _firestore
              .collection('student_rewards')
              .doc();
          transaction.set(rewardHistoryRef, {
            'studentId': studentId,
            'pointsEarned': -pointsLocked, // negative = deduction
            'type': 'reward_redemption',
            'rewardId': requestId,
            'description': 'Reward redeemed (product link)',
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      });

      await _appendRewardAudit(
        requestId: requestId,
        action: 'approved_link',
        metadata: {'purchase_method': 'link'},
      );

      return {'success': true, 'message': 'Reward approved via product link'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to approve by link: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> markRewardPendingPrice({
    required String requestId,
  }) async {
    try {
      final roleResult = await _validateApproverRole();
      if (!(roleResult['success'] as bool)) return roleResult;

      final approverId = _auth.currentUser?.uid;
      await _firestore.collection('reward_requests').doc(requestId).update({
        'status': 'pending_price',
        'purchaseMethod': 'manual',
        'purchase_method': 'manual',
        'purchase_mode': 'manual',
        'priceEntered': false,
        'pointsDeducted': 0,
        'approvedBy': approverId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _appendRewardAudit(
        requestId: requestId,
        action: 'pending_price',
        metadata: {'purchase_method': 'manual'},
      );

      return {
        'success': true,
        'message': 'Reward marked as pending price entry',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to mark pending price: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> approveRewardManualWithPrice({
    required String requestId,
    required double enteredPrice,
  }) async {
    if (enteredPrice <= 0) {
      return {'success': false, 'message': 'Price must be greater than zero'};
    }

    try {
      final roleResult = await _validateApproverRole();
      if (!(roleResult['success'] as bool)) return roleResult;

      final pointsToDeduct = enteredPrice.round();
      final approverId = _auth.currentUser?.uid;
      final requestRef = _firestore
          .collection('reward_requests')
          .doc(requestId);

      await _firestore.runTransaction((transaction) async {
        final requestSnap = await transaction.get(requestRef);
        if (!requestSnap.exists) {
          throw Exception('Reward request not found');
        }

        final requestData = requestSnap.data() ?? <String, dynamic>{};
        final currentStatus = (requestData['status'] ?? '').toString();
        final alreadyEntered =
            (requestData['priceEntered'] as bool?) == true ||
            (requestData['price_entered'] as bool?) == true;
        if (alreadyEntered || currentStatus == 'approved') {
          throw Exception('This reward is already approved');
        }
        if (currentStatus == 'rejected') {
          throw Exception('Rejected rewards cannot be approved');
        }

        final studentId =
            (requestData['student_id'] as String?) ??
            (requestData['studentId'] as String?) ??
            '';
        if (studentId.isEmpty) {
          throw Exception('Student information missing on request');
        }

        final studentRef = _firestore.collection('students').doc(studentId);
        final userRef = _firestore.collection('users').doc(studentId);

        final studentSnap = await transaction.get(studentRef);
        final userSnap = await transaction.get(userRef);

        final studentData = studentSnap.data() ?? <String, dynamic>{};
        final userData = userSnap.data() ?? <String, dynamic>{};

        int toInt(dynamic value) {
          if (value is int) return value;
          if (value is num) return value.toInt();
          if (value is String) return int.tryParse(value) ?? 0;
          return 0;
        }

        final availableInStudent = toInt(studentData['rewardPoints']);
        final availableInUser = toInt(userData['rewardPoints']);
        final available = availableInStudent > 0
            ? availableInStudent
            : availableInUser;

        if (available > 0 && available < pointsToDeduct) {
          throw Exception(
            'Insufficient points: $available available, $pointsToDeduct required',
          );
        }

        transaction.update(requestRef, {
          'status': 'approved',
          'purchaseMethod': 'manual',
          'purchase_method': 'manual',
          'purchase_mode': 'manual',
          'priceEntered': true,
          'price_entered': true,
          'enteredPrice': enteredPrice,
          'entered_price': enteredPrice,
          'manual_price': enteredPrice,
          'price': enteredPrice,
          'pointsDeducted': pointsToDeduct,
          'points_deducted': pointsToDeduct,
          'points.deducted': pointsToDeduct,
          'approved_on': FieldValue.serverTimestamp(),
          'approvedOn': FieldValue.serverTimestamp(),
          'parentApprovedAt': FieldValue.serverTimestamp(),
          'approvedBy': approverId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Get locked points from the request (set during creation)
        int lockedPoints = 0;
        if (requestData['points'] is Map) {
          lockedPoints =
              ((requestData['points'] as Map)['locked'] as num?)?.toInt() ?? 0;
        }
        if (lockedPoints == 0) {
          lockedPoints = (requestData['pointsRequired'] as num?)?.toInt() ?? 0;
        }

        if (studentSnap.exists) {
          final updateData = <String, dynamic>{
            'rewardPoints': FieldValue.increment(-pointsToDeduct),
            'totalPoints': FieldValue.increment(-pointsToDeduct),
            'points': FieldValue.increment(-pointsToDeduct),
            'reward_points': FieldValue.increment(-pointsToDeduct),
            'lastRewardRedemptionAt': FieldValue.serverTimestamp(),
          };
          // Convert locked points to deducted points
          if (lockedPoints > 0) {
            updateData['locked_points'] = FieldValue.increment(-lockedPoints);
            updateData['deducted_points'] = FieldValue.increment(
              pointsToDeduct,
            );
          } else {
            // If no locked points tracked, deduct from available_points
            updateData['available_points'] = FieldValue.increment(
              -pointsToDeduct,
            );
          }
          transaction.update(studentRef, updateData);
        }

        if (userSnap.exists) {
          transaction.update(userRef, {
            'rewardPoints': FieldValue.increment(-pointsToDeduct),
            'totalPoints': FieldValue.increment(-pointsToDeduct),
            'points': FieldValue.increment(-pointsToDeduct),
            'reward_points': FieldValue.increment(-pointsToDeduct),
            'available_points': FieldValue.increment(-pointsToDeduct),
            'lastRewardRedemptionAt': FieldValue.serverTimestamp(),
          });
        }

        final logRef = _firestore.collection('reward_transactions').doc();
        transaction.set(logRef, {
          'type': 'reward_redemption',
          'studentId': studentId,
          'rewardId': requestId,
          'pointsDeducted': pointsToDeduct,
          'price': enteredPrice,
          'purchaseMethod': 'manual',
          'approvedBy': approverId,
          'timestamp': FieldValue.serverTimestamp(),
        });

        final historyRef = _firestore.collection('student_rewards').doc();
        transaction.set(historyRef, {
          'studentId': studentId,
          'pointsEarned':
              -pointsToDeduct, // negative = deduction; dashboard & leaderboard sum this field
          'type': 'reward_redemption',
          'rewardId': requestId,
          'description': 'Reward redemption (manual purchase)',
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      await _appendRewardAudit(
        requestId: requestId,
        action: 'approved_manual_price_entered',
        metadata: {
          'purchase_method': 'manual',
          'entered_price': enteredPrice,
          'points_deducted': pointsToDeduct,
        },
      );

      return {
        'success': true,
        'message': 'Reward approved and $pointsToDeduct points deducted',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to approve manual purchase: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> _validateApproverRole() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final role = (userDoc.data()?['role'] as String? ?? '').toLowerCase();
    if (!_approverRoles.contains(role)) {
      return {
        'success': false,
        'message': 'You are not authorized to approve rewards',
      };
    }

    return {'success': true, 'message': 'Authorized'};
  }

  Future<void> _appendRewardAudit({
    required String requestId,
    required String action,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _firestore.collection('reward_requests').doc(requestId).update({
        'audit': FieldValue.arrayUnion([
          {
            'actor': _auth.currentUser?.uid,
            'action': action,
            'timestamp': DateTime.now().toIso8601String(),
            'metadata': ?metadata,
          },
        ]),
      });
    } catch (_) {}
  }

  /// Delete a reward request (for pending or rejected requests)
  Future<void> deleteRewardRequest(String requestId) async {
    try {
      await _firestore.collection('reward_requests').doc(requestId).delete();
    } catch (e) {
      throw Exception('Failed to delete reward request: $e');
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

  /// Get student's attendance records for a specific month
  Future<List<AttendanceRecord>> getStudentAttendanceForMonth(
    String studentId,
    DateTime month,
  ) async {
    try {
      print(
        'DEBUG: getStudentAttendanceForMonth called for studentId: $studentId, month: $month',
      );

      // Try to get student details from students collection first, then users
      DocumentSnapshot<Map<String, dynamic>> studentDoc;

      try {
        print('DEBUG: Trying to fetch from students collection...');
        studentDoc = await _firestore
            .collection('students')
            .doc(studentId)
            .get();
        print('DEBUG: Found in students collection: ${studentDoc.exists}');
      } catch (e) {
        print(
          'DEBUG: Error fetching from students collection: $e, trying users collection...',
        );
        studentDoc = await _firestore.collection('users').doc(studentId).get();
        print('DEBUG: Found in users collection: ${studentDoc.exists}');
      }

      if (!studentDoc.exists) {
        print('DEBUG: Student document does not exist');
        return [];
      }

      final studentData = studentDoc.data();
      print('DEBUG: Student data: $studentData');

      String? className = studentData?['className'] as String?;
      String? schoolCode = studentData?['schoolCode'] as String?;

      // If className not found, try alternates
      if (className == null) {
        className = studentData?['class'] as String?;
        print('DEBUG: className from class field: $className');
      }
      if (className == null) {
        className = studentData?['standard'] as String?;
        print('DEBUG: className from standard field: $className');
      }
      if (schoolCode == null) {
        schoolCode = studentData?['school'] as String?;
        print('DEBUG: schoolCode from school field: $schoolCode');
      }

      print('DEBUG: Final className: $className, schoolCode: $schoolCode');

      if (className == null || schoolCode == null || schoolCode.isEmpty) {
        print('DEBUG: Missing className or schoolCode');
        return [];
      }

      // Parse grade and section from className (e.g., "Grade 10", "Grade 10 - A", "10", "10-A")
      String? grade;
      String? section;

      final gradeMatch = RegExp(r'Grade\s+(\d+)').firstMatch(className);
      if (gradeMatch != null) {
        grade = gradeMatch.group(1);
        final sectionMatch = RegExp(r'-\s*([A-Za-z])').firstMatch(className);
        section = sectionMatch?.group(1);
        print(
          'DEBUG: Parsed as Grade format - grade: $grade, section: $section',
        );
      } else {
        // Try parsing "10" or "10-A" format
        final parts = className.split('-');
        grade = parts[0].trim().replaceAll(RegExp(r'[^0-9]'), '');
        if (parts.length > 1) {
          section = parts[1].trim();
        }
      }

      // IMPORTANT: If section not found in className, check the separate 'section' field
      if (section == null || section.isEmpty) {
        final sectionField = studentData?['section'] as String?;
        if (sectionField != null && sectionField.isNotEmpty) {
          section = sectionField;
          print('DEBUG: Section from separate field: $section');
        }
      }

      if (grade == null || grade.isEmpty) {
        print('DEBUG: Could not parse grade from className: $className');
        return [];
      }

      print('DEBUG: Final parsed - grade: $grade, section: $section');

      // Query attendance records for the specified month
      final startOfMonth = DateTime(month.year, month.month, 1);
      final endOfMonth = DateTime(month.year, month.month + 1, 0);

      print('DEBUG: Querying attendance from $startOfMonth to $endOfMonth');
      print(
        'DEBUG: Query params - schoolCode: $schoolCode, grade: $grade, section: $section',
      );

      // Query without section first to see all attendance docs for this grade
      var query = _firestore
          .collection('attendance')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('standard', isEqualTo: grade);

      // Note: Not filtering by section here because the section field structure may vary
      // We'll check section in post-processing if needed

      final querySnapshot = await query.get();
      print('DEBUG: Found ${querySnapshot.docs.length} attendance documents');

      final List<AttendanceRecord> records = [];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final dateField = data['date'];

        // Check if date is within month range
        DateTime? docDate;
        if (dateField is Timestamp) {
          docDate = dateField.toDate();
        } else if (dateField is String) {
          try {
            docDate = DateTime.parse(dateField);
          } catch (_) {
            print('DEBUG: Failed to parse date: $dateField');
            continue;
          }
        }

        if (docDate == null ||
            docDate.isBefore(startOfMonth) ||
            docDate.isAfter(endOfMonth)) {
          print('DEBUG: Date $docDate is outside month range');
          continue;
        }

        final students = data['students'] as Map<String, dynamic>?;
        if (students == null) {
          print('DEBUG: No students map in attendance doc');
          continue;
        }

        print('DEBUG: Students in this doc: ${students.keys}');

        // Check if this student has an attendance record for this date
        final studentInfo = students[studentId] as Map<String, dynamic>?;
        if (studentInfo != null) {
          final status =
              studentInfo['status']?.toString().toLowerCase() ?? 'present';
          print('DEBUG: Found attendance for $studentId on $docDate: $status');
          records.add(AttendanceRecord(date: docDate, status: status));
        } else {
          print('DEBUG: Student $studentId not found in this attendance doc');
        }
      }

      print('DEBUG: Total records found: ${records.length}');
      return records;
    } catch (e, st) {
      print('DEBUG: Error in getStudentAttendanceForMonth: $e');
      print('DEBUG: Stack trace: $st');
      return [];
    }
  }
}
