import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/offline_cache_manager.dart';
import '../services/network_service.dart';
import '../models/community_model.dart';

/// Repository for managing principal/institute dashboard data
/// Handles API calls, caching, and offline mode
class PrincipalDashboardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OfflineCacheManager _cacheManager = OfflineCacheManager();
  final NetworkService _networkService = NetworkService();

  /// Fetch dashboard stats with offline support
  /// Returns: students count, staff count, attendance data
  Future<Map<String, dynamic>> fetchDashboardStats(String schoolCode) async {
    // Check connectivity
    final isConnected = await _networkService.isConnected();

    if (isConnected) {
      try {
        // Fetch fresh data
        final stats = await _fetchStatsFromFirebase(schoolCode);

        // Cache the data
        await _cacheManager.cachePrincipalStats(
          schoolCode: schoolCode,
          stats: stats,
        );

        return stats;
      } catch (e) {
        debugPrint('Error fetching dashboard stats: $e');
        // Fall through to cache
      }
    }

    // Return cached data
    final cached = _cacheManager.getCachedPrincipalStats(schoolCode);
    if (cached != null) {
      return cached;
    }

    // No data available
    return {
      'students': 0,
      'staff': 0,
      'attendance': {'present': 0, 'total': 0, 'percent': 0.0},
      'fromCache': false,
    };
  }

  /// Fetch stats from Firebase
  Future<Map<String, dynamic>> _fetchStatsFromFirebase(
    String schoolCode,
  ) async {
    // Get student count
    final studentsQuery = await _firestore
        .collection('students')
        .where('schoolCode', isEqualTo: schoolCode)
        .get();
    final studentCount = studentsQuery.size;

    // Get staff count
    final staffQuery = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('schoolCode', isEqualTo: schoolCode)
        .get();
    final staffCount = staffQuery.size;

    // Get today's attendance
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final attendanceQuery = await _firestore
        .collection('attendance')
        .where('schoolCode', isEqualTo: schoolCode)
        .where('date', isEqualTo: dateStr)
        .get();

    int presentCount = 0;
    for (final doc in attendanceQuery.docs) {
      final data = doc.data();
      final students = data['students'] as Map<String, dynamic>?;
      if (students != null) {
        for (final studentEntry in students.entries) {
          final studentData = studentEntry.value as Map<String, dynamic>?;
          if (studentData != null) {
            final status =
                studentData['status']?.toString().toLowerCase() ?? 'present';
            if (status == 'present') {
              presentCount++;
            }
          }
        }
      }
    }

    final attendancePercent = studentCount > 0
        ? (presentCount / studentCount * 100)
        : 0.0;

    return {
      'students': studentCount,
      'staff': staffCount,
      'attendance': {
        'present': presentCount,
        'total': studentCount,
        'percent': attendancePercent,
      },
      'fromCache': false,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Fetch institute communities with offline support
  Future<List<CommunityModel>> fetchInstituteCommunities({
    required String schoolCode,
  }) async {
    // Check connectivity
    final isConnected = await _networkService.isConnected();

    if (isConnected) {
      try {
        // Fetch fresh data from Firestore
        final communities = await _fetchCommunitiesFromFirebase(schoolCode);

        // Cache the data
        final communitiesData = communities
            .map(
              (c) => {
                'id': c.id,
                'name': c.name,
                'slug': c.slug,
                'description': c.description,
                'category': c.category,
                'memberCount': c.memberCount,
                'isActive': c.isActive,
                'visibility': c.visibility,
                'scope': c.scope,
                'schoolCode': c.schoolCode,
                'avatarUrl': c.avatarUrl,
                'standards': c.standards,
                'audienceRoles': c.audienceRoles,
                'joinMode': c.joinMode,
                'messageCount': c.messageCount,
                'lastMessageBy': c.lastMessageBy,
                'lastMessagePreview': c.lastMessagePreview,
                'coverImage': c.coverImage,
                'tags': c.tags,
                'createdBy': c.createdBy,
                'createdByName': c.createdByName,
                'createdByRole': c.createdByRole,
                'rules': c.rules,
                'allowImages': c.allowImages,
                'allowLinks': c.allowLinks,
              },
            )
            .toList();

        await _cacheManager.cacheInstituteCommunities(
          schoolCode: schoolCode,
          communities: communitiesData,
        );

        return communities;
      } catch (e) {
        debugPrint('Error fetching communities: $e');
        // Fall through to cache
      }
    }

    // Return cached data
    final cached = _cacheManager.getCachedInstituteCommunities(schoolCode);
    if (cached != null) {
      return cached.map((data) => _communityFromMap(data)).toList();
    }

    // No data available
    return [];
  }

  /// Fetch communities from Firebase
  Future<List<CommunityModel>> _fetchCommunitiesFromFirebase(
    String schoolCode,
  ) async {
    // Query for institute and principal communities
    final instituteQuery = await _firestore
        .collection('communities')
        .where('isActive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .where('audienceRoles', arrayContains: 'institute')
        .get();

    final principalQuery = await _firestore
        .collection('communities')
        .where('isActive', isEqualTo: true)
        .where('visibility', isEqualTo: 'public')
        .where('audienceRoles', arrayContains: 'principal')
        .get();

    // Merge and deduplicate
    final communityMap = <String, CommunityModel>{};

    for (final doc in [...instituteQuery.docs, ...principalQuery.docs]) {
      final community = CommunityModel.fromFirestore(doc);
      final schoolMatch =
          community.scope == 'global' ||
          (community.scope == 'school' && community.schoolCode == schoolCode);

      if (schoolMatch && !communityMap.containsKey(community.id)) {
        communityMap[community.id] = community;
      }
    }

    final communities = communityMap.values.toList();
    communities.sort((a, b) => b.memberCount.compareTo(a.memberCount));
    return communities;
  }

  /// Convert map to CommunityModel
  CommunityModel _communityFromMap(Map<String, dynamic> data) {
    return CommunityModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      slug: data['slug'] ?? '',
      description: data['description'] ?? '',
      standards: List<String>.from(data['standards'] ?? []),
      audienceRoles: List<String>.from(data['audienceRoles'] ?? []),
      category: data['category'] ?? 'General',
      memberCount: data['memberCount'] ?? 0,
      messageCount: data['messageCount'] ?? 0,
      isActive: data['isActive'] ?? true,
      visibility: data['visibility'] ?? 'public',
      scope: data['scope'] ?? 'global',
      schoolCode: data['schoolCode'],
      joinMode: data['joinMode'] ?? 'open',
      lastMessageBy: data['lastMessageBy'] ?? '',
      lastMessagePreview: data['lastMessagePreview'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      coverImage: data['coverImage'] ?? '',
      tags: List<String>.from(data['tags'] ?? []),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdByRole: data['createdByRole'] ?? '',
      rules: data['rules'] ?? '',
      allowImages: data['allowImages'] ?? false,
      allowLinks: data['allowLinks'] ?? true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Check if data is stale (for refresh logic)
  bool isDataStale(String key) {
    return _cacheManager.isDataStale(
      key: key,
      maxAge: const Duration(hours: 2), // Refresh every 2 hours
    );
  }
}
