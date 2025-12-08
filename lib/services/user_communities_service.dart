import 'package:cloud_firestore/cloud_firestore.dart';

/// Optimized service for user_communities collection
/// Replaces expensive collectionGroup('members') queries
class UserCommunitiesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ Cache with 5-minute TTL
  Map<String, dynamic>? _cachedUserCommunities;
  DateTime? _cacheTimestamp;
  String? _cachedUserId;

  /// Check if cache is valid (5 minutes)
  bool _isCacheValid(String userId) {
    if (_cachedUserId != userId) return false;
    if (_cacheTimestamp == null || _cachedUserCommunities == null) return false;
    return DateTime.now().difference(_cacheTimestamp!).inMinutes < 5;
  }

  /// Clear cache (call after joining/leaving community or on logout)
  void clearCache() {
    _cachedUserCommunities = null;
    _cacheTimestamp = null;
    _cachedUserId = null;
  }

  /// Get user's communities from user_communities collection
  /// ✅ OPTIMIZATION: 1 read instead of collectionGroup scan (3000+ reads)
  Future<Map<String, dynamic>?> getUserCommunities(String userId) async {
    try {
      // Return cached data if valid
      if (_isCacheValid(userId)) {
        print('📦 Using cached user_communities data');
        return _cachedUserCommunities;
      }

      print('🔍 Fetching user_communities for: $userId');

      final doc = await _firestore
          .collection('user_communities')
          .doc(userId)
          .get();

      if (!doc.exists || doc.data() == null) {
        print('⚠️ user_communities document not found for user: $userId');
        return null;
      }

      final data = doc.data()!;

      // Cache the result
      _cachedUserCommunities = data;
      _cacheTimestamp = DateTime.now();
      _cachedUserId = userId;

      print('✅ Fetched ${data['totalCommunities'] ?? 0} communities');
      return data;
    } catch (e) {
      print('❌ Error fetching user_communities: $e');
      return null;
    }
  }

  /// Get user's communities with real-time updates
  /// ✅ OPTIMIZATION: 1 snapshot listener instead of collectionGroup
  Stream<Map<String, dynamic>?> getUserCommunitiesStream(String userId) {
    return _firestore
        .collection('user_communities')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            return null;
          }

          // Update cache
          _cachedUserCommunities = snapshot.data();
          _cacheTimestamp = DateTime.now();
          _cachedUserId = userId;

          return snapshot.data();
        });
  }

  /// Parse communities list from user_communities document
  List<Map<String, dynamic>> parseCommunities(Map<String, dynamic>? data) {
    if (data == null) return [];

    final communities = data['communities'] as List<dynamic>?;
    if (communities == null) return [];

    return communities.whereType<Map<String, dynamic>>().toList();
  }

  /// Get community IDs list
  List<String> getCommunityIds(Map<String, dynamic>? data) {
    if (data == null) return [];

    final communityIds = data['communityIds'] as List<dynamic>?;
    if (communityIds == null) return [];

    return communityIds.whereType<String>().toList();
  }

  /// Check if user is member of a community
  /// ✅ OPTIMIZATION: Check cached data, no query
  bool isMemberOf(String communityId) {
    if (_cachedUserCommunities == null) return false;

    final communityIds =
        _cachedUserCommunities!['communityIds'] as List<dynamic>?;
    if (communityIds == null) return false;

    return communityIds.contains(communityId);
  }

  /// Get total unread count across all communities
  /// ✅ OPTIMIZATION: Read from cached totalUnread field
  int getTotalUnreadCount() {
    if (_cachedUserCommunities == null) return 0;
    return (_cachedUserCommunities!['totalUnread'] as num?)?.toInt() ?? 0;
  }

  /// Get unread count for specific community
  /// ✅ OPTIMIZATION: Read from cached communities array
  int getUnreadCountForCommunity(String communityId) {
    if (_cachedUserCommunities == null) return 0;

    final communities =
        _cachedUserCommunities!['communities'] as List<dynamic>?;
    if (communities == null) return 0;

    for (final community in communities) {
      if (community is Map<String, dynamic> &&
          community['communityId'] == communityId) {
        return (community['unreadCount'] as num?)?.toInt() ?? 0;
      }
    }

    return 0;
  }

  /// Mark community as read (set unread count to 0)
  /// Called when user opens a community chat
  Future<void> markCommunityAsRead(String userId, String communityId) async {
    try {
      final doc = await _firestore
          .collection('user_communities')
          .doc(userId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final communities = List<Map<String, dynamic>>.from(
        (data['communities'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>() ??
            [],
      );

      // Find and update the community's unread count
      int oldUnreadCount = 0;
      for (var i = 0; i < communities.length; i++) {
        if (communities[i]['communityId'] == communityId) {
          oldUnreadCount =
              (communities[i]['unreadCount'] as num?)?.toInt() ?? 0;
          communities[i]['unreadCount'] = 0;
          break;
        }
      }

      // Update total unread count
      final currentTotalUnread = (data['totalUnread'] as num?)?.toInt() ?? 0;
      final newTotalUnread = (currentTotalUnread - oldUnreadCount)
          .clamp(0, double.infinity)
          .toInt();

      await _firestore.collection('user_communities').doc(userId).update({
        'communities': communities,
        'totalUnread': newTotalUnread,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update local cache
      if (_cachedUserId == userId && _cachedUserCommunities != null) {
        _cachedUserCommunities!['communities'] = communities;
        _cachedUserCommunities!['totalUnread'] = newTotalUnread;
      }

      print('✅ Marked community as read: $communityId');
    } catch (e) {
      print('❌ Error marking community as read: $e');
    }
  }

  /// Increment unread count for a community
  /// Called when a new message is received (from Cloud Function ideally)
  Future<void> incrementUnreadCount(String userId, String communityId) async {
    try {
      final doc = await _firestore
          .collection('user_communities')
          .doc(userId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final communities = List<Map<String, dynamic>>.from(
        (data['communities'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>() ??
            [],
      );

      // Find and increment the community's unread count
      bool found = false;
      for (var i = 0; i < communities.length; i++) {
        if (communities[i]['communityId'] == communityId) {
          final currentCount =
              (communities[i]['unreadCount'] as num?)?.toInt() ?? 0;
          communities[i]['unreadCount'] = currentCount + 1;
          found = true;
          break;
        }
      }

      if (!found) return;

      // Increment total unread count
      await _firestore.collection('user_communities').doc(userId).update({
        'communities': communities,
        'totalUnread': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Invalidate cache to force refresh
      if (_cachedUserId == userId) {
        clearCache();
      }

      print('✅ Incremented unread count for community: $communityId');
    } catch (e) {
      print('❌ Error incrementing unread count: $e');
    }
  }

  /// Update last message info for a community
  /// Called when a new message is sent
  Future<void> updateLastMessage({
    required String userId,
    required String communityId,
    required DateTime lastMessageAt,
  }) async {
    try {
      final doc = await _firestore
          .collection('user_communities')
          .doc(userId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final communities = List<Map<String, dynamic>>.from(
        (data['communities'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>() ??
            [],
      );

      // Find and update the community's last message time
      for (var i = 0; i < communities.length; i++) {
        if (communities[i]['communityId'] == communityId) {
          communities[i]['lastMessageAt'] = Timestamp.fromDate(lastMessageAt);
          break;
        }
      }

      await _firestore.collection('user_communities').doc(userId).update({
        'communities': communities,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update local cache
      if (_cachedUserId == userId && _cachedUserCommunities != null) {
        _cachedUserCommunities!['communities'] = communities;
      }
    } catch (e) {
      print('❌ Error updating last message: $e');
    }
  }

  /// Rebuild user_communities index (fallback if data is missing)
  /// This should ideally be done server-side
  Future<bool> rebuildUserCommunitiesIndex(String userId) async {
    try {
      print('🔄 Rebuilding user_communities index for: $userId');

      // Scan community members to find user's communities
      final memberQuery = await _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      if (memberQuery.docs.isEmpty) {
        print('⚠️ No communities found for user');
        return false;
      }

      // Extract community IDs
      final communityIds = memberQuery.docs
          .map((doc) => doc.reference.parent.parent!.id)
          .toSet()
          .toList();

      // Fetch community details
      List<Map<String, dynamic>> communities = [];
      int totalUnread = 0;

      for (final communityId in communityIds) {
        final communityDoc = await _firestore
            .collection('communities')
            .doc(communityId)
            .get();

        if (!communityDoc.exists) continue;

        final communityData = communityDoc.data()!;
        final memberData = memberQuery.docs
            .firstWhere((doc) => doc.reference.parent.parent!.id == communityId)
            .data();

        final unreadCount = (memberData['unreadCount'] as num?)?.toInt() ?? 0;
        totalUnread += unreadCount;

        communities.add({
          'communityId': communityId,
          'communityName': communityData['name'] ?? 'Community',
          'communityIcon': communityData['icon'] ?? '💬',
          'lastMessageAt':
              communityData['lastMessageAt'] ?? communityData['createdAt'],
          'unreadCount': unreadCount,
          'isMuted': memberData['muteNotifications'] ?? false,
        });
      }

      // Sort by last message time
      communities.sort((a, b) {
        final aTime =
            (a['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final bTime =
            (b['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      // Get user info
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() ?? {};

      // Write to user_communities collection
      await _firestore.collection('user_communities').doc(userId).set({
        'userId': userId,
        'userName': userData['name'] ?? 'User',
        'userEmail': userData['email'] ?? '',
        'userRole': userData['role'] ?? 'student',
        'schoolCode': userData['instituteId'] ?? '',
        'className': userData['className'] ?? '',
        'section': userData['section'] ?? '',
        'communityIds': communityIds,
        'communities': communities,
        'totalCommunities': communities.length,
        'totalUnread': totalUnread,
        'lastUpdated': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear cache to force refresh
      clearCache();

      print(
        '✅ Rebuilt user_communities index: ${communities.length} communities',
      );
      return true;
    } catch (e) {
      print('❌ Error rebuilding user_communities index: $e');
      return false;
    }
  }
}
