# Remember Me Feature - Architecture Diagrams

## 1. Complete Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         APP LIFECYCLE                            │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────────────┐
│   APP STARTS (First Time)    │
└──────────────────────┬───────┘
                       │
                       ▼
            ┌──────────────────────┐
            │ SessionManager Check │
            │ (getLoginSession)    │
            └──────┬───────────────┘
                   │
         ┌─────────┴────────────┐
         │                      │
         ▼                      ▼
    SESSION?              NO SESSION?
         │                      │
         │                      └──────────────────┐
         │                                         │
         ▼                                         ▼
    Firebase User              ┌──────────────────────────┐
    Validation                 │ Show Role Selection      │
         │                     │ (student/teacher/parent) │
         │                     └──────────────────────────┘
         │
         ▼
    ┌──────────────────────────────────────┐
    │ StudentDashboardScreen Loads         │
    │ (StudentProvider.loadDashboardData)  │
    └──────────────────┬───────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
    ┌─────────────────┐       ┌─────────────────────┐
    │  Load Cache     │       │  Load Firestore     │
    │  (1 sec)        │       │  (3 sec background) │
    │                 │       │                     │
    │ ✅ Instant      │       │ 🔄 Fresh data      │
    │ ✅ Shows data   │       │ ✅ Updates UI       │
    └────────┬────────┘       └────────┬────────────┘
             │                         │
             └──────────────┬──────────┘
                            │
                            ▼
                   ┌────────────────────┐
                   │ Dashboard Display  │
                   │ (Full & Updated)   │
                   └────────────────────┘
```

## 2. Cache Loading Strategy

```
StudentProvider.loadDashboardData()
│
├─ PHASE 1: Cache Load (1-2 seconds)
│  │
│  └─ CacheManager.getStudentDataCache(studentId)
│     │
│     ├─ Read from SharedPreferences
│     ├─ Deserialize JSON → StudentModel
│     ├─ Return to Provider
│     │
│     ▼
│     ✅ Update _currentStudent
│     ✅ notifyListeners()  ← UI updates NOW
│     ✅ Show cached name, profile, streak
│
├─ PHASE 2: Firestore Sync (1-3 seconds, parallel)
│  │
│  ├─ _studentService.getCurrentStudent()
│  │  │
│  │  └─ Query Firestore
│  │     │
│  │     ▼
│  │     ✅ Receive fresh data
│  │
│  ├─ CacheManager.cacheStudentData(fresh)
│  │  │
│  │  └─ Update SharedPreferences with fresh data
│  │
│  └─ Update _currentStudent with fresh data
│     └─ notifyListeners()  ← UI updates with fresh data
│
└─ PHASE 3: Error Handling
   │
   ├─ If Firestore fails:
   │  └─ Cache remains valid & usable
   │
   └─ If both fail:
      └─ User sees error but keeps cached data
```

## 3. Logout Complete Data Clearing

```
StudentProfileScreen._onLogout()
│
├─ Step 1: DailyChallengeProvider.clearAllState()
│  └─ Clears challenge cache in SharedPreferences
│
├─ Step 2: StudentProvider.clear()
│  │
│  ├─ _currentStudent = null
│  ├─ _todayChallenge = null
│  ├─ _notifications = []
│  ├─ _hasLoaded = false
│  │
│  └─ CacheManager.clearStudentDataCache()
│     └─ Remove _studentDataKey from SharedPreferences
│        └─ Remove _studentDataTimestampKey
│
├─ Step 3: AuthProvider.signOut()
│  │
│  └─ prefs.clear()
│     └─ 🔥 WIPES ALL SharedPreferences
│        (This is extra insurance - wipes everything)
│
└─ Step 4: Navigate to /role-selection
   │
   ├─ Clear all routes
   └─ Show role selection screen
      └─ No student data accessible
         └─ No cache loaded
```

## 4. SessionManager Integration Flow

```
LOGIN FLOW
─────────────────────────────────────────────────────────────

StudentLoginScreen
│
├─ User enters credentials
│
├─ Firebase.signInWithEmailAndPassword()
│  │
│  └─ ✅ Auth succeeds OR ❌ Auth fails
│
├─ If ✅ Auth succeeds:
│  │
│  └─ SessionManager.saveLoginSession(
│       userId: user.uid,
│       userRole: 'student',
│       schoolId: user.instituteId
│     )
│     │
│     └─ Stores in SharedPreferences:
│        ├─ login_user_id: uid
│        ├─ login_user_role: 'student'
│        ├─ login_school_id: schoolId
│        └─ login_timestamp: now
│
├─ Navigate to StudentDashboardScreen
│
└─ StudentDashboardScreen loads:
   └─ StudentProvider.loadDashboardData()
      ├─ Load cache (1 sec)
      └─ Sync Firestore (background)


