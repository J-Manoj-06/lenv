// QUICK INTEGRATION GUIDE FOR OFFLINE SUPPORT
// Copy & paste patterns to add offline to any service or provider

// ============================================
// PATTERN 1: Stream with Offline Support
// ============================================

import 'services/connectivity_service.dart';
import 'services/offline_cache_manager.dart';

Stream<List<GroupData>> getGroupsWithOfflineSupport(String userId) async* {
  final connectivity = ConnectivityService();
  final cache = OfflineCacheManager();
  
  await for (final isOnline in connectivity.onConnectivityChanged) {
    if (isOnline) {
      try {
        // Online: fetch fresh data and cache it
        final groups = await _fetchGroupsFromFirestore(userId);
        await cache.cacheGroups(
          userId: userId,
          role: 'student',
          groupsList: groups,
        );
        yield groups;
      } catch (e) {
        // Fetch failed, try cache
        final cached = cache.getCachedGroups(
          userId: userId,
          role: 'student',
        );
        if (cached != null) yield cached;
      }
    } else {
      // Offline: load from cache
      final cached = cache.getCachedGroups(
        userId: userId,
        role: 'student',
      );
      if (cached != null) {
        yield cached;
      }
      // Keep listening for reconnection
    }
  }
}

// ============================================
// PATTERN 2: One-time Fetch with Cache
// ============================================

Future<List<CommunityData>> getCommunitiesWithFallback(String userId) async {
  final connectivity = ConnectivityService();
  final cache = OfflineCacheManager();
  
  if (connectivity.isOnline) {
    try {
      final communities = await _fetchCommunitiesFromFirestore(userId);
      // Cache for offline
      await cache.cacheCommunities(
        userId: userId,
        communities: communities,
      );
      return communities;
    } catch (e) {
      // Fall through to cache
    }
  }
  
  // Offline or fetch failed: use cache
  final cached = cache.getCachedCommunities(userId);
  return cached ?? [];
}

// ============================================
// PATTERN 3: Provider with Offline Support
// ============================================

import 'services/offline_provider_support.dart';

class StudentProvider extends ChangeNotifier {
  Future<void> loadDashboard(String studentId) async {
    // Method 1: Simple cache fallback
    if (ProviderOfflineHelpers.isOnline()) {
      try {
        final dashboard = await _fetchDashboardFromFirestore(studentId);
        await ProviderOfflineHelpers.cacheDashboardData(
          userId: studentId,
          role: 'student',
          dashboardData: dashboard,
        );
        _dashboard = dashboard;
        notifyListeners();
        return;
      } catch (e) {
        // Fall through to cache
      }
    }
    
    // Load from cache if offline or fetch failed
    final cached = ProviderOfflineHelpers.getCachedDashboard(
      userId: studentId,
      role: 'student',
    );
    
    if (cached != null) {
      _dashboard = cached;
      notifyListeners();
    }
  }
}

// ============================================
// PATTERN 4: Role-Based Offline Data
// ============================================

class TeacherProvider extends ChangeNotifier {
  Future<void> loadTeacherDashboard(String teacherId) async {
    final cache = OfflineCacheManager();
    
    // Fetch online if available
    if (ConnectivityService().isOnline) {
      try {
        final dashboard = await _fetchTeacherDashboard(teacherId);
        await cache.cacheDashboard(
          userId: teacherId,
          role: 'teacher',
          dashboardData: dashboard,
        );
        _dashboard = dashboard;
        notifyListeners();
        return;
      } catch (e) {
        // Continue to cache
      }
    }
    
    // Load cached teacher dashboard
    final cached = cache.getCachedDashboard(
      userId: teacherId,
      role: 'teacher',
    );
    
    if (cached != null) {
      _dashboard = cached;
      notifyListeners();
    }
  }
}

// ============================================
// PATTERN 5: Message Caching
// ============================================

class ChatProvider extends ChangeNotifier {
  Future<void> loadMessages(String conversationId) async {
    final cache = OfflineCacheManager();
    
    if (ConnectivityService().isOnline) {
      try {
        final messages = await _fetchMessagesFromFirestore(conversationId);
        // Cache messages for offline access
        final messageData = messages
            .map((m) => m.toJson())
            .toList();
        
        await cache.cacheUserData(
          userId: conversationId,
          dataType: 'messages',
          data: messageData,
        );
        
        _messages = messages;
        notifyListeners();
        return;
      } catch (e) {
        // Fall to cache
      }
    }
    
    // Load cached messages
    final cached = cache.getCachedUserData(
      userId: conversationId,
      dataType: 'messages',
    );
    
    if (cached != null) {
      _messages = (cached as List)
          .map((m) => Message.fromJson(m))
          .toList();
      notifyListeners();
    }
  }
}

// ============================================
// PATTERN 6: Listening to Connectivity Changes
// ============================================

class AppProvider extends ChangeNotifier {
  StreamSubscription? _connectivitySubscription;
  
  void startMonitoringConnectivity() {
    final connectivity = ConnectivityService();
    
    _connectivitySubscription =
        connectivity.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        print('Back online - syncing data...');
        // Trigger data refresh for all providers
        refreshAllData();
      } else {
        print('Offline - using cached data');
        // Show cached data (already loaded)
      }
    });
  }
  
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

// ============================================
// IMPLEMENTATION TIPS
// ============================================

/*
1. ALWAYS check ConnectivityService.isOnline before network calls
2. ALWAYS cache successful API responses
3. ALWAYS load from cache when offline
4. DO NOT modify UI - use existing empty states if cache is empty
5. DO NOT add loading indicators or offline badges
6. DO NOT clear cache on network errors (keep stale data)
7. DO refresh cache when connection is restored
8. DO clear cache on logout (already handled)

TESTING OFFLINE:
- Turn off WiFi + Mobile data on device/simulator
- App should display all previously loaded data
- Turn connection back on
- App should automatically sync when possible

KEY SERVICES:
- ConnectivityService.isOnline → boolean check
- ConnectivityService.onConnectivityChanged → stream listener
- OfflineCacheManager → unified cache for all data types
- ProviderOfflineHelpers → quick cache methods for providers
*/
