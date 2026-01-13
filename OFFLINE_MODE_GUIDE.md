# Offline Support Implementation Guide

## Overview
This app now supports complete offline functionality for all four roles:
- Student
- Teacher  
- Parent
- Institute

## Architecture

### Core Services

#### 1. **ConnectivityService** (`lib/services/connectivity_service.dart`)
Monitors network connectivity state globally.

**Usage:**
```dart
final connectivity = ConnectivityService();
bool isOnline = connectivity.isOnline;
bool isOffline = connectivity.isOffline;

// Listen to changes
connectivity.onConnectivityChanged.listen((isOnline) {
  print('Connection changed: $isOnline');
});
```

#### 2. **OfflineCacheManager** (`lib/services/offline_cache_manager.dart`)
Unified cache manager for all app data types.

**Manages:**
- Groups (all roles)
- Communities
- Messages (cached after API calls)
- Daily content
- Dashboards (role-specific)
- Profiles & user data
- Leaderboards
- Announcements

**Usage:**
```dart
final cacheManager = OfflineCacheManager();

// Cache data
await cacheManager.cacheGroups(
  userId: userId,
  role: 'student',
  groupsList: groups,
);

// Retrieve data
final cachedGroups = cacheManager.getCachedGroups(
  userId: userId,
  role: 'student',
);
```

#### 3. **LocalCacheService** (`lib/services/local_cache_service.dart`)
Handles media messages and session data (already in app).

## Integration Patterns

### Pattern 1: Service-Level Offline Support

Add offline support to any service using helper classes:

**For Group Messaging:**
```dart
import 'services/group_messaging_offline_support.dart';

// Use offline-aware stream
final messagingService = GroupMessagingService();
final messages = messagingService.getGroupMessagesWithOfflineSupport(
  classId,
  subjectId,
);
```

**For Communities:**
```dart
import 'services/community_service_offline_support.dart';

// Online or cached messages
final messages = await CommunityServiceOfflineSupport
    .getMessagesWithOfflineSupport(
  communityId: communityId,
  communityService: communityService,
);
```

### Pattern 2: Provider-Level Offline Support

Use the `OfflineSupportMixin` in providers:

```dart
class StudentProvider extends ChangeNotifier with OfflineSupportMixin {
  Future<void> loadStudentData(String studentId) async {
    final data = await loadFromCacheIfOffline(
      onlineLoader: () => _fetchStudentDataFromFirestore(studentId),
      cacheLoader: () => ProviderOfflineHelpers
          .getCachedStudentData(studentId),
      cacheKey: 'student_$studentId',
    );
    
    if (data != null) {
      _studentData = data;
      notifyListeners();
    }
  }
}
```

### Pattern 3: Manual Offline Handling

For specific operations:

```dart
import 'services/offline_provider_support.dart';

if (ProviderOfflineHelpers.isOnline()) {
  // Perform online operation
  await performNetworkOperation();
} else {
  // Load from cache
  final cached = ProviderOfflineHelpers.getCachedStudentData(userId);
  if (cached != null) {
    // Use cached data
  }
}
```

## Implementation Checklist

### For Each Provider/Service

- [ ] Import `ConnectivityService` and `OfflineCacheManager`
- [ ] Check `ConnectivityService.isOnline` before network calls
- [ ] Cache data after successful API responses
- [ ] Load from cache using `OfflineCacheManager` when offline
- [ ] Handle null/empty cache gracefully (show existing empty states)
- [ ] Do not modify UI layouts or add offline indicators
- [ ] Ensure role-based access rules are maintained in cache

### For Streams

If implementing Firestore streams, use offline-aware approach:

```dart
Stream<List<T>> getDataWithOfflineSupport() {
  final connectivity = ConnectivityService();
  
  return connectivity.onConnectivityChanged.asyncExpand((isOnline) async* {
    if (isOnline) {
      // Stream from Firestore and cache
      yield* firestoreStream.doOnData((data) async {
        await cacheManager.cache(data);
      });
    } else {
      // Load from cache
      final cached = cacheManager.getFromCache();
      if (cached != null) yield cached;
      yield* Stream.empty();
    }
  });
}
```

## Cache Management

### Automatic Cache Clearing

Cache is automatically cleared on logout:

```dart
// In auth/logout flow
await OfflineCacheManager().clearAllCache();
```

### Manual Cache Clearing

```dart
final cacheManager = OfflineCacheManager();

// Clear specific conversation
await cacheManager.deleteConversationCache('conv_id');

// Clear specific media
await cacheManager.deleteMediaCache('media_id');

// Clear all
await cacheManager.clearAllCache();
```

### Cache Statistics

```dart
final stats = await cacheManager.getCacheStats();
print('Cached groups: ${stats['groups']}');
print('Cached communities: ${stats['communities']}');
```

## Role-Based Offline Access

### Student Role
- ✅ Cached groups/subjects
- ✅ Community messages & data
- ✅ Daily content & challenges
- ✅ Student dashboard
- ✅ Profile data
- ✅ Leaderboards

### Teacher Role
- ✅ Assigned classes/subjects
- ✅ Group messages
- ✅ Teacher dashboard
- ✅ Profile data
- ✅ Announcements

### Parent Role
- ✅ Child information
- ✅ Parent-teacher messages
- ✅ Parent dashboard
- ✅ Reports

### Institute Role
- ✅ Institution announcements
- ✅ Dashboard data
- ✅ Profile data

## Data Sync on Reconnection

When connection is restored:

1. **Automatic**: Firestore streams resume fetching fresh data
2. **Manual**: Services refresh data and update cache
3. **Transparent**: UI shows fresh data without indicating sync

**No user action required.**

## Testing Offline Mode

### Simulator/Device:
1. Turn off WiFi and Mobile data
2. App continues to function with cached data
3. Turn connection back ON
4. App automatically resumes syncing

### Manual Testing:
```dart
// Force offline mode for testing
final connectivity = ConnectivityService();
// Note: Only for testing, requires code modification
```

## Performance Notes

- **Cache size**: Unlimited by design (Hive handles compression)
- **Sync overhead**: Minimal (only caches successful responses)
- **Memory impact**: Negligible (Hive uses efficient serialization)
- **Battery impact**: Neutral (no background services)

## Non-Goals (Not Implemented)

❌ Offline message composition/sending  
❌ Background sync services  
❌ Conflict resolution for edited messages  
❌ Bandwidth optimization  
❌ Custom offline UI indicators  

## Troubleshooting

### Data Not Showing Offline
- Check cache initialization in `main.dart`
- Verify data was fetched online first (cache needs data to cache)
- Check user role matches cache scope

### Cache Growing Too Large
- Normal behavior - Hive compresses automatically
- Clear old caches: `cacheManager.clearAllCache()`

### Connectivity Detection Not Working
- Ensure `connectivity_plus` is installed
- Check Android/iOS permissions (handled by plugin)

## Future Enhancements

- Selective cache clearing per role
- Cache TTL (time-to-live) management
- Cache compression analytics
- Offline read-only UI mode indicator
