import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/community_model.dart';
import '../models/community_member_model.dart';
import '../models/community_message_model.dart';
import '../models/student_model.dart';
import '../models/media_metadata.dart';

class MessageSearchPage {
  final List<CommunityMessageModel> messages;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;

  const MessageSearchPage({
    required this.messages,
    required this.lastDoc,
    required this.hasMore,
  });
}

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

      // Get all active, public communities with server read
      final query = await _firestore
          .collection('communities')
          .where('isActive', isEqualTo: true)
          .where('visibility', isEqualTo: 'public')
          .where('audienceRoles', arrayContains: 'student')
          .get(const GetOptions(source: Source.server));

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

  /// Get communities eligible for teachers (shows all, including joined)
  Future<List<CommunityModel>> getExploreCommunitiesForTeacher({
    required String schoolCode,
  }) async {
    try {
      // Get all active, public communities for teachers with server read
      final query = await _firestore
          .collection('communities')
          .where('isActive', isEqualTo: true)
          .where('visibility', isEqualTo: 'public')
          .where('audienceRoles', arrayContains: 'teacher')
          .get(const GetOptions(source: Source.server));

      // Filter by school scope
      final communities = query.docs
          .map((doc) => CommunityModel.fromFirestore(doc))
          .where((community) {
            // Check school scope
            final schoolMatch =
                community.scope == 'global' ||
                (community.scope == 'school' &&
                    community.schoolCode == schoolCode);

            return schoolMatch;
          })
          .toList();

      // Sort by member count (most popular first)
      communities.sort((a, b) => b.memberCount.compareTo(a.memberCount));

      debugPrint(
        '✅ Found ${communities.length} explore communities for teacher',
      );
      return communities;
    } catch (e) {
      debugPrint('❌ Error getting teacher explore communities: $e');
      return [];
    }
  }

  /// Get communities user has joined
  /// ✅ OPTIMIZED: Uses user_communities collection (1 read instead of 3000+)
  Future<List<CommunityModel>> getMyComm(String userId) async {
    try {
      // ✅ OPTIMIZATION: Read from user_communities index with server read
      final indexDoc = await _firestore
          .collection('user_communities')
          .doc(userId)
          .get(const GetOptions(source: Source.server));

      if (!indexDoc.exists || indexDoc.data() == null) {
        debugPrint(
          '⚠️ user_communities document not found, falling back to collectionGroup',
        );
        return _getMyCommFallback(userId);
      }

      final indexData = indexDoc.data()!;
      final fromIndex =
          (indexData['communityIds'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          [];

      // 🔎 Self-healing: also scan membership to catch any missing IDs
      // This is a single collectionGroup query and only runs once per load.
      final memberQuery = await _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      final fromMembership = memberQuery.docs
          .map((doc) => doc.reference.parent.parent!.id)
          .toSet()
          .toList();

      // Union of IDs from index and membership (deduped)
      final communityIds = <String>{...fromIndex, ...fromMembership}.toList();

      // If membership discovered extra IDs, update the index asynchronously
      final missingInIndex = fromMembership
          .where((id) => !fromIndex.contains(id))
          .toList();
      if (missingInIndex.isNotEmpty) {
        try {
          await _firestore.collection('user_communities').doc(userId).set({
            'communityIds': FieldValue.arrayUnion(missingInIndex),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint(
            '🩺 Self-healed user_communities by adding ${missingInIndex.length} missing id(s)',
          );
        } catch (e) {
          debugPrint('⚠️ Failed to self-heal user_communities: $e');
        }
      }

      if (communityIds.isEmpty) {
        return [];
      }

      // Fetch community details (N reads where N = number of joined communities)
      final communities = <CommunityModel>[];
      for (final id in communityIds) {
        // Force server read to avoid stale cache
        final doc = await _firestore
            .collection('communities')
            .doc(id)
            .get(const GetOptions(source: Source.server));
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

      debugPrint('✅ Found ${communities.length} joined communities via index');
      return communities;
    } catch (e) {
      debugPrint('❌ Error getting my communities: $e');
      return [];
    }
  }

  /// Fallback method using collectionGroup (legacy)
  Future<List<CommunityModel>> _getMyCommFallback(String userId) async {
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

      debugPrint('✅ Found ${communities.length} joined communities (fallback)');
      return communities;
    } catch (e) {
      debugPrint('❌ Error in fallback: $e');
      return [];
    }
  }

  /// Get stream of joined communities (real-time updates)
  /// ✅ OPTIMIZED: Uses user_communities index
  Stream<List<CommunityModel>> getMyCommunitiesStream(String userId) {
    return _firestore
        .collection('user_communities')
        .doc(userId)
        .snapshots()
        .asyncMap((indexDoc) async {
          if (!indexDoc.exists || indexDoc.data() == null) {
            debugPrint('⚠️ user_communities not found, using fallback');
            return _getMyCommStreamFallback(userId);
          }

          final indexData = indexDoc.data()!;
          final communityIds =
              (indexData['communityIds'] as List<dynamic>?)
                  ?.whereType<String>()
                  .toList() ??
              [];

          if (communityIds.isEmpty) return <CommunityModel>[];

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

  /// Fallback stream using collectionGroup (legacy)
  Future<List<CommunityModel>> _getMyCommStreamFallback(String userId) async {
    try {
      final memberQuery = await _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      if (memberQuery.docs.isEmpty) return <CommunityModel>[];

      final communityIds = memberQuery.docs
          .map((doc) => doc.reference.parent.parent!.id)
          .toSet()
          .toList();

      final communities = <CommunityModel>[];
      for (final id in communityIds) {
        final doc = await _firestore.collection('communities').doc(id).get();
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
    } catch (e) {
      debugPrint('❌ Error in stream fallback: $e');
      return [];
    }
  }

  /// Join a community (for students)
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

      // ✅ CRITICAL: Update user_communities index for immediate display
      final userCommRef = _firestore
          .collection('user_communities')
          .doc(student.uid);

      batch.set(userCommRef, {
        'userId': student.uid,
        'communityIds': FieldValue.arrayUnion([communityId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      debugPrint('✅ Successfully joined community: $communityId');
      debugPrint('✅ Updated user_communities index for: ${student.uid}');
      return true;
    } catch (e) {
      debugPrint('❌ Error joining community: $e');
      return false;
    }
  }

  /// Join a community (for teachers)
  Future<bool> joinCommunityAsTeacher({
    required String communityId,
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required String schoolCode,
  }) async {
    try {
      final batch = _firestore.batch();

      // Add teacher to members subcollection
      final memberRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .doc(teacherId);

      batch.set(memberRef, {
        'userId': teacherId,
        'userName': teacherName,
        'userEmail': teacherEmail,
        'userRole': 'teacher',
        'userGrade': '', // Not applicable for teachers
        'userSection': '',
        'schoolCode': schoolCode,
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

      // ✅ CRITICAL: Update user_communities index for immediate display
      final userCommRef = _firestore
          .collection('user_communities')
          .doc(teacherId);

      batch.set(userCommRef, {
        'userId': teacherId,
        'communityIds': FieldValue.arrayUnion([communityId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      debugPrint('✅ Teacher successfully joined community: $communityId');
      debugPrint('✅ Updated user_communities index for teacher: $teacherId');
      return true;
    } catch (e) {
      debugPrint('❌ Error teacher joining community: $e');
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
  /// ✅ OPTIMIZATION: Updates user_communities index for all members
  Future<bool> sendMessage({
    required String communityId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String content,
    String? replyToId,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
    String? mediaType, // 'image', 'pdf', 'audio'
    MediaMetadata? mediaMetadata, // WhatsApp-style media metadata
  }) async {
    try {
      final batch = _firestore.batch();

      // Add message to messages subcollection
      final messageRef = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .doc();

      // Determine message type based on media
      String messageType = 'text';
      if (imageUrl != null && imageUrl.isNotEmpty) {
        messageType = 'image';
      } else if (fileUrl != null && fileUrl.isNotEmpty) {
        messageType = mediaType ?? 'file'; // Use specific type if provided
      }

      final messageData = {
        'id': messageRef.id,
        'senderId': senderId,
        'senderName': senderName,
        'senderRole': senderRole,
        'content': content,
        'type': messageType,
        'imageUrl': imageUrl ?? '',
        'fileUrl': fileUrl ?? '',
        'fileName': fileName ?? '',
        'mediaMetadata': mediaMetadata?.toFirestore(),
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

      // Create preview text for different message types
      String preview = content;
      if (messageType == 'image') {
        preview = '📷 Image';
      } else if (messageType == 'pdf' || messageType == 'file') {
        preview = '📄 ${fileName ?? 'File'}';
      } else if (messageType == 'audio') {
        preview = '🎵 Audio';
      }

      // Update community with last message info
      final communityRef = _firestore
          .collection('communities')
          .doc(communityId);
      batch.update(communityRef, {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': preview.length > 100
            ? '${preview.substring(0, 100)}...'
            : preview,
        'lastMessageSender': senderName,
        'messageCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      debugPrint('✅ Message sent to community: $communityId');

      // ✅ OPTIMIZATION: Update user_communities for all members (async, non-blocking)
      _updateUserCommunitiesAfterMessage(
        communityId,
        senderId,
        senderName,
        preview,
      );

      return true;
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      return false;
    }
  }

  /// ✅ OPTIMIZATION: Update user_communities for all community members
  /// Increments unread count for everyone except sender
  Future<void> _updateUserCommunitiesAfterMessage(
    String communityId,
    String senderId,
    String senderName,
    String content,
  ) async {
    try {
      // Get all active members of the community
      final membersSnapshot = await _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .get();

      final batch = _firestore.batch();
      int batchCount = 0;

      for (final memberDoc in membersSnapshot.docs) {
        final memberData = memberDoc.data();
        final userId = memberData['userId'] as String?;

        if (userId == null || userId == senderId) continue; // Skip sender

        // Update user_communities for this member
        final userCommRef = _firestore
            .collection('user_communities')
            .doc(userId);

        batch.set(userCommRef, {
          'communities': {
            communityId: {
              'unreadCount': FieldValue.increment(1),
              'lastMessage': content.length > 50
                  ? '${content.substring(0, 50)}...'
                  : content,
              'lastMessageAt': FieldValue.serverTimestamp(),
              'lastMessageBy': senderName,
            },
          },
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        batchCount++;

        // Firestore batch limit is 500 operations
        if (batchCount >= 450) {
          await batch.commit();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      debugPrint(
        '✅ Updated user_communities for ${membersSnapshot.docs.length} members',
      );
    } catch (e) {
      // Don't throw - message was already sent successfully
      debugPrint('⚠️ Failed to update user_communities: $e');
    }
  }

  /// Get messages stream for real-time updates
  /// ✅ OPTIMIZED: Default limit of 50 messages
  Stream<List<CommunityMessageModel>> getMessagesStream(
    String communityId, {
    int limit = 50,
  }) {
    return _firestore
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .where((doc) {
                // Filter out documents with invalid timestamp data
                final data = doc.data();
                return data['createdAt'] != null;
              })
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

  /// Search messages with lightweight client-side filtering over paginated fetches
  Future<MessageSearchPage> searchMessages({
    required String communityId,
    required String query,
    int limit = 25,
    DocumentSnapshot? lastDoc,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return MessageSearchPage(
        messages: const [],
        lastDoc: lastDoc,
        hasMore: false,
      );
    }

    try {
      var ref = _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (lastDoc != null) {
        ref = ref.startAfterDocument(lastDoc);
      }

      final snap = await ref.get();
      final lowerQuery = trimmed.toLowerCase();

      bool matches(CommunityMessageModel m) {
        final content = m.content.toLowerCase();
        final sender = m.senderName.toLowerCase();
        final type = m.type.toLowerCase();
        final fileName = m.fileName.toLowerCase();
        final metaName = m.mediaMetadata?.originalFileName?.toLowerCase() ?? '';
        final mime = m.mediaMetadata?.mimeType?.toLowerCase() ?? '';
        final mediaPath = m.mediaMetadata?.r2Key.toLowerCase() ?? '';

        return content.contains(lowerQuery) ||
            sender.contains(lowerQuery) ||
            type.contains(lowerQuery) ||
            fileName.contains(lowerQuery) ||
            metaName.contains(lowerQuery) ||
            mime.contains(lowerQuery) ||
            mediaPath.contains(lowerQuery);
      }

      final messages = snap.docs
          .map((doc) => CommunityMessageModel.fromFirestore(doc))
          .where(matches)
          .toList();

      final hasMore = snap.docs.length == limit;
      final nextCursor = snap.docs.isNotEmpty ? snap.docs.last : lastDoc;

      return MessageSearchPage(
        messages: messages,
        lastDoc: nextCursor,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ Error searching messages: $e');
      return MessageSearchPage(
        messages: const [],
        lastDoc: lastDoc,
        hasMore: false,
      );
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
  /// Only the original sender can delete for everyone.
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

      final snapshot = await messageRef.get();
      if (!snapshot.exists) {
        debugPrint('❌ Message not found: $messageId');
        return false;
      }

      final data = snapshot.data();
      final senderId = data?['senderId'] as String?;
      if (senderId == null || senderId != userId) {
        debugPrint('🚫 Unauthorized delete attempt by $userId for $messageId');
        return false;
      }

      await messageRef.update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'content': 'This message was deleted',
        'imageUrl': '',
        'fileUrl': '',
        'fileName': '',
        'mediaMetadata': null,
        'reactions': {},
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
