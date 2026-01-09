# Debug Guide: Infinite Loading Issue

## Summary
Debug logging has been added to trace where the infinite loading occurs on the **home page** and **rewards page**.

## What to Look For

### 1. Student Dashboard (Home Page)
**File:** `lib/screens/student/student_dashboard_screen.dart`

Expected log sequence:
```
🏠 StudentDashboard: initState called
🏠 StudentDashboard: Post-frame callback triggered
🏠 StudentDashboard: Calling _loadDashboardData()
🏠 _loadDashboardData: Starting...
🏠 _loadDashboardData: Auth status - currentUser=..., isLoading=...
✅ _loadDashboardData: Loading dashboard for user: [studentId]
```

Then from `StudentProvider`:
```
🚀 Starting loadDashboardData for student: [studentId]
📦 Attempting to load from cache...
✅ Loaded student data from cache: [Name]
🔥 Loading from Firestore...
✅ Firestore fetch complete: [Name]
💾 Caching fresh student data...
✅ Cache saved
📚 Loading today's challenge...
✅ Challenge loaded: [Challenge Title]
✅ Checking if student attempted challenge...
✅ Attempt status: [true/false]
🔔 Loading notifications...
✅ Notifications loaded: [N] items
📊 Updating student stats...
✅ Stats updated
✅ Dashboard data loading COMPLETE
✅ notifyListeners() called - _isLoading set to false
```

**If you see:** A log message but no "COMPLETE", the async operation after it is hanging.

---

### 2. Rewards Catalog Page
**File:** `lib/features/rewards/ui/screens/rewards_catalog_screen.dart`

Expected log sequence:
```
🎁 RewardsCatalogScreen: Building with searchQuery=""
```

Then from providers:
```
🎁 rewardsCatalogProvider: Starting catalog fetch...
```

Then from repository:
```
🎁 getCatalog: Starting (forceRefresh=false)
🔥 getCatalog: Fetching from Firestore collection: rewards_catalog
✅ getCatalog: Firestore returned [N] documents
✅ getCatalog: Mapped to [N] products
✅ rewardsCatalogProvider: Successfully loaded [N] products
✅ RewardsCatalogScreen: Data loaded with [N] products
```

**Or fallback (if Firestore empty):**
```
⚠️ getCatalog: Firestore is empty, loading dummy catalog
📄 _loadDummyCatalog: Starting...
✅ _loadDummyCatalog: Loaded JSON from assets
✅ _loadDummyCatalog: Parsed [N] products from dummy data
```

**If you see:** Loading state persists or error appears.

---

### 3. Parent Dashboard (Home Page - Parent Account)
**File:** `lib/screens/parent/parent_dashboard_screen.dart`

Expected log sequence:
```
👨‍👩‍👧 ParentDashboard: initState called
👨‍👩‍👧 ParentDashboard: Post-frame callback triggered, calling _initializeParentData()
👨‍👩‍👧 _initializeParentData: Starting initialization
👨‍👩‍👧 _initializeParentData: Initializing with email=[email], id=[parentId]
👨‍👩‍👧 _initializeParentData: Initialization complete, isLoadingChildren=false
```

---

### 4. Real-time Points Stream
**File:** `lib/features/rewards/services/rewards_repository.dart`

Expected log sequence (when points are watched):
```
💰 streamStudentPoints: Creating stream for student: [studentId]
💰 streamStudentPoints: Snapshot received for [studentId] with [N] documents
✅ streamStudentPoints: Total points for [studentId]: [points]
```

**Or fallback:**
```
⚠️ streamStudentPoints: No rewards found, checking students collection
✅ streamStudentPoints: Fallback points for [studentId]: [points]
```

---

## How to Read Logs

### Step 1: Run the app in debug mode
```bash
flutter run -v
```

### Step 2: Navigate to the problematic screen
- For home page: Restart app and check if the "Fetching your details..." spinner disappears
- For rewards page: Navigate to rewards section and check if products load

### Step 3: Check the console output
Look for the emoji prefixes:
- ✅ = Success
- 🚀 = Starting operation
- ⏳ = Loading
- ❌ = Error
- ⚠️ = Warning/Fallback
- 🔄 = Already loaded/cached
- 🔥 = Firestore operation
- 💾 = Cache operation
- 📦 = From cache
- 🎁 = Rewards catalog
- 💰 = Points/rewards data
- 👨‍👩‍👧 = Parent dashboard
- 🏠 = Student dashboard

### Step 4: Identify the stall point
**The last log message before the spinner persists is where the hang occurs.**

For example, if you see:
```
✅ Firestore fetch complete: John
💾 Caching fresh student data...
[NO MORE LOGS]
```

Then the issue is in `CacheManager.cacheStudentData()` - it's not completing.

---

## Common Causes

### 1. Firestore timeout
- Look for: `Firestore timeout` message
- **Fix:** Check internet connection, Firestore rules, collection naming

### 2. Async operation not completing
- Look for: Missing ✅ after an operation starts
- **Fix:** Check try/catch blocks, ensure all await calls resolve

### 3. Provider infinite loop
- Look for: Same log repeating multiple times
- **Fix:** Check provider dependencies, watch() calls, state mutations

### 4. Missing data in Firestore
- Look for: `Firestore returned 0 documents` or `⚠️ Using cached data`
- **Fix:** Ensure data exists in Firestore collections, check queries

---

## Next Steps

1. **Run the app** and navigate to the problematic page
2. **Copy the console output**
3. **Share the last 50 lines** showing where logs stop
4. I can then identify the exact issue and apply a fix

---

## To Remove Debug Logs Later

Once the issue is fixed, search for these patterns and remove them:
- `print('🎁` 
- `print('🚀`
- `print('💰`
- `print('🏠`
- `print('👨‍👩‍👧`
- `print('✅`
- `print('❌`
- All other print statements I added

Or run: `dart format .` and I can provide cleanup script.
