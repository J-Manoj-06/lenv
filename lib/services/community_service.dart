import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/community_model.dart';
import '../models/community_member_model.dart';
import '../models/community_message_model.dart';
import '../models/student_model.dart';

class CommunityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Extract grade from className (e.g., "Grade 9 - A" -> "Grade 9")
  String _extractGrade(String? className) {
    if (className == null || className.isEmpty) return '';
    // Match "Grade 10" from "Grade 10 - A" or just "Grade 10"
    final match = RegExp(r'Grade\s+\d+').firstMatch(className);
    return match?.group(0) ?? '';
  }

  /// Get communities eligible for exploration (shows all, including joined)
  Future<List<CommunityModel>> getExploreCommunities(
    StudentModel student,
  ) async {
    try {
      final userGrade = _extractGrade(student.className);

      if (userGrade.isEmpty) {
        debugPrint('⚠️ Could not extract grade from: ${student.className}');
        return [];
      }

      // Get all active, public communities
      final query = await _firestore
          .collection('communities')
          .where('isActive', isEqualTo: true)
          .where('visibility', isEqualTo: 'public')
          .where('audienceRoles', arrayContains: 'student')
          .get();

      // Filter by grade (show ALL eligible communities including joined ones)
      final communities = query.docs
          .map((doc) => CommunityModel.fromFirestore(doc))
          .where((community) {
            // Check if user's grade is in standards array (case-insensitive)
            final userGradeLower = userGrade.toLowerCase();
            final isEligible = community.standards.any(
              (standard) => standard.toLowerCase() == userGradeLower,
            );

            // Check school scope
            final schoolMatch =
                community.scope == 'global' ||
                (community.scope == 'school' &&
                    community.schoolCode == student.schoolCode);

            return isEligible && schoolMatch;
          })
          .toList();

      // Sort by member count (most popular first)
      communities.sort((a, b) => b.memberCount.compareTo(a.memberCount));

      debugPrint(
        '✅ Found ${communities.length} explore communities for $userGrade',
      );
      return communities;
    } catch (e) {
      debugPrint('❌ Error getting explore communities: $e');
      return [];
    }
  }

  /// Get communities user has joined
  Future<List<CommunityModel>> getMyComm(String userId) async {
    try {
      // Query members subcollection across all communities
      final memberQuery = await _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      if (memberQuery.docs.isEmpty) {
        return [];
      }

      // Extract community IDs
      final communityIds = memberQuery.docs
          .map((doc) => doc.reference.parent.parent!.id)
          .toSet()
          .toList();

      // Fetch community details
      final communities = <CommunityModel>[];
      for (final id in communityIds) {
        final doc = await _firestore.collection('communities').doc(id).get();
        if (doc.exists) {
          communities.add(CommunityModel.fromFirestore(doc));
        }
      }

      // Sort by last message time (most recent first)
      communities.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      debugPrint('✅ Found ${communities.length} joined communities');
      return communities;
    } catch (e) {
      debugPrint('❌ Error getting my communities: $e');
      return [];
    }
  }

  /// Get stream of joined communities (real-time updates)
  Stream<List<CommunityModel>> getMyCommunitiesStream(String userId) {
    return _firestore
        .collectionGroup('members')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isEmpty) return <CommunityModel>[];

          final communityIds = snapshot.docs
              .map((doc) => doc.reference.parent.parent!.id)
              .toSet()
              .toList();

          final communities = <CommunityModel>[];
          for (final id in communityIds) {
            final doc = await _firestore
                .collection('communities')
                .doc(id)
                .get();
            if (doc.exists) {
              communities.add(CommunityModel.fromFirestore(doc));
            }
          }

          communities.sort((a, b) {
            final aTime = a.lastMessageAt ?? a.createdAt;
            final bTime = b.lastMessageAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });

          return communities;
        });
  }

  /// Helper: Get list of community IDs user has joined
  Future<Set<String>> _getJoinedCommunityIds(String userId) async {
    try {
      final memberQuery = await _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      return memberQuery.docs
          .map((doc) => doc.reference.parent.parent!.id)
          .toSet();
    } catch (e) {
      debugPrint('❌ Error getting joined community IDs: $e');
      return {};
    }
  }

  /// Join a community
  Future<bool> joinCommunity(String communityId, StudentModel student) async {
    try {
      final batch = _firestore.batch();

      // Add user to members subcollection
      final memberRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .doc(student.uid);

      final userGrade = _extractGrade(student.className);

      batch.set(memberRef, {
        'userId': student.uid,
        'userName': student.name,
        'userEmail': student.email,
        'userRole': 'student',
        'userGrade': userGrade,
        'userSection': '', // Extract if needed
        'schoolCode': student.schoolCode ?? '',
        'avatarUrl': '',
        'joinedAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'isModerator': false,
        'lastReadAt': FieldValue.serverTimestamp(),
        'unreadCount': 0,
        'messageCount': 0,
        'muteNotifications': false,
        'favorited': false,
      });

      // Update community member count
      final communityRef = _firestore
          .collection('communities')
          .doc(communityId);
      batch.update(communityRef, {
        'memberCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      debugPrint('✅ Successfully joined community: $communityId');
      return true;
    } catch (e) {
      debugPrint('❌ Error joining community: $e');
      return false;
    }
  }

  /// Leave a community
  Future<bool> leaveCommunity(String communityId, String userId) async {
    try {
      final batch = _firestore.batch();

      // Remove user from members
      final memberRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .doc(userId);
      batch.delete(memberRef);

      // Update community member count
      final communityRef = _firestore
          .collection('communities')
          .doc(communityId);
      batch.update(communityRef, {
        'memberCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      debugPrint('✅ Successfully left community: $communityId');
      return true;
    } catch (e) {
      debugPrint('❌ Error leaving community: $e');
      return false;
    }
  }

  /// Check if user is member of community
  Future<bool> isMember(String communityId, String userId) async {
    try {
      final doc = await _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .doc(userId)
          .get();
      return doc.exists && doc.data()?['status'] == 'active';
    } catch (e) {
      return false;
    }
  }

  /// Search communities by name or description
  Future<List<CommunityModel>> searchCommunities(
    String query,
    StudentModel student,
  ) async {
    try {
      final allCommunities = await getExploreCommunities(student);

      if (query.isEmpty) return allCommunities;

      final lowercaseQuery = query.toLowerCase();
      return allCommunities.where((community) {
        return community.name.toLowerCase().contains(lowercaseQuery) ||
            community.description.toLowerCase().contains(lowercaseQuery) ||
            community.tags.any(
              (tag) => tag.toLowerCase().contains(lowercaseQuery),
            );
      }).toList();
    } catch (e) {
      debugPrint('❌ Error searching communities: $e');
      return [];
    }
  }

  /// Filter communities by category
  Future<List<CommunityModel>> filterByCategory(
    String category,
    StudentModel student,
  ) async {
    try {
      final allCommunities = await getExploreCommunities(student);

      if (category.isEmpty || category.toLowerCase() == 'all') {
        return allCommunities;
      }

      return allCommunities
          .where(
            (community) =>
                community.category.toLowerCase() == category.toLowerCase(),
          )
          .toList();
    } catch (e) {
      debugPrint('❌ Error filtering by category: $e');
      return [];
    }
  }

  /// Get community details
  Future<CommunityModel?> getCommunity(String communityId) async {
    try {
      final doc = await _firestore
          .collection('communities')
          .doc(communityId)
          .get();
      if (doc.exists) {
        return CommunityModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting community: $e');
      return null;
    }
  }

  /// Get community members
  Future<List<CommunityMemberModel>> getMembers(String communityId) async {
    try {
      final snapshot = await _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .orderBy('joinedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => CommunityMemberModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting members: $e');
      return [];
    }
  }

  // ==================== MESSAGE OPERATIONS ====================

  /// Send a message to community
  Future<bool> sendMessage({
    required String communityId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String content,
    String? replyToId,
  }) async {
    try {
      final batch = _firestore.batch();

      // Add message to messages subcollection
      final messageRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .doc();

      final messageData = {
        'id': messageRef.id,
        'senderId': senderId,
        'senderName': senderName,
        'senderRole': senderRole,
        'content': content,
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
        'editedAt': null,
        'deletedAt': null,
        'isEdited': false,
        'isDeleted': false,
        'reactions': {},
        'replyToId': replyToId,
        'attachments': [],
        'mentions': [],
        'isPinned': false,
      };

      batch.set(messageRef, messageData);

      // Update community with last message info
      final communityRef = _firestore
          .collection('communities')
          .doc(communityId);
      batch.update(communityRef, {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': content.length > 100
            ? '${content.substring(0, 100)}...'
            : content,
        'lastMessageSender': senderName,
        'messageCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      debugPrint('✅ Message sent to community: $communityId');
      return true;
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      return false;
    }
  }

  /// Get messages stream for real-time updates
  Stream<List<CommunityMessageModel>> getMessagesStream(String communityId) {
    return _firestore
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => CommunityMessageModel.fromFirestore(doc))
              .toList();
        });
  }

  /// Get messages (paginated)
  Future<List<CommunityMessageModel>> getMessages({
    required String communityId,
    int limit = 50,
    DocumentSnapshot? lastDoc,
  }) async {
    try {
      var query = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => CommunityMessageModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting messages: $e');
      return [];
    }
  }

  /// Add reaction to message
  Future<bool> addReaction({
    required String communityId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    try {
      final messageRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .doc(messageId);

      // Get current reactions
      final doc = await messageRef.get();
      final reactions = Map<String, dynamic>.from(
        doc.data()?['reactions'] ?? {},
      );

      // Initialize emoji array if not exists
      if (!reactions.containsKey(emoji)) {
        reactions[emoji] = [];
      }

      // Toggle reaction (add if not exists, remove if exists)
      final userReactions = List<String>.from(reactions[emoji]);
      if (userReactions.contains(userId)) {
        userReactions.remove(userId);
        if (userReactions.isEmpty) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = userReactions;
        }
      } else {
        userReactions.add(userId);
        reactions[emoji] = userReactions;
      }

      await messageRef.update({'reactions': reactions});
      debugPrint('✅ Reaction updated for message: $messageId');
      return true;
    } catch (e) {
      debugPrint('❌ Error adding reaction: $e');
      return false;
    }
  }

  /// Mark messages as read
  Future<bool> markAsRead({
    required String communityId,
    required String userId,
  }) async {
    try {
      final memberRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .doc(userId);

      await memberRef.update({
        'lastReadAt': FieldValue.serverTimestamp(),
        'unreadCount': 0,
      });

      debugPrint('✅ Messages marked as read for user: $userId');
      return true;
    } catch (e) {
      debugPrint('❌ Error marking messages as read: $e');
      return false;
    }
  }

  /// Delete message (soft delete)
  Future<bool> deleteMessage({
    required String communityId,
    required String messageId,
    required String userId,
  }) async {
    try {
      final messageRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .doc(messageId);

      await messageRef.update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'content': 'This message was deleted',
      });

      debugPrint('✅ Message deleted: $messageId');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting message: $e');
      return false;
    }
  }

  /// Edit message
  Future<bool> editMessage({
    required String communityId,
    required String messageId,
    required String newContent,
  }) async {
    try {
      final messageRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .doc(messageId);

      await messageRef.update({
        'content': newContent,
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Message edited: $messageId');
      return true;
    } catch (e) {
      debugPrint('❌ Error editing message: $e');
      return false;
    }
  }
}