REOPEN APP FLOW
─────────────────────────────────────────────────────────────

App Start → SessionManager.getLoginSession()
│
├─ Read from SharedPreferences
│  ├─ Get login_user_id
│  ├─ Get login_user_role
│  └─ Get login_school_id
│
├─ Validate in Firebase:
│  ├─ Get current Firebase user
│  ├─ Compare user.uid with saved login_user_id
│  └─ ✅ Match OR ❌ No match
│
├─ If ✅ Valid session:
│  │
│  ├─ Return LoginSession object
│  │
│  └─ App routes to StudentDashboardScreen
│     └─ StudentProvider.loadDashboardData()
│        ├─ Load cache (1 sec) ← Data visible NOW
│        └─ Sync Firestore (background)
│
└─ If ❌ Invalid/Expired session:
   │
   └─ Navigate to role-selection screen
      └─ User must login again
```

## 5. Multi-Account Isolation

```
ACCOUNT SWITCHING - Data Isolation Guaranteed
────────────────────────────────────────────

Scenario: Switch from StudentA to StudentB

┌──────────────────────┐
│ StudentA Logged In   │
│ Cache contains:      │
│ • _studentDataKey    │ (StudentA's data)
│ • _timestamp         │ (StudentA's time)
└──────┬───────────────┘
       │
       ▼
    Logout
       │
       ├─ CacheManager.clearStudentDataCache()
       │  └─ Remove _studentDataKey
       │     └─ Remove _timestamp
       │
       ├─ prefs.clear()
       │  └─ 🔥 WIPES ALL prefs
       │
       └─ SessionManager.clearLoginSession()
          └─ Remove login_user_id (StudentA's ID)
             └─ Remove login_user_role
                └─ Remove login_school_id

     ✅ ALL DATA GONE

┌──────────────────────┐
│ StudentB Logs In     │
│ Cache now contains:  │
│ • _studentDataKey    │ (StudentB's data ONLY)
│ • _timestamp         │ (StudentB's time)
│                      │
│ ❌ NO StudentA data  │ ← Complete isolation!
└──────────────────────┘
```

## 6. Offline Mode Handling

```
OFFLINE MODE SCENARIO
────────────────────────────────────────────

App Running + Cache Populated
│
├─ Enable Airplane Mode
│  └─ WiFi & Cellular OFF
│
├─ Close App
│
└─ Reopen App (Still Airplane Mode)
   │
   ├─ SessionManager.getLoginSession()
   │  └─ Firebase check times out
   │     └─ Continue anyway (cached session)
   │
   ├─ StudentProvider.loadDashboardData()
   │  │
   │  ├─ PHASE 1: Cache Load
   │  │  ├─ Load from SharedPreferences ✅
   │  │  ├─ UI shows data immediately
   │  │  └─ Console: "📦 Loaded from cache"
   │  │
   │  └─ PHASE 2: Firestore Sync
   │     ├─ Try to query Firestore
   │     ├─ No internet → Timeout
   │     ├─ Catch error
   │     └─ Fall back to cache (already showing)
   │        └─ Console: "⚠️ Using offline mode"
   │
   └─ ✅ Dashboard fully functional
      └─ Can view all cached data


COMING ONLINE
────────────────────────────────────────────

Disable Airplane Mode
│
└─ Connection restored
   │
   ├─ App detects online
   │
   ├─ StudentProvider.loadDashboardData() runs again
   │  │
   │  ├─ PHASE 2: Firestore Sync now succeeds
   │  │  ├─ Query Firestore ✅
   │  │  ├─ Receive fresh data
   │  │  └─ Update cache with fresh data
   │  │
   │  └─ Update UI with fresh data
   │     └─ Console: "💾 Cached fresh data"
   │
   └─ ✅ App now fully synced
```

## 7. Cache Lifecycle

```
CACHE LIFECYCLE - StudentModel
────────────────────────────────────────────

Login → Create Cache
│
├─ Student logs in successfully
│
├─ StudentProvider.loadDashboardData() runs
│
├─ Step 1: Load Firestore
│  └─ Fetch StudentModel
│
├─ Step 2: Cache it
│  └─ CacheManager.cacheStudentData(student)
│     └─ Serialize with toFirestore()
│        └─ Store in SharedPreferences
│           └─ Set timestamp (now)
│              └─ ✅ Cache ready
│
└─ Cache Age: 0 minutes


Use Cache → Check Validity
│
├─ Next session (app restart)
│
├─ Check: isStudentDataCacheValid()
│  └─ Get timestamp from cache
│     └─ Calculate age = now - timestamp
│        └─ Compare: age < 1 hour? (default)
│
├─ ✅ If valid:
│  └─ Use cached data
│
└─ ❌ If expired (> 1 hour):
   └─ Force refresh from Firestore


Logout → Clear Cache
│
├─ Call clear()
│
├─ CacheManager.clearStudentDataCache()
│  └─ Remove _studentDataKey
│     └─ Remove _timestamp
│
└─ ✅ Cache destroyed
   └─ Completely gone


Cache Age Over Time
──────────────────────────────────────
0-1 hour:  ✅ Valid - Use cache
1-24 hour: ⚠️  Stale - But still usable
>24 hour:  ❌ Expired - Force refresh
```

## 8. Provider State Machine

```
StudentProvider State Transitions
────────────────────────────────────────────

INITIAL
  │
  ├─ _currentStudent = null
  ├─ _hasLoaded = false
  └─ _isLoading = false
       │
       ▼
   LOADING
       │
       ├─ _isLoading = true
       │
       ├─ Load from cache
       │  └─ _currentStudent = cachedStudent
       │     └─ notifyListeners() [UI UPDATE 1]
       │
       ├─ Load from Firestore
       │  └─ _currentStudent = freshStudent
       │     └─ notifyListeners() [UI UPDATE 2]
       │
       └─ _hasLoaded = true
            │
            ▼
        LOADED & SYNCED
            │
            ├─ _currentStudent = data
            ├─ _hasLoaded = true
            └─ _isLoading = false
                 │
         ┌───────┴───────┐
         │               │
    REFRESH         LOGOUT
    (same flow)          │
         │               ▼
         │         CLEARING
         │               │
         │          clear()
         │               │
         │          ├─ _currentStudent = null
         │          ├─ _hasLoaded = false
         │          ├─ Clear cache
         │          └─ notifyListeners()
         │               │
         │               ▼
         │            CLEARED
         │               │
         └───────────────┘
                 │
                 ▼
             INITIAL (reset)
```

## 9. Cache Key Architecture

```
CacheManager Keys Structure
────────────────────────────────────────────

SharedPreferences Storage:
{
  // Student Data
  "_student_cache_data": "{StudentModel JSON}",
  "_student_cache_timestamp": 1704067200000,
  
  // Generic Cache (for future use)
  "custom_key_name": "{JSON}",
  "custom_key_name_timestamp": 1704067200000,
  
  // Other Data (SessionManager, AuthProvider, etc.)
  "login_user_id": "uid123",
  "login_user_role": "student",
  "login_school_id": "school123",
  ...
}

Keys Clear on Logout:
  ON: CacheManager.clearAllCaches()
    • Searches for all keys containing "_cache"
    • Removes _student_cache_data
    • Removes _student_cache_timestamp
    • Removes any custom cache keys
    
  ON: AuthProvider.signOut()
    • prefs.clear() ← WIPES EVERYTHING above
    • Complete nuclear option
```

## 10. Error Scenarios & Recovery

```
ERROR SCENARIOS & RECOVERY PATHS
────────────────────────────────────────────

Scenario 1: Firestore Fails, Cache Valid
──────────────────────────────────────
loadDashboardData()
  │
  ├─ Load cache ✅
  ├─ Show to user ✅
  │
  └─ Load Firestore
     ├─ ❌ Connection error
     ├─ ❌ Catch exception
     │
     └─ Use cached data
        └─ ✅ User sees old but valid data
           └─ Console: "Error syncing: Connection lost"


Scenario 2: Cache Expired, Firestore OK
──────────────────────────────────────
loadDashboardData()
  │
  ├─ Load cache
  │  ├─ Check timestamp
  │  ├─ Age > 1 hour? YES
  │  └─ ❌ Cache too old, skip
  │
  ├─ Load Firestore
  │  └─ ✅ Succeeds
  │
  ├─ Update cache
  │  └─ Fresh data now cached
  │
  └─ ✅ User sees fresh data


Scenario 3: No Cache, No Firestore
──────────────────────────────────────
loadDashboardData()
  │
  ├─ Load cache
  │  └─ ❌ Not found
  │
  ├─ Load Firestore
  │  └─ ❌ Connection error
  │
  ├─ Catch exception
  │  └─ _errorMessage = "Failed to load..."
  │
  └─ ❌ Show error to user
     └─ "Unable to load. Check connection."
```

---

## Summary

The Remember Me feature implements a robust, multi-layered approach to persistent login:

1. **SessionManager** - Persists login session across app restarts
2. **CacheManager** - Stores student data for instant display
3. **StudentProvider** - Dual-load strategy (cache first, Firestore sync)
4. **Offline Support** - App works with cached data when offline
5. **Data Isolation** - Complete cache wipe on logout
6. **Error Handling** - Graceful fallback if Firestore fails

This architecture ensures the best possible user experience while maintaining security and data integrity.
