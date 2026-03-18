import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../models/product_model.dart';
import '../models/reward_request_model.dart';

/// Repository for managing reward catalog and requests
class RewardsRepository {
  final FirebaseFirestore _firestore;
  static const String catalogCollection = 'rewards_catalog';
  static const String requestsCollection = 'reward_requests';
  static const String studentsCollection = 'students';
  static const String parentsCollection = 'parents';

  List<ProductModel>? _catalogCache;

  RewardsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Get all products from catalog (with caching)
  Future<List<ProductModel>> getCatalog({bool forceRefresh = false}) async {
    try {
      // Return cache if available and not forcing refresh
      if (_catalogCache != null && !forceRefresh) {
        return _catalogCache!;
      }

      // Try to fetch from Firestore
      final snapshot = await _firestore
          .collection(catalogCollection)
          .get()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw Exception('Firestore timeout'),
          );

      if (snapshot.docs.isNotEmpty) {
        _catalogCache = snapshot.docs.map((doc) {
          final data = doc.data();
          data['_documentId'] = doc.id;
          return ProductModel.fromMap(data);
        }).toList();
        return _catalogCache!;
      }

      // Fallback to dummy JSON if Firestore is empty
      return _loadDummyCatalog();
    } catch (e) {
      // Fallback to dummy JSON on error
      return _loadDummyCatalog();
    }
  }

  /// Load dummy catalog from assets
  Future<List<ProductModel>> _loadDummyCatalog() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/dummy_rewards.json',
      );
      final jsonList = jsonDecode(jsonString) as List;
      final products = jsonList
          .map((item) => ProductModel.fromMap(item as Map<String, dynamic>))
          .toList();
      return products;
    } catch (e) {
      return [];
    }
  }

  /// Search products by query
  Future<List<ProductModel>> searchProducts(String query) async {
    final catalog = await getCatalog();
    if (query.isEmpty) {
      return catalog;
    }

    final lowerQuery = query.toLowerCase();
    final results = catalog
        .where(
          (p) =>
              p.title.toLowerCase().contains(lowerQuery) ||
              (p.description?.toLowerCase().contains(lowerQuery) ?? false),
        )
        .toList();
    return results;
  }

  /// Get product by ID
  Future<ProductModel?> getProductById(String productId) async {
    try {
      final doc = await _firestore
          .collection(catalogCollection)
          .doc(productId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        data['_documentId'] = doc.id;
        return ProductModel.fromMap(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Create a reward request (with Firestore transaction)
  Future<RewardRequestModel> createRequest({
    required String studentId,
    required String parentId,
    required ProductModel product,
    required int pointsRequired,
    required DateTime lockExpiresAt,
  }) async {
    try {
      final requestRef = _firestore.collection(requestsCollection).doc();

      final studentRef = _firestore
          .collection(studentsCollection)
          .doc(studentId);

      // Ensure student document exists with points structure
      await _ensureStudentPointsStructure(studentId);

      // Run transaction to ensure atomicity
      await _firestore.runTransaction((transaction) async {
        // Get current student data
        final studentSnap = await transaction.get(studentRef);

        if (!studentSnap.exists) {
          throw Exception(
            'Student profile not found. Please ensure student is properly initialized.',
          );
        }

        final studentData = studentSnap.data() ?? {};

        final availablePointsRaw =
            studentData['available_points'] ??
            studentData['pointsEarned'] ??
            studentData['points'];
        final lockedPointsRaw =
            studentData['locked_points'] ?? studentData['lockedPoints'] ?? 0;
        final availablePoints = (availablePointsRaw is num)
            ? availablePointsRaw.toInt()
            : 0;
        final lockedPoints = (lockedPointsRaw is num)
            ? lockedPointsRaw.toInt()
            : 0;

        // Check if student has enough points
        if (availablePoints < pointsRequired) {
          throw Exception(
            'Insufficient points: You have $availablePoints points but need $pointsRequired points',
          );
        }

        // Create audit entry
        final auditEntry = AuditEntry(
          actor: studentId,
          action: 'requested',
          timestamp: DateTime.now(),
        );

        // Create request document
        final request = RewardRequestModel(
          requestId: requestRef.id,
          studentId: studentId,
          parentId: parentId,
          productSnapshot: product,
          pointsData: PointsData(
            required: pointsRequired,
            locked: pointsRequired,
            deducted: 0,
          ),
          status: RewardRequestStatus.pendingParentApproval,
          timestamps: TimestampsData(
            requestedAt: DateTime.now(),
            lockExpiresAt: lockExpiresAt,
          ),
          audit: [auditEntry],
        );

        final requestMap = request.toMap();

        // Inject student name so parent-side fromJson() can display it correctly
        final resolvedStudentName =
            (studentData['name'] as String?)?.trim() ??
            (studentData['studentName'] as String?)?.trim() ??
            '';
        if (resolvedStudentName.isNotEmpty) {
          requestMap['student_name'] = resolvedStudentName;
          requestMap['studentName'] = resolvedStudentName;
        }

        // Update student points
        transaction.update(studentRef, {
          'available_points': availablePoints - pointsRequired,
          'locked_points': lockedPoints + pointsRequired,
          'last_reward_request': Timestamp.now(),
        });

        // Create request document
        transaction.set(requestRef, requestMap);
      });

      // Fetch and return created request

      // Wait a moment for Firestore to propagate
      await Future.delayed(const Duration(milliseconds: 100));

      final doc = await requestRef.get();

      if (!doc.exists) {
        throw Exception('Request document not found after creation');
      }

      final docData = doc.data();
      if (docData == null) {
        throw Exception('Document data is null');
      }

      try {
        final result = RewardRequestModel.fromMap(docData);
        return result;
      } catch (parseError) {
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update request status
  Future<void> updateRequestStatus({
    required String requestId,
    required RewardRequestStatus newStatus,
    required String userId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final requestRef = _firestore
            .collection(requestsCollection)
            .doc(requestId);
        final requestSnap = await transaction.get(requestRef);

        if (!requestSnap.exists) {
          throw Exception('Request not found');
        }

        final request = RewardRequestModel.fromMap(requestSnap.data()!);

        // Validate transition
        if (!request.canTransitionTo(newStatus)) {
          throw Exception('Invalid status transition');
        }

        // Create audit entry
        final auditEntry = AuditEntry(
          actor: userId,
          action: newStatus.value,
          timestamp: DateTime.now(),
          metadata: metadata,
        );

        // Update request
        transaction.update(requestRef, {
          'status': newStatus.value,
          'audit': [...request.audit.map((e) => e.toMap()), auditEntry.toMap()],
        });
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Get requests for student
  Future<List<RewardRequestModel>> getStudentRequests(String studentId) async {
    try {
      final snapshot = await _firestore
          .collection(requestsCollection)
          .where('student_id', isEqualTo: studentId)
          .orderBy('timestamps.requested_at', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => RewardRequestModel.fromMap(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get requests for parent
  Future<List<RewardRequestModel>> getParentRequests(String parentId) async {
    try {
      final snapshot = await _firestore
          .collection(requestsCollection)
          .where('parent_id', isEqualTo: parentId)
          .orderBy('timestamps.requested_at', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => RewardRequestModel.fromMap(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get single request
  Future<RewardRequestModel?> getRequest(String requestId) async {
    try {
      final doc = await _firestore
          .collection(requestsCollection)
          .doc(requestId)
          .get();
      if (doc.exists) {
        return RewardRequestModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Listen to requests for parent (real-time)
  Stream<List<RewardRequestModel>> streamParentRequests(String parentId) {
    try {
      return _firestore
          .collection(requestsCollection)
          .where('parent_id', isEqualTo: parentId)
          .snapshots()
          .handleError((error) {
            return Stream.value(<QuerySnapshot<Map<String, dynamic>>>[]);
          })
          .map((snapshot) {
            try {
              final requests = snapshot.docs
                  .map((doc) {
                    try {
                      final data = doc.data();
                      return RewardRequestModel.fromMap(data);
                    } catch (e) {
                      return null;
                    }
                  })
                  .whereType<RewardRequestModel>()
                  .toList();

              // Sort by requested_at descending on the client side
              requests.sort(
                (a, b) => b.timestamps.requestedAt.compareTo(
                  a.timestamps.requestedAt,
                ),
              );

              return requests;
            } catch (e) {
              return [];
            }
          });
    } catch (e) {
      return Stream.value([]);
    }
  }

  /// Listen to requests for student (real-time)
  Stream<List<RewardRequestModel>> streamStudentRequests(String studentId) {
    try {
      // Query using student_id - this matches what createRequest() saves
      return _firestore
          .collection(requestsCollection)
          .where('student_id', isEqualTo: studentId)
          .snapshots()
          .handleError((error) {
            return Stream.value(<QuerySnapshot<Map<String, dynamic>>>[]);
          })
          .map((snapshot) {
            try {
              final requests = snapshot.docs
                  .map((doc) {
                    try {
                      final data = doc.data();
                      return RewardRequestModel.fromMap(data);
                    } catch (e) {
                      return null;
                    }
                  })
                  .whereType<RewardRequestModel>()
                  .toList();

              // Sort by requested_at descending on the client side
              requests.sort(
                (a, b) => b.timestamps.requestedAt.compareTo(
                  a.timestamps.requestedAt,
                ),
              );

              return requests;
            } catch (e) {
              return [];
            }
          });
    } catch (e) {
      return Stream.value([]);
    }
  }

  /// Get student available and locked points
  Future<Map<String, int>> getStudentPoints(String studentId) async {
    try {
      final doc = await _firestore
          .collection(studentsCollection)
          .doc(studentId)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        return {
          'available': (data['available_points'] as num?)?.toInt() ?? 0,
          'locked': (data['locked_points'] as num?)?.toInt() ?? 0,
          'deducted': (data['deducted_points'] as num?)?.toInt() ?? 0,
        };
      }
      return {'available': 0, 'locked': 0, 'deducted': 0};
    } catch (e) {
      return {'available': 0, 'locked': 0, 'deducted': 0};
    }
  }

  /// Get student document data
  Future<Map<String, dynamic>> getStudentDocument(String studentId) async {
    try {
      final doc = await _firestore
          .collection(studentsCollection)
          .doc(studentId)
          .get();
      return doc.data() ?? {};
    } catch (e) {
      return {};
    }
  }

  /// Listen to student points (real-time)
  Stream<double> streamStudentPoints(String studentId) {
    // Read from student_rewards collection — the single source of truth for
    // earned points. This is the same source the student dashboard uses.
    // We subtract locked_points and deducted_points from the students doc
    // to get the actual available balance.
    return _firestore
        .collection('student_rewards')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .asyncMap((snap) async {
          // Sum all pointsEarned from student_rewards
          double totalEarned = 0;
          for (final doc in snap.docs) {
            final data = doc.data();
            final pts = data['pointsEarned'];
            if (pts is num) totalEarned += pts.toDouble();
          }

          // Get locked and deducted from students document
          try {
            final studentDoc = await _firestore
                .collection(studentsCollection)
                .doc(studentId)
                .get();
            if (studentDoc.exists) {
              final sData = studentDoc.data() ?? {};
              final locked = (sData['locked_points'] as num?)?.toDouble() ?? 0;
              // NOTE: deducted_points is NOT subtracted here because approved
              // deductions are already reflected as negative entries in
              // student_rewards (so totalEarned already accounts for them).
              final available = totalEarned - locked;

              // Sync available_points on student doc if it differs
              final currentAvailable = (sData['available_points'] as num?)
                  ?.toDouble();
              if (currentAvailable == null ||
                  (currentAvailable - available).abs() > 0.5) {
                _firestore
                    .collection(studentsCollection)
                    .doc(studentId)
                    .update({'available_points': available.round()})
                    .catchError((_) {});
              }

              return available < 0 ? 0.0 : available;
            }
          } catch (_) {}

          return totalEarned;
        });
  }

  /// Clear cache
  void clearCache() {
    _catalogCache = null;
  }

  /// Ensure student has points structure
  Future<void> _ensureStudentPointsStructure(String studentId) async {
    try {
      final studentDoc = await _firestore
          .collection(studentsCollection)
          .doc(studentId)
          .get();

      // Compute actual earned points from student_rewards collection
      int earnedPoints = 0;
      try {
        final rewardsSnap = await _firestore
            .collection('student_rewards')
            .where('studentId', isEqualTo: studentId)
            .get();
        for (final doc in rewardsSnap.docs) {
          final pts = doc.data()['pointsEarned'];
          if (pts is num) earnedPoints += pts.toInt();
        }
      } catch (_) {}

      if (!studentDoc.exists) {
        await _firestore.collection(studentsCollection).doc(studentId).set({
          'available_points': earnedPoints,
          'locked_points': 0,
          'deducted_points': 0,
          'created_at': Timestamp.now(),
        }, SetOptions(merge: true));
        return;
      }

      final data = studentDoc.data() ?? {};
      final lockedPoints = (data['locked_points'] as num?)?.toInt() ?? 0;
      final deductedPoints = (data['deducted_points'] as num?)?.toInt() ?? 0;
      // NOTE: deducted_points is NOT subtracted because approved deductions
      // are already reflected as negative entries in student_rewards.
      final correctAvailable = earnedPoints - lockedPoints;

      // Always sync available_points from the real earned total
      final currentAvailable = (data['available_points'] as num?)?.toInt();
      if (currentAvailable == null || currentAvailable != correctAvailable) {
        await _firestore.collection(studentsCollection).doc(studentId).update({
          'available_points': correctAvailable < 0 ? 0 : correctAvailable,
          'locked_points': lockedPoints,
          'deducted_points': deductedPoints,
        });
      }
    } catch (e) {}
  }

  /// Delete reward request
  Future<void> deleteRewardRequest(String requestId) async {
    try {
      await _firestore.collection(requestsCollection).doc(requestId).delete();
    } catch (e) {
      rethrow;
    }
  }

  /// Get latest reward request for student
  Future<RewardRequestModel?> getLatestRewardRequest(String studentId) async {
    try {
      final snapshot = await _firestore
          .collection(requestsCollection)
          .where('student_id', isEqualTo: studentId)
          .orderBy('timestamps.requested_at', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return RewardRequestModel.fromMap(snapshot.docs.first.data());
    } catch (e) {
      return null;
    }
  }

  /// Check if student has pending request
  Future<bool> hasActivePendingRequest(String studentId) async {
    final latest = await getLatestRewardRequest(studentId);
    return latest != null &&
        latest.status == RewardRequestStatus.pendingParentApproval;
  }

  /// Approve reward request
  Future<void> approveRewardRequest({
    required String requestId,
    required String approverId,
    required String approvalMethod, // 'amazon' or 'manual'
    double? manualPrice,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final requestRef = _firestore
            .collection(requestsCollection)
            .doc(requestId);
        final requestSnap = await transaction.get(requestRef);

        if (!requestSnap.exists) {
          throw Exception('Request not found');
        }

        final request = RewardRequestModel.fromMap(requestSnap.data()!);

        // Check if already approved or cancelled
        if (request.status != RewardRequestStatus.pendingParentApproval) {
          throw Exception('Request is not pending');
        }

        // Check if expired
        if (DateTime.now().isAfter(request.timestamps.lockExpiresAt)) {
          throw Exception('Request has expired');
        }

        // Create audit entry
        final auditEntry = AuditEntry(
          actor: approverId,
          action: 'approved',
          timestamp: DateTime.now(),
          metadata: {
            'approval_method': approvalMethod,
            'manual_price': ?manualPrice,
          },
        );

        // Update request
        transaction.update(requestRef, {
          'status': RewardRequestStatus.approvedPurchaseInProgress.value,
          'purchase_mode': approvalMethod,
          'manual_price': ?manualPrice,
          'audit': [...request.audit.map((e) => e.toMap()), auditEntry.toMap()],
        });
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel expired reward requests
  Future<int> cancelExpiredRewardRequests() async {
    try {
      final now = DateTime.now();
      final snapshot = await _firestore
          .collection(requestsCollection)
          .where(
            'status',
            isEqualTo: RewardRequestStatus.pendingParentApproval.value,
          )
          .get();

      int cancelledCount = 0;

      for (final doc in snapshot.docs) {
        try {
          final request = RewardRequestModel.fromMap(doc.data());

          // Check if expired (21 days)
          if (now.isAfter(request.timestamps.lockExpiresAt)) {
            await _firestore.runTransaction((transaction) async {
              final requestRef = _firestore
                  .collection(requestsCollection)
                  .doc(doc.id);

              final auditEntry = AuditEntry(
                actor: 'system',
                action: 'cancelled',
                timestamp: now,
                metadata: {'reason': 'EXPIRED_21_DAYS'},
              );

              transaction.update(requestRef, {
                'status': RewardRequestStatus.expiredOrAutoResolved.value,
                'audit': [
                  ...request.audit.map((e) => e.toMap()),
                  auditEntry.toMap(),
                ],
              });

              // Release locked points back to student
              final studentRef = _firestore
                  .collection(studentsCollection)
                  .doc(request.studentId);
              final studentSnap = await transaction.get(studentRef);

              if (studentSnap.exists) {
                final studentData = studentSnap.data() ?? {};
                final availablePoints =
                    (studentData['available_points'] as num?)?.toInt() ?? 0;
                final lockedPoints =
                    (studentData['locked_points'] as num?)?.toInt() ?? 0;

                transaction.update(studentRef, {
                  'available_points':
                      availablePoints + request.pointsData.required,
                  'locked_points': lockedPoints - request.pointsData.required,
                });
              }
            });

            cancelledCount++;
          }
        } catch (e) {}
      }

      return cancelledCount;
    } catch (e) {
      return 0;
    }
  }

  /// Check and send reminder if needed
  Future<bool> checkAndSendReminder(String studentId) async {
    try {
      final latest = await getLatestRewardRequest(studentId);

      if (latest == null ||
          latest.status != RewardRequestStatus.pendingParentApproval) {
        return false;
      }

      final now = DateTime.now();
      final daysSinceRequest = now
          .difference(latest.timestamps.requestedAt)
          .inDays;

      // Check if expired
      if (now.isAfter(latest.timestamps.lockExpiresAt)) {
        return false;
      }

      // Check if reminder needed (3 days since request or last reminder)
      bool needsReminder = false;
      if (latest.lastReminderSentAt == null) {
        needsReminder = daysSinceRequest >= 3;
      } else {
        final daysSinceLastReminder = now
            .difference(latest.lastReminderSentAt!)
            .inDays;
        needsReminder = daysSinceLastReminder >= 3;
      }

      if (needsReminder) {
        // Update last reminder timestamp
        await _firestore
            .collection(requestsCollection)
            .doc(latest.requestId)
            .update({'last_reminder_sent_at': Timestamp.fromDate(now)});
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
