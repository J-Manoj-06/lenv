import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reward_request_model.dart';

class RewardRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'reward_requests';

  // Create a new reward request
  Future<String> createRewardRequest({
    required String studentId,
    required String studentName,
    required String productId,
    required String productName,
    required String amazonLink,
    required double price,
    required int pointsRequired,
  }) async {
    try {
      final docData = {
        'student_id': studentId,
        'studentName': studentName,
        'productId': productId,
        'productName': productName,
        'amazonLink': amazonLink,
        'price': price,
        'pointsRequired': pointsRequired,
        'status': 'pending',
        'timestamps': {'requested_at': FieldValue.serverTimestamp()},
      };

      final docRef = await _firestore.collection(_collection).add(docData);

      // Verify it was saved
      final savedDoc = await docRef.get();

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create reward request: $e');
    }
  }

  // Get reward requests for a specific student
  Stream<List<RewardRequestModel>> getStudentRewardRequests(String studentId) {
    // Query using student_id (new field name) - new requests use this field
    return _firestore
        .collection(_collection)
        .where('student_id', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((doc) {
            return RewardRequestModel.fromJson(doc.data(), id: doc.id);
          }).toList();
          // Sort descending by requestedOn locally
          list.sort((a, b) => b.requestedOn.compareTo(a.requestedOn));
          return list;
        });
  }

  // Get all pending reward requests (for parents/teachers)
  // Uses 'pendingParentApproval' status — the value written by RewardsRepository.createRequest()
  // Sorting is done client-side to avoid requiring a composite index
  Stream<List<RewardRequestModel>> getPendingRewardRequests() {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'pendingParentApproval')
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => RewardRequestModel.fromJson(doc.data(), id: doc.id))
              .toList();
          // Sort descending by requestedOn client-side
          list.sort((a, b) => b.requestedOn.compareTo(a.requestedOn));
          return list;
        });
  }

  // Update reward request status
  Future<void> updateRewardRequestStatus({
    required String requestId,
    required String status,
    String? parentId,
  }) async {
    try {
      final updateData = <String, dynamic>{'status': status};

      if (parentId != null) {
        updateData['parentId'] = parentId;
      }

      if (status == 'approved' || status == 'rejected') {
        updateData['approvedOn'] = FieldValue.serverTimestamp();
      }

      await _firestore
          .collection(_collection)
          .doc(requestId)
          .update(updateData);
    } catch (e) {
      throw Exception('Failed to update reward request: $e');
    }
  }

  // Delete a reward request
  Future<void> deleteRewardRequest(String requestId) async {
    try {
      await _firestore.collection(_collection).doc(requestId).delete();
    } catch (e) {
      throw Exception('Failed to delete reward request: $e');
    }
  }

  // Get reward request by ID
  Future<RewardRequestModel?> getRewardRequestById(String requestId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(requestId).get();
      if (doc.exists) {
        return RewardRequestModel.fromJson(doc.data()!, id: doc.id);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get reward request: $e');
    }
  }
}
