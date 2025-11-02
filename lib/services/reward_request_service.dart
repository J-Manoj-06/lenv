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
      final docRef = await _firestore.collection(_collection).add({
        'studentId': studentId,
        'studentName': studentName,
        'productId': productId,
        'productName': productName,
        'amazonLink': amazonLink,
        'price': price,
        'pointsRequired': pointsRequired,
        'status': 'pending',
        'requestedOn': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create reward request: $e');
    }
  }

  // Get reward requests for a specific student
  Stream<List<RewardRequestModel>> getStudentRewardRequests(String studentId) {
    // Avoid requiring a composite index by not ordering on the server;
    // sort by requestedOn on the client side instead.
    return _firestore
        .collection(_collection)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => RewardRequestModel.fromJson(doc.data(), id: doc.id))
              .toList();
          // Sort descending by requestedOn locally
          list.sort((a, b) => b.requestedOn.compareTo(a.requestedOn));
          return list;
        });
  }

  // Get all pending reward requests (for parents/teachers)
  Stream<List<RewardRequestModel>> getPendingRewardRequests() {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: 'pending')
        .orderBy('requestedOn', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RewardRequestModel.fromJson(doc.data(), id: doc.id))
              .toList(),
        );
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
