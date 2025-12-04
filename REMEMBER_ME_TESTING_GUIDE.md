# Remember Me Feature - Testing Guide

## Quick Start - Testing Steps

### Test 1: Basic Cache Loading ✅
**Objective:** Verify cached data loads on app restart

1. **Login as a student**
   - Open app
   - Navigate to student login
   - Enter credentials
   - Tap login

2. **Close app completely**
   - Use back button or system close
   - Verify app is completely closed (not in background)

3. **Reopen app**
   - Tap app icon to reopen
   - **Expected:** Dashboard should load from cache immediately
   - **Look for:** Student name, profile, streak visible within 1 second
   - **Console logs:** 
     ```
     📦 Loaded student data from cache
     💾 Cached fresh student data
     ```

4. **Verify Firestore sync happens**
   - Wait 2-3 seconds
   - **Expected:** UI updates with fresh Firestore data
   - **Console logs:**
     ```
     ✅ Student data cached
     ```

### Test 2: Logout Clears Cache ✅
**Objective:** Verify logout completely removes cached data

1. **Login as Student A**
   - Login with first account
   - Verify dashboard loads with data

2. **Logout**
   - Tap profile icon → Logout
   - Confirm logout
   - Wait for navigation to /role-selection

3. **Close app**
   - Close app completely

4. **Reopen app**
   - Tap app icon
   - **Expected:** Role selection screen appears (NOT logged in)
   - **NOT Expected:** Student data visible or accessible
   - **Console logs:**
     ```
     ✅ Student data cache cleared
     ```

### Test 3: Multi-Account Isolation ✅
**Objective:** Verify switching accounts doesn't leak data

1. **Login as Student A**
   - Login with first account
   - Note student name, profile picture
   - Logout

2. **Login as Student B**
   - Login with different account
   - Wait for dashboard to load
   - Note different student name/profile
   - **Expected:** Only Student B's data visible
   - **NOT Expected:** Any of Student A's data visible

3. **Close and reopen app**
   - Close app
   - Reopen
   - **Expected:** Still showing Student B's cached data
   - **NOT Expected:** Student A's data

4. **Logout and login as A again**
   - Logout
   - Login as Student A
   - **Expected:** Student A's data visible (either cached or from Firestore)
   - **NOT Expected:** Student B's data visible

### Test 4: Offline Mode ✅
**Objective:** Verify app works offline with cached data

#### 4a: Offline Reading
1. **Login with internet**
   - Login as student
   - Wait for full dashboard load (including Firestore sync)

2. **Enable Airplane Mode**
   - Enable airplane mode (Settings)
   - **Verify:** WiFi and Cellular both off

3. **Close app**
   - Close app completely

4. **Reopen app**
   - Tap app icon while still in airplane mode
   - **Expected:** Dashboard loads from cache
   - **Expected:** All data visible (name, profile, streak, etc.)
   - **Not Expected:** Network errors or blank screen
   - **Console logs:**
     ```
     📦 Loaded student data from cache
     ⚠️ Using cached data (offline mode)
     ```

#### 4b: Online Sync
1. **Still in app (offline)**
   - Disable airplane mode
   - **Expected:** App automatically syncs with Firestore
   - **Expected:** UI updates with fresh data
   - **Console logs:**
     ```
     💾 Cached fresh student data
     ```

2. **Navigate and verify**
   - Tap profile, leaderboard, tests
   - All should load with fresh data

### Test 5: Daily Challenge Cache ✅
**Objective:** Verify challenge persists across app restarts

1. **Login and view daily challenge**
   - Login as student
   - Navigate to daily challenge
   - View today's question

2. **Close app without answering**
   - Close app completely

3. **Reopen app**
   - Open app
   - Navigate to daily challenge
   - **Expected:** Same question appears from cache
   - **Expected:** Correct state shown (not answered yet)

4. **Answer challenge**
   - Answer the challenge
   - Submit answer

5. **Close and reopen**
   - Close app
   - Reopen app
   - Navigate to daily challenge
   - **Expected:** "Already answered" state shown
   - **NOT Expected:** Challenge available to answer again

### Test 6: All Student Screens ✅
**Objective:** Verify all 8 screens work with cache

For each screen below:
1. Login and navigate to screen
2. Verify data displays
3. Close app completely
4. Reopen app
5. Re-navigate to screen
6. **Expected:** Data still visible from cache

**Screens to Test:**
1. ✅ **Dashboard** (`student_dashboard_screen.dart`)
   - Student name, profile, streak visible

2. ✅ **Profile** (`student_profile_screen.dart`)
   - Personal info, stats, class info visible

3. ✅ **Tests** (`student_tests_screen.dart`)
   - List of tests visible
   - Can tap and take test

4. ✅ **Leaderboard** (`student_leaderboard_screen.dart`)
   - Rankings visible
   - Student's position shows

5. ✅ **Rewards** (`student_rewards_screen.dart`)
   - Reward points visible
   - Badge information shows

6. ✅ **Messages** (`student_groups_screen.dart`)
   - Group list visible
   - Can open group chats

7. ✅ **Take Test** (`take_test_screen.dart`)
   - Questions load
   - Can answer and submit

8. ✅ **Daily Challenge** (`daily_challenge_screen.dart`)
   - Challenge loads
   - Can answer and submit

## Manual Testing Session

### Setup
```
Device: Android Device/Emulator
Internet: WiFi on
Time: ~30 minutes per session
Tests: Run in order 1-6
```

### Recording Results

For each test, note:
- **Time:** When you started
- **Status:** ✅ PASS / ❌ FAIL
- **Notes:** What you observed
- **Errors:** Any console errors
- **Screenshots:** Before/after states (if failing)

### Test Results Template

```
Test 1: Basic Cache Loading
- Status: [PASS/FAIL]
- Cache load time: ___ ms
- Firestore sync time: ___ ms
- Errors: [NONE/list]
- Notes: _______________

Test 2: Logout Clears Cache
- Status: [PASS/FAIL]
- Errors: [NONE/list]
- Notes: _______________

... etc
```

## Debugging Tips

### View Cache Contents
Enable in CacheManager (or add print temporarily):
```dart
final stats = await CacheManager.getCacheStats();
print('Cache stats: $stats');
```

### Check SharedPreferences
Android Studio → Device File Explorer → `/data/data/com.yourapp/shared_prefs`

### View Console Logs
```
flutter logs
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Data not loading | Cache expired | Check `isStudentDataCacheValid()` |
| Stale data | Firestore not syncing | Check internet, logs for errors |
| Memory bloat | Cache growing too large | Call `CacheManager.clearAllCaches()` |
| Login loop | Session not saved | Verify `SessionManager.saveLoginSession()` called |
| Logout not working | Cache not cleared | Check `await clear()` is awaited |

## Performance Checklist

- [ ] Cache loads in < 1 second
- [ ] Firestore sync completes within 3 seconds
- [ ] No noticeable UI lag when syncing
- [ ] Memory usage < 100MB when cached
- [ ] Offline mode works smoothly
- [ ] No crashes on app restart
- [ ] No data leaks between accounts

## Sign-Off

Once all tests pass:
1. ✅ Update this file with results
2. ✅ Mark todos as complete
3. ✅ Create final implementation report
4. ✅ Prepare for production deployment

---

**Last Updated:** [TODAY]
**Tested By:** [YOUR NAME]
**Status:** 🟡 TESTING IN PROGRESS
