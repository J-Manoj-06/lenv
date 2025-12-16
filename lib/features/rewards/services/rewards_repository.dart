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
    print('🎁 getCatalog: Starting (forceRefresh=$forceRefresh)');
    try {
      // Return cache if available and not forcing refresh
      if (_catalogCache != null && !forceRefresh) {
        print('✅ getCatalog: Returning cached catalog (${_catalogCache!.length} items)');
        return _catalogCache!;
      }

      print('🔥 getCatalog: Fetching from Firestore collection: $catalogCollection');
      // Try to fetch from Firestore
      final snapshot = await _firestore
          .collection(catalogCollection)
          .get()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw Exception('Firestore timeout'),
          );

      print('✅ getCatalog: Firestore returned ${snapshot.docs.length} documents');
      if (snapshot.docs.isNotEmpty) {
        _catalogCache = snapshot.docs
            .map((doc) => ProductModel.fromMap(doc.data()))
            .toList();
        print('✅ getCatalog: Mapped to ${_catalogCache!.length} products');
        return _catalogCache!;
      }

      print('⚠️ getCatalog: Firestore is empty, loading dummy catalog');
      // Fallback to dummy JSON if Firestore is empty
      return _loadDummyCatalog();
    } catch (e) {
      print('❌ getCatalog: Error loading catalog from Firestore: $e');
      // Fallback to dummy JSON on error
      return _loadDummyCatalog();
    }
  }

  /// Load dummy catalog from assets
  Future<List<ProductModel>> _loadDummyCatalog() async {
    print('📄 _loadDummyCatalog: Starting...');
    try {
      final jsonString = await rootBundle.loadString(
        'assets/dummy_rewards.json',
      );
      print('✅ _loadDummyCatalog: Loaded JSON from assets');
      final jsonList = jsonDecode(jsonString) as List;
      final products = jsonList
          .map((item) => ProductModel.fromMap(item as Map<String, dynamic>))
          .toList();
      print('✅ _loadDummyCatalog: Parsed ${products.length} products from dummy data');
      return products;
    } catch (e) {
      print('❌ _loadDummyCatalog: Error loading dummy catalog: $e');
      return [];
    }
  }

  /// Search products by query
  Future<List<ProductModel>> searchProducts(String query) async {
    print('🔍 searchProducts: Searching for "$query"');
    final catalog = await getCatalog();
    if (query.isEmpty) {
      print('🔍 searchProducts: Empty query, returning all ${catalog.length} products');
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
    print('🔍 searchProducts: Found ${results.length} results for "$query"');
    return results;
  }

  /// Get product by ID
  Future<ProductModel?> getProductById(String productId) async {
    print('🔎 getProductById: Fetching product: $productId');
    try {
      final doc = await _firestore
          .collection(catalogCollection)
          .doc(productId)
          .get();
      if (doc.exists) {
        print('✅ getProductById: Found product: $productId');
        return ProductModel.fromMap(doc.data()!);
      }
      print('⚠️ getProductById: Product not found: $productId');
      return null;
    } catch (e) {
      print('❌ getProductById: Error getting product: $e');
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

      // Run transaction to ensure atomicity
      await _firestore.runTransaction((transaction) async {
        // Get current student data
        final studentSnap = await transaction.get(studentRef);
        final studentData = studentSnap.data() ?? {};
        final availablePoints =
            (studentData['available_points'] as num?)?.toInt() ?? 0;
        final lockedPoints =
            (studentData['locked_points'] as num?)?.toInt() ?? 0;

        // Check if student has enough points
        if (availablePoints < pointsRequired) {
          throw Exception('Insufficient points');
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

        // Update student points
        transaction.update(studentRef, {
          'available_points': availablePoints - pointsRequired,
          'locked_points': lockedPoints + pointsRequired,
          'last_reward_request': Timestamp.now(),
        });

        // Create request document
        transaction.set(requestRef, request.toMap());
      });

      // Fetch and return created request
      final doc = await requestRef.get();
      return RewardRequestModel.fromMap(doc.data()!);
    } catch (e) {
      print('❌ Error creating request: $e');
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
      print('❌ Error updating request status: $e');
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
      print('❌ Error getting student requests: $e');
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
      print('❌ Error getting parent requests: $e');
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
      print('❌ Error getting request: $e');
      return null;
    }
  }

  /// Listen to requests for parent (real-time)
  Stream<List<RewardRequestModel>> streamParentRequests(String parentId) {
    try {
      return _firestore
          .collection(requestsCollection)
          .where('parent_id', isEqualTo: parentId)
          .orderBy('timestamps.requested_at', descending: true)
          .snapshots()
          .handleError(
            (error) {
              print('❌ Error streaming parent requests: $error');
              return Stream.value(<QuerySnapshot<Map<String, dynamic>>>[]);
            },
          )
          .map(
            (snapshot) {
              try {
                return snapshot.docs
                    .map((doc) => RewardRequestModel.fromMap(doc.data()))
                    .toList();
              } catch (e) {
                print('❌ Error parsing parent requests: $e');
                return [];
              }
            },
          );
    } catch (e) {
      print('❌ Error creating parent stream: $e');
      return Stream.value([]);
    }
  }

  /// Listen to requests for student (real-time)
  Stream<List<RewardRequestModel>> streamStudentRequests(String studentId) {
    try {
      return _firestore
          .collection(requestsCollection)
          .where('student_id', isEqualTo: studentId)
          .orderBy('timestamps.requested_at', descending: true)
          .snapshots()
          .handleError(
            (error) {
              print('❌ Error streaming student requests: $error');
              return Stream.value(<QuerySnapshot<Map<String, dynamic>>>[]);
            },
          )
          .map(
            (snapshot) {
              try {
                return snapshot.docs
                    .map((doc) => RewardRequestModel.fromMap(doc.data()))
                    .toList();
              } catch (e) {
                print('❌ Error parsing reward requests: $e');
                return [];
              }
            },
          );
    } catch (e) {
      print('❌ Error creating request stream: $e');
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
      print('❌ Error getting student points: $e');
      return {'available': 0, 'locked': 0, 'deducted': 0};
    }
  }

  /// Listen to student points (real-time)
  Stream<double> streamStudentPoints(String studentId) {
    print('💰 streamStudentPoints: Creating stream for student: $studentId');
    // Primary live source: student_rewards collection (sums pointsEarned)
    // Fallback: students doc available_points / legacy fields
    return _firestore
        .collection('student_rewards')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .asyncMap((snap) async {
          print('💰 streamStudentPoints: Snapshot received for $studentId with ${snap.docs.length} documents');
          if (snap.docs.isNotEmpty) {
            double total = 0;
            for (final doc in snap.docs) {
              final data = doc.data();
              final pts = data['pointsEarned'];
              if (pts is num) total += pts.toDouble();
            }
            print('✅ streamStudentPoints: Total points for $studentId: $total');
            return total;
          }

          print('⚠️ streamStudentPoints: No rewards found, checking students collection');
          // Fallback to students document if no rewards entries
          final studentDoc = await _firestore
              .collection(studentsCollection)
              .doc(studentId)
              .get();
          final data = studentDoc.data() ?? {};
          final available = (data['available_points'] as num?)?.toDouble();
          final legacyEarned = (data['pointsEarned'] as num?)?.toDouble();
          final legacyPoints = (data['points'] as num?)?.toDouble();
          final result = available ?? legacyEarned ?? legacyPoints ?? 0.0;
          print('✅ streamStudentPoints: Fallback points for $studentId: $result');
          return result;
        });
  }

  /// Clear cache
  void clearCache() {
    _catalogCache = null;
  }
}
